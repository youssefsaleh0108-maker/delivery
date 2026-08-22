# Phase 5 security review

Carried out against the running stack on 2026-08-09, covering the five areas Section 11 names for
Phase 5: token scopes, MinIO policies, per-connector credential isolation, Vault AppRole scoping,
and the Settings audit log.

Every finding below was verified against the live system, not read off the source. Where a check
passed, the evidence is stated so a re-review can reproduce it rather than take this on trust.

---

## Findings

### 1. Any token from the realm was accepted by every service — FIXED

**Severity: high.** Spring's default JWT validation checks the issuer, the signature and the expiry
and nothing else. Every service trusts the same Keycloak realm, so a token issued to *any* client in
that realm was accepted by *every* service, limited only by the realm roles on it.

Reproduced by adding a `rogue-partner` client to the realm and using it to obtain a token for the
`customer` user. The token carried the `CUSTOMER` realm role and was accepted:

```
rogue token azp: rogue-partner
rogue token has CUSTOMER role: ["CUSTOMER"]
rogue -> /api/orders/mine  : 200      (before the fix)
```

This is not a hypothetical. The realm holds only our own clients today, but the first partner
integration or internal tool added to it would inherit the full API surface — a Keycloak
configuration change silently becoming a security change across fifteen services, with nothing in
this repository to notice.

**Fix:** `AuthorizedPartyValidator` in `platform-security`, wired into both the servlet and reactive
decoders and enabled platform-wide from `config-repo/application.yml`:

```
delivery.security.allowed-client-ids: [mobile-app, backoffice-web, merchant-portal]
```

Matched against `azp`, not `aud`. Keycloak leaves `aud` empty on these public clients unless an
audience mapper is configured per client, and a check that silently passes when someone forgets one
is worse than no check at all. The service-account clients (`notifications-manager`,
`accounting-service`) are deliberately excluded — they call Keycloak's admin API, never ours.

**After the fix:**

```
rogue -> /api/orders/mine  : 401
rogue -> /api/products     : 401
genuine -> /api/orders/mine: 200
```

### 2. Connectors opened their whole `/api/connector/**` prefix — FIXED

**Severity: low.** The three notification connectors permitted the wildcard, so any endpoint later
added under that prefix would have been public by default. Narrowed to the two paths the worker
actually calls, `/api/connector/send` and `/api/connector/status`. The Core Banking connector
already permitted only `/status`, because it has no send endpoint by design.

### 3. Every service port is published to the host — ACCEPTED IN DEV, MUST NOT SHIP

**Severity: high if replicated.** `docker-compose.yml` publishes 8101–8115 to the host. The
endpoints documented as "internal only" — `/api/connector/send`, which sends an arbitrary SMS, and
the simulator's `/test/faults`, which breaks the bank connection — are therefore reachable from the
host machine with no token at all.

This is a deliberate dev affordance and is fine on a laptop. It is the single most important thing
for the Kubernetes manifests to get right: **everything except Traefik must be `ClusterIP`**,
and the Core Banking Simulator must not be deployed outside dev at all. Recorded here because the
compose file is the model those manifests were written from, and copying its port list would carry
this straight into staging.

### 4. The Core Banking Vault policy is unbound — ACCEPTED, WITH REASONING

Section 10 asks for the Core Banking Connector's secret path to have its own Vault policy, separate
from every other service's. `infra/vault/policies/corebanking-connector.hcl` exists and is correct.
It is also bound to no role, and the Config Server's policy grants `read` on `secret/data/*` — which
includes the bank's path.

That is not an oversight so much as the two requirements in Section 10 pulling against each other.
The same section requires that *every* service's secrets route through the Config Server rather than
services holding their own Vault credentials, "which keeps Vault access centralized and auditable in
one place". If the Config Server serves the connector its secrets, it must be able to read them.

So the separation is real as a policy and nominal in effect. Closing it properly means the Core
Banking Connector authenticating to Vault directly with its own AppRole and the Config Server's
blanket read being narrowed to exclude that path — which trades the centralisation Section 10 also
asks for. **That trade is a decision for whoever owns Vault (Section 12, open decision #8), not one
to make silently here.** The policy file is left in place and ready to bind.

### 5. Actuator surface — PASSED

Checked directly against a credential-holding service. Only `health`, `info`, `metrics`,
`prometheus` and `refresh` are exposed; of those only health/info/prometheus are unauthenticated:

```
/actuator/env         : 401        /actuator/health     : 200
/actuator/configprops : 401        /actuator/prometheus : 200
/actuator/beans       : 401
/actuator/heapdump    : 401
/actuator/refresh     : 401
```

`env` and `configprops` matter most — both would render Vault-sourced secrets — and both are closed.
`health` returns only `status` and `groups`, with no component detail, because `show-details` is
`when-authorized`.

`prometheus` being unauthenticated is accepted: it exposes no secrets, is not routed by the Gateway,
and a metrics scraper inside the cluster is its only intended caller.

### 6. MinIO policies — PASSED

`product-images` is the only bucket with anonymous access, and it is read-only; writes still require
a presigned PUT issued to a MERCHANT. `delivery-proof`, `merchant-kyc`, `user-avatars` and
`receipts` are all `none`. `delivery-proof` has versioning plus a noncurrent-expiry rule, so a rider
or a bug cannot silently destroy the only record of a contested delivery. Presigned URLs are
single-object by construction and expire in 10 minutes.

Ten minutes is longer than strictly needed for a GET. It is kept because the same TTL covers the
upload path, where a slow mobile connection uploading a proof-of-delivery photo is a real case, and
splitting the two adds a knob for a risk that is bounded by the URL being single-object anyway.

### 7. Per-connector credential isolation — PASSED

Each connector is its own deployable and reads exactly one credential path. No connector has a
database. No worker has a credential. The one process that could see everything is the Config
Server, which is the intended design (see finding 4).

Verified in passing that the connectors do not log what they hold: `DevLogPushClient` masks device
tokens, which are themselves credentials — anyone holding one can push to that device.

### 8. Settings audit log — PASSED

Verified live in the Phase 3 and Phase 4 smoke tests rather than by reading the code: a provider
switch records the old value, the new value and the acting user's `sub`, in the same transaction as
the change, so an audit trail with a gap in it is not expressible. `assertNoSecrets` rejects any
config key that looks like a credential, which is checked in the smoke test with both an `apiKey`
and a `smtpPassword` field (both 422).

---

## Not covered

- **TLS everywhere, including service-to-service.** Section 10 requires it. The compose stack is
  plaintext on a bridge network. This is a deployment concern, not a code one, and belongs with the
  Kubernetes work — but it is the largest single gap between this stack and the brief's security
  section, and the `/api/connector/send` design explicitly depends on it in production.
- **Keycloak client secret rotation.** The dev secrets are constants in
  `infra/keycloak/apply-realm-updates.sh`, which re-asserts them on every run and so already
  functions as a rotation path. Nothing schedules it.
- **Penetration testing and dependency CVE scanning.** The CI template runs a dependency scan and
  uploads SARIF; no results are reviewed here.

# The platform on k3s: dev and qa on one box

Two full environments — `delivery-dev` and `delivery-qa` namespaces — on a single-node k3s
cluster (8 cores / 24 GB / Contabo). Each namespace runs its own complete stack: Postgres,
Redis, RabbitMQ, MinIO, Keycloak, Vault (dev mode), mailpit, the Config Server and the thirteen
Spring services, all at **replicas: 1**. k3s's bundled Traefik is the one shared edge; the
per-environment hostnames are what keep the two apart on it.

| | dev | qa |
| --- | --- | --- |
| API | api-dev.youdrop.shop | api-qa.youdrop.shop |
| Keycloak | iam-dev.youdrop.shop | iam-qa.youdrop.shop |
| Portal | portal-dev.youdrop.shop | portal-qa.youdrop.shop |
| Ops tools | monitoring-dev.youdrop.shop | monitoring-qa.youdrop.shop |

All records point at the box's IP; TLS is ACME through the bundled Traefik
(`cluster/traefik-config.yaml`).

## Layout

```
cluster/traefik-config.yaml   # HelmChartConfig: ACME resolver, 80->443 redirect, acme.json PVC
base/                         # everything both environments share
  assets/                     # postgres init, keycloak realm+theme, minio/vault bootstrap
  configmap-common.yaml       # platform-common: the environment identical in dev and qa
  data-layer.yaml             # postgres, redis, rabbitmq, minio(+init Job), mailpit
  identity.yaml               # keycloak, vault(+init Job), config-server
  services.yaml               # the 13 Spring services (generated, replicas: 1)
  portal.yaml                 # nginx over /opt/delivery/sites/<env>/portal (hostPath)
overlays/dev, overlays/qa     # namespace, platform-env ConfigMap, ingress with the env's hosts
overlays/ingress.template.yaml  # single source for both ingress files
scripts/render-overlays.sh    # regenerates both ingress.yaml files from the template
scripts/gen-secrets.sh        # creates a new namespace's Secrets (run on the box)
scripts/rotate-secrets.sh     # replaces credentials in a running namespace, and proves it (on the box)
```

## Deploying (on the box)

```bash
rsync -a deploy/k3s/ root@<box>:/opt/delivery/k3s/
kubectl apply -f /opt/delivery/k3s/cluster/traefik-config.yaml
sh /opt/delivery/k3s/scripts/gen-secrets.sh delivery-dev
kubectl apply -k /opt/delivery/k3s/overlays/dev
# and the same pair with delivery-qa / overlays/qa
```

`gen-secrets.sh` mints fresh credentials per environment and refuses to overwrite existing ones —
regenerating passwords under stateful volumes would strand the data. See *Secrets, and rotating
them* below for what it creates and who reads each one.

## What to know

- **Vault is dev-mode and in-memory, but reboot-safe**: the `vault-reseed` sidecar in the vault pod
  re-seeds AppRole + policies + KV from `platform-secrets` on every pod start (and re-heals a vault
  container restart), and its readiness probe gates the vault Service until the seed reaches its
  completion marker. Nothing to do on reboot. All Vault state derives from `platform-secrets` (the
  datastore) — add new secret material there, never by hand in Vault (the reseed would overwrite it).
- **Mail goes to mailpit** (monitoring-<env>/mailpit, behind the ops basic-auth). Real SMTP means
  putting relay credentials in `platform-secrets` and pointing `SMTP_*` in `platform-common` at
  the relay — a deliberate act, since test data then reaches real inboxes.
- **Every photo the platform reads runs on sample data** until two deliberate acts, both per
  environment. One switch covers all three: Merchant Blitz's shelf scans, a merchant finding a
  product in their own catalogue by photo, and a customer searching the shops by photo. (1) Give product-service the Claude API key in its own Secret, `anthropic-api` —
  never `platform-secrets`: every service imports that one whole, so a key there would sit in every
  pod on the platform. Only product-service references `anthropic-api` (an optional `secretKeyRef`
  in `base/services.yaml`), and `gen-secrets.sh` deliberately does not create it. Type the key in on
  the box rather than putting it in a manifest, a commit, a chat or your shell history:

  ```sh
  read -rs ANTHROPIC_API_KEY   # paste the key, press Enter; nothing is echoed
  printf %s "$ANTHROPIC_API_KEY" | kubectl -n delivery-dev create secret generic anthropic-api \
    --from-file=ANTHROPIC_API_KEY=/dev/stdin
  unset ANTHROPIC_API_KEY
  kubectl -n delivery-dev rollout restart deployment/product-service
  ```

  To rotate it, delete `anthropic-api` and repeat. (2) Select the provider: add
  `CATALOG_SCAN_VISION_PROVIDER=CLAUDE` to that overlay's `platform-env` literals. Either one alone
  changes nothing a merchant can see: CLAUDE without a key still answers with labelled samples, and
  a key without CLAUDE is never used. Each scan is a paid call once both are done; the per-merchant
  caps live under `delivery.catalog.scan` in product-service's `application.yml`.

  **What each of the three does before and after.** Blitz and a merchant's find by photo answer with
  labelled sample lines until both acts are done, and with real readings after. Customer photo search
  does neither: while the key or the provider is missing, `GET /api/products/search/capabilities`
  answers `photoSearch: false`, the customer app draws no camera, and the endpoint refuses — a
  customer is never shown sample products. Both acts done turns it on for customers too, at 10 photos
  per customer a day and 1,000 a day across the platform (about $40 a day at most); the caps and the
  per-photo cost are under `delivery.catalog.photo-search` in `application.yml`. To keep customers off
  while merchants use the reader, add `CUSTOMER_PHOTO_SEARCH_ENABLED=false` beside the provider.
  Photos sent for reading are never stored: only a row per read, per account, for the daily caps.
- **Service-order attachments need their bucket once per environment.** The files customers attach
  to service orders live in the private `order-attachments` bucket, which `minio/bootstrap.sh`
  creates. A finished Job never runs again, whether Argo CD or `kubectl apply` applies it (the
  generated ConfigMaps keep their names). So the bootstrap Job's name carries a suffix, now
  `minio-init-3`: -2 added this bucket, and -3 moved the image to quay.io. The next sync creates the
  renamed Job, and the script runs once more in each environment. It is idempotent, so existing
  buckets and rules are left as they are. Bump the suffix whenever the script or its image changes.
  To confirm:

  ```sh
  kubectl -n delivery-dev logs job/minio-init-3 | grep order-attachments
  # and the same with delivery-qa
  ```

  The same apply routes `/order-attachments` on the API hostname (presigned requests only; MinIO
  refuses unsigned ones) behind `order-attachment-upload-limit`, which answers 413 to a body over
  10 MiB before MinIO stores a byte — keep it in step with order-manager's
  `delivery.attachments.max-size-bytes` — and hands order-manager its MinIO credentials from
  `platform-secrets`, as onboarding-service gets them; the Vault seed carries them too from the next
  vault pod start. order-manager's image must be built against platform-storage 0.1.3, published to
  GitHub Packages.
- **Applicant documents reach storage the same way.** `/merchant-kyc` is routed on the API hostname
  like `/order-attachments` — prefix kept, presigned requests only, MinIO refusing unsigned ones —
  behind `merchant-kyc-upload-limit`, a 413 over 10 MiB (keep it in step with onboarding-service's
  `delivery.storage.minio.max-upload-size-bytes`). Until it was, every rider's and merchant's id,
  licence and registration upload met Traefik's own 404 and never reached MinIO. The bucket has
  existed since the first bootstrap, so the next sync of each overlay is the whole deployment. To
  confirm, an unsigned request must now get MinIO's XML `AccessDenied`, not `404 page not found`:

  ```sh
  curl -s -X PUT https://api-dev.youdrop.shop/merchant-kyc/probe   # and api-qa
  ```

  The storage routes, then: `product-images` and `apk` (public), `user-avatars`,
  `order-attachments` and `merchant-kyc` (private, presigned). `delivery-proof` and `receipts` stay
  unrouted because no service signs a URL into either yet; `scripts/verify.sh` checks both halves.
- **The demo logins** (customer/rider/merchant/backoffice/carrier) come from the realm import, and
  their passwords from the `demo-logins` Secret — see below.
- **The realm import runs only against a fresh database**, so a change to the realm file reaches an
  environment that already has one only by hand. The user profile now declares
  `onboardingApplicationId`, admin-only to view and to edit: onboarding-service stamps it on every
  account it makes for an applicant's passcode, and finishes an interrupted sign-up only on an
  account stamped for that application. Keycloak silently drops an undeclared attribute, so until
  dev and qa declare it an interrupted sign-up is refused with `account-exists` (safe, but it cannot
  be finished). Declare it with `scripts/rotate-secrets.sh <namespace> user-profile-stamp` (done on
  dev on 2026-09-19; qa gets it with its own rotation), or by hand in the admin console: Realm
  settings → User profile → Create attribute, name `onboardingApplicationId`, display name `Onboarding application`, not required,
  and only admins may view or edit it. (Do not run `infra/keycloak/apply-realm-updates.sh` here: it
  re-asserts the compose stack's dev client secrets.)
- **The identity settings the realm file now carries**, and how a running environment gets them.
  All of it is in the file for a fresh import; a live realm takes it from two idempotent steps,
  run in this order and not together:

  ```sh
  bash scripts/rotate-secrets.sh delivery-dev edge-identity      # safe for every installed build
  bash scripts/rotate-secrets.sh delivery-dev refresh-rotation   # LAST, and only once (see below)
  ```

  | | before | after |
  | --- | --- | --- |
  | `delivery-portal` password grant | on | off — the portal uses Authorization Code + PKCE, and a public client with direct access grants turns a phished password into a session |
  | `delivery-portal` `offline_access` | granted (realm default) | removed — it is what let the back office hold a token that never expires |
  | `delivery-portal` client session | the realm's 30 d idle / 90 d max | 8 h idle, 24 h max, which is also its refresh token's ceiling |
  | `delivery-portal` loopback redirect URIs | on both environments | dev only |
  | realm `sslRequired` | `none` | `external` |
  | realm refresh tokens | 30 days, reusable | rotated on every use, no reuse |
  | `mobile-app` web origins | `+` | `+` and `https://www.youdrop.shop`, which the site's receipt panel needs |
  | `mobile-app` client session | the realm's 30 d idle / 90 d max | **14 d idle, 30 d max** |

  **`refresh-rotation` is the one that can sign somebody out**, which is why it is separate and
  goes last. Under it a client that runs two refresh grants at once presents a token the server
  has already replaced, and Keycloak ends the session rather than refusing the one request. The
  client-side fix is in `delivery_core`'s `AuthService` (one grant at a time; see
  `auth_refresh_rotation_test.dart`), so run this only once the portal build being served and the
  APK people have installed both contain it. Realm-wide SSO stays 30 d / 90 d because it is the
  phones' session too — which is also why a portal user reaching the 8 h idle limit gets a silent
  PKCE round trip rather than a password prompt.

  **What rotation does and does not stop.** Measured on dev after the step ran, with
  `revokeRefreshToken` true, `refreshTokenMaxReuse` 0 and no client override:

  | | |
  | --- | --- |
  | Replay the token that was **just** spent | refused (`invalid_grant`), **and the session is revoked** — the live token dies with it |
  | Replay a token from **two rotations earlier** | **accepted.** It mints a new token, and the token the client is holding keeps working |

  So Keycloak guards the CURRENT token, not the chain. A refresh token copied out of a browser or
  a backup is still usable for as long as its session lives, unless the thief is unlucky enough to
  race the real client's very next refresh. **The client session window is the real bound**, and
  both clients now have one: `delivery-portal` 8 h idle / 24 h max, `mobile-app` 14 d idle /
  30 d max. Note which number does the work — idle only expires a token nobody is using, and a
  thief spending a stolen one keeps resetting that clock, so the MAXIMUM is what bounds an
  actively abused token. `mobile-app` inherited the realm's 90 days; it is now 30.

  **What that means for a rider or a customer.** They sign in again after 14 days without opening
  the app, and after 30 days however often they use it. Biometric "Continue as" is not an
  exception: the stash behind it IS a refresh token (`AuthService.signOut(keepForBiometrics:
  true)`), so it dies with the session it belongs to, and the next sign-in asks for a passcode
  before the fingerprint is offered again. A rider can meet the 30-day bound mid-shift; nothing in
  the app defers it. Raising either number is one client attribute, applied by re-running
  `edge-identity` after changing it here and in the realm file.

  When the window is first narrowed, every session already older than the new maximum ends at
  once. That was accepted deliberately in 2026-09, while the platform had no real user base — the
  cost of this change grows every week it is deferred.

  `refresh-rotation` proves both halves of the first row, and it needs **two sign-ins** to do it:
  the replay is what revokes the session, so a proof that replays first and then checks the
  rotated token is measuring its own side effect. It did exactly that on the first run and failed;
  `scripts/verify.sh` now pins the shape so it cannot come back.
- **The Keycloak admin console is not public.** The edge refuses `/admin` on `iam-dev` and
  `iam-qa` (`overlays/ingress.template.yaml`, the `deny-public` middleware), which covers the
  console and the admin REST API; `/realms` is untouched, so authorize, token, JWKS, logout and
  the account console all still answer. `rotate-secrets.sh` reaches the admin API by
  port-forwarding to `svc/keycloak`, so it keeps working; every other script in the repository
  already used the in-cluster address. To use the console yourself:

  ```sh
  kubectl -n delivery-dev port-forward svc/keycloak 8080:8080   # then http://127.0.0.1:8080/admin
  ```
- **order-manager's image** is the one Docker Hub pull (its own repo/pipeline); everything else
  pulls public GHCR packages.
- **The portal** serves whatever is under `/opt/delivery/sites/<env>/portal` on the node — sync a
  Flutter Web build there. `infra/deploy-portal.sh` has the shape of that build; the part that is
  not optional is:

  ```sh
  cd clients/apps/delivery_portal
  flutter build web --release --no-web-resources-cdn \
    --dart-define=KEYCLOAK_ISSUER="https://iam-<env>.youdrop.shop/realms/delivery-platform" \
    --dart-define=API_BASE_URL="https://api-<env>.youdrop.shop" \
    --dart-define=OIDC_REDIRECT_URL="https://portal-<env>.youdrop.shop/"
  ```

  `--no-web-resources-cdn` keeps CanvasKit on our own origin (`web/flutter_bootstrap.js` already
  points the loader at the local copy; this stops the build offering the gstatic one at all), and
  Rubik is bundled as an asset. Both matter now: the portal's CSP is `script-src 'self'
  'wasm-unsafe-eval'`, and a renderer fetched from an origin the policy does not allow leaves a
  blank page, not a degraded one. A build that overrides `MAP_TILE_URL` must also change the tile
  host in `overlays/ingress.template.yaml`; `scripts/verify.sh` fails if the two disagree.
- **The public website** (youdrop.shop apex) is not deployed here yet: its static build was never
  in the repository. Routes for it can join the template when the content exists.
- **probes are TCP**, matching what the compose stack verified; actuator-based HTTP probes are a
  cheap later upgrade if /actuator/health is permitted unauthenticated.

## Secrets, and rotating them

Until 2026-09 the public repository carried working credentials for dev and qa: the realm file's
service-account client secrets and demo passwords, the WhatsApp webhook secret and verify token
in `platform-common`, and the ops basic-auth hash in `gen-secrets.sh`. None of that is in git now;
`scripts/verify.sh` fails if it comes back. Each value lives in one Secret, on the box only:

| Secret | keys | read by |
| --- | --- | --- |
| `platform-secrets` | infrastructure passwords (Postgres, Redis, RabbitMQ, MinIO, Keycloak admin, Config Server, Vault), `SMTP_PASSWORD` | every Spring service (whole, via envFrom), the data layer, Vault, Keycloak |
| `keycloak-clients` | `ONBOARDING_CLIENT_SECRET`, `ACCOUNTING_CLIENT_SECRET`, `NOTIFICATIONS_CLIENT_SECRET` | Keycloak's first-boot import; each of those three services, its own key |
| `demo-logins` | `customer`, `rider`, `merchant`, `backoffice`, `carrier` | Keycloak's first-boot import; `scripts/e2e-smoke.sh` |
| `whatsapp-webhook` | `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN` | whatsapp-service |
| `sms-dlr` | `SMS_DEV_DLR_SECRET` | sms-connector |
| `ops-auth-users` | `users` (an apr1 hash) | Traefik, for monitoring-<env> |
| `anthropic-api` | `ANTHROPIC_API_KEY` (optional, by hand) | product-service |

- **The realm file holds `${NAME}` placeholders**, which Keycloak fills from its own environment
  while it imports a realm at startup — and only then, only for a realm that does not exist yet.
  A placeholder it cannot resolve is imported as its own text, which is why every one is a
  non-optional `secretKeyRef` on the keycloak container. (The Google identity provider's
  `$(env:GOOGLE_CLIENT_ID)` is keycloak-config-cli syntax, not Keycloak's: the import keeps it
  literally, harmless while that provider is disabled.)
- **The demo logins' passwords**: six-digit passcodes for the four that sign in on the phone (the
  app accepts nothing else), a long password for backoffice, which signs in only through the
  portal's Keycloak page. Read one on the box, onto your own terminal:

  ```sh
  kubectl -n delivery-dev get secret demo-logins -o jsonpath='{.data.customer}' | base64 -d; echo
  ```

  `e2e-smoke.sh` reads the Secret itself (run it on the box). The Flutter live tests take
  `--dart-define=DEMO_<USER>_PASSWORD=...` (or `--dart-define-from-file`), never a value in git.
- **The ops password** is written by `gen-secrets.sh` (and `rotate-secrets.sh ops-auth`) to
  `/root/ops-auth-password-<env>.txt`, mode 600, user `ops`. Only its hash is in the Secret.
- **Never `kubectl apply` a Secret.** Apply copies every value into a
  `last-applied-configuration` annotation, which `kubectl describe` prints. Create, replace, patch.
- **Rotating** a value in a running environment is `scripts/rotate-secrets.sh <ns> <step>`, one
  step at a time: each checks its preconditions, changes one thing, restarts what reads it, and
  proves the new value works and the old one is refused. `gen-secrets.sh` never rotates anything.
- **Still in the repository, deliberately:** the per-service database roles' passwords, derived
  from the role name in `postgres-init/02-service-roles.sql` and repeated in `vault/bootstrap.sh`
  and two services' `application.yml`. Postgres answers only inside the cluster, and every Spring
  pod already holds the superuser password through `platform-secrets`, so they add little; replacing
  them means changing the roles, the Vault seed and two Deployments together — the production
  secrets refactor. The roles nothing logs in as cannot log in at all.

## The connection budget

Postgres allows 200 connections, three of them reserved for superusers, so **197 are usable per
environment** (dev and qa each run their own instance). Eleven services hold independently-sized
Hikari pools with nothing between them and the database:

| | max | idle floor |
| --- | --- | --- |
| order-tracking | 15 | 3 |
| onboarding-service | 12 | 3 |
| accounting, app-notification, notifications-manager, order-manager, product, whatsapp | 10 each | 2 each |
| transfer-service | 5 | 1 |
| connector-settings | 4 | 1 |
| config-server | 2 | 1 |
| **total** | **98** | **21** |

**Every pool names `minimum-idle`, and that is not decoration.** Hikari defaults the idle floor to
the MAXIMUM, so a pool that does not name one never shrinks and its ceiling becomes its permanent
footprint. Three services were in that state and held 10, 5 and 2 connections around the clock
between them for work measured in milliseconds.

The ceiling is what decides whether this platform can run **two replicas of everything**: 98 x 2 =
196 against 197 usable, which fits and leaves nothing. A third replica, or a new service, needs
either a raised `max_connections` (each backend costs roughly 10 MB of the box's memory) or a
connection pooler in front. There is no pooler today. Failure is not graceful — a service that
cannot get a connection blocks for Hikari's 30-second timeout, and the losers are whichever
services start last rather than whichever matter least.

## Monitoring

`scripts/setup-monitoring.sh` installs `cluster/monitoring.yaml` — one Prometheus and one Grafana
in the `monitoring` namespace, watching both environments. **Run it again after `gen-secrets.sh`
creates or rotates an environment's `platform-secrets`**: it copies that environment's Config
Server basic-auth login into the `config-server-scrape` Secret, and the scrape job cannot
authenticate without a current copy.

Grafana's datasources are provisioned from that file and provisioning is the only place they may
be added. A datasource created by hand in the UI is invisible to every review and survives every
redeploy; the only way to remove one is to name it under `deleteDatasources`, which the file now
does for the `jaeger` datasource somebody added against a tracing backend this platform does not
run.

Alert rules live in the `prometheus-rules` ConfigMap. **There is no Alertmanager**, so nothing
pages: a firing alert shows in the Prometheus UI and as the `ALERTS` series in Grafana. Two rules
today — a dead-letter queue with anything in it, and any scrape target down for 15 minutes.

## Draining a dead-letter queue

A notification that exhausts its retries is *parked*, not dropped: `DeadLetterPublisher` publishes
the whole command plus the reason it failed onto `notification.dlq` through the default exchange.
That queue is bound to nothing and has no consumer **on purpose** — it is a parking lot, and the
bodies in it are the only record of what was never sent. `NotificationDeadLettersParked` fires
while it is non-empty.

Read it without consuming it (`reject_requeue_true` puts every message back):

```bash
NS=delivery-dev
U=$(kubectl -n $NS get secret platform-secrets -o jsonpath='{.data.RABBITMQ_USER}' | base64 -d)
P=$(kubectl -n $NS get secret platform-secrets -o jsonpath='{.data.RABBITMQ_PASSWORD}' | base64 -d)
# Through env, not argv: the broker password would otherwise stand in the pod's process list.
kubectl -n $NS exec rabbitmq-0 -- env RU="$U" RP="$P" sh -c \
  'rabbitmqadmin -u "$RU" -p "$RP" -f raw_json \
     get queue=notification.dlq count=100 ackmode=reject_requeue_true'
```

`count` is a ceiling, not a page: each result carries `message_count`, the number still behind the
last one returned, so raise it until that reaches zero.

Each message is `{"command": …, "reason": …}`. The same reason is on an `x-dead-letter-reason`
header, alongside `x-dead-lettered-at` and `channel`; `message_id` is the idempotency key and
`correlation_id` is the correlation id of the request that caused it, so a body can be traced back
to a log line. All of that is kept out of the body precisely so the command can be replayed
unchanged.

The reason says which of three things happened, and they want different responses:

- a preparer's rejection (`recipient is not a valid E.164 number: …`, `empty email body`,
  `payload exceeds the FCM 4KB limit`) — the command is malformed and replaying it changes nothing;
- `connector unreachable: …` or a provider error — retries were exhausted against something that
  was down, and a replay after it is back is the whole point of keeping the body;
- `worker error: …` — a bug in the worker itself, so the message is evidence for a fix rather than
  something to resend.

To retry one once the cause is fixed, publish its `command` object back onto the dispatch queue
for its channel (`notification.dispatch.email` / `.sms` / `.push` / `.in_app`); the idempotency
key travels with it, so a message that did in fact go out will not go out twice.

**Do not purge until the messages have been read and their reasons recorded.** A purge is the one
irreversible operation here, and it destroys the evidence of an outage rather than the outage.


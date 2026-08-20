# Delivery Platform

A role-based delivery marketplace — Customer, Delivery Rider, Merchant, Backoffice — built as
Spring Boot microservices behind Flutter clients, with Keycloak for IAM, PostgreSQL for storage,
MinIO for files, and a Spring Cloud Config Server composited with Vault for configuration and
secrets.

The complete technical plan is [`docs/PROJECT_BRIEF.md`](docs/PROJECT_BRIEF.md). Section references
throughout this repo point at it.

| Also in `docs/` | |
| --- | --- |
| [`SECURITY_REVIEW.md`](docs/SECURITY_REVIEW.md) | Phase 5 review — findings, fixes, and what was accepted |
| [`LOAD_TEST.md`](docs/LOAD_TEST.md) | Measured capacity of the two paths Section 10 singles out |
| [`UAT_SCRIPT.md`](docs/UAT_SCRIPT.md) | The browser walkthrough nobody has run yet — the last thing owed before go-live |
| [`SMS_CUTOVER_RUNBOOK.md`](docs/SMS_CUTOVER_RUNBOOK.md) | Phase 6 — the staged vendor cutover, its gates, and its rollback |

**Current state: all six phases built. Two things are open, and neither is an engineering task —
UAT in a real browser, and the choice of SMS vendor.**

Platform foundation, catalog, the full order lifecycle with live tracking, and the whole
notification and integration layer — nine services from Notifications Manager through the three
channel workers to the three provider connectors, plus Connector Settings and its Backoffice
screen. Phase 4 adds the accounting settlement saga, the Core Banking connector
and simulator, and financial reconciliation. Phase 5 is the hardening pass: a security review with
fixes, load testing, correlation-ID tracing proven end to end, tracking-table partitioning, and
Kubernetes manifests. Phase 6 adds per-provider delivery-rate monitoring and a canary ramp, so an
SMS vendor can be cut over a slice at a time instead of all at once.

---

## What works today

Verified running on this machine, from a cold `docker compose up -d` with empty volumes:

| | |
| --- | --- |
| Maven monorepo | 23 modules, `mvn clean install` green, 164 unit tests |
| `platform-security` | Keycloak realm roles → Spring authorities, servlet **and** reactive |
| `platform-outbox` | Outbox entity, `FOR UPDATE SKIP LOCKED` relay, DLQ status, Flyway migration |
| `platform-observability` | Correlation-ID filter (both stacks) + OTLP tracing |
| `platform-storage` | Presigned MinIO PUT/GET, `file_metadata`, confirm-and-size-check |
| Config Server | Git + Vault composite, AppRole auth, Spring Cloud Bus refresh |
| API Gateway | JWT validation, Redis rate limiting, routes declared for all later services |
| `platform-notifications` | Command/receipt contracts, resilience wrapper, worker and connector auto-configuration |
| **Product Service** | Catalog CRUD, per-row ownership, image upload, catalog events on the bus |
| **Order Manager** | Order lifecycle state machine, price snapshotting, pessimistic rider claim |
| **Order Tracking** | PostGIS positions, Redis hot-read cache, participants projection off the bus |
| **Notifications Manager** | Templates, rendering, the notification log, audience fan-out |
| **Mail / Push / SMS workers** | One queue and one deployable per channel; segmentation, MIME, payload shaping |
| **Email / Push / SMS connectors** | The only processes holding provider credentials; breaker, retry, idempotency, DLQ |
| **App Notification** | `in_app_messages`, STOMP over WebSocket, REST polling fallback |
| **Connector Settings** | Business-user-managed provider choice with an audit log |
| **Accounting Service** | Settlement saga, commission split, compensation, `accounting` schema |
| **Core Banking Connector** | The only process holding bank credentials; simulator/real toggle at runtime |
| **Core Banking Simulator** | Dev-only fake bank with a real ledger, real idempotency and fault injection |
| Postgres 17 + PostGIS | 9 schemas, one owner role each, `delivery_readonly` |
| Keycloak 26 | `delivery-platform` realm, 4 roles, 6 clients, 4 dev users, declared user-profile attributes |
| MinIO | 5 buckets with per-bucket policies, versioning on `delivery-proof` |
| Mailpit | SMTP relay and the SMS dev test inbox, readable at http://127.0.0.1:8025 |
| Vault | AppRole + read-only policy, 14 secret paths, a dedicated policy for the bank's path |
| RabbitMQ | Domain-event bus, doubles as Spring Cloud Bus transport |
| Jaeger | Traces arriving from the Gateway and every domain service |
| CI/CD | Reusable per-service workflow + callers + Flutter matrix |
| Hardening | `azp` token allow-list, daily-partitioned `tracking_events` with rollup + retention |
| Cutover | Per-provider delivery rates, canary ramp deterministic on the idempotency key |
| Deployment | Kubernetes manifests (`deploy/k8s/`) — **written, never applied**; no cluster exists |

Six smoke tests assert all of the above through the Gateway with real Keycloak tokens —
**39 + 51 + 70 + 74 + 29 + 27 = 290 checks, all passing.** Phase 1 covers cross-merchant isolation. Phase 2 the
order state machine and live tracking. Phase 3 the notification layer end to end: a provider switch
reaching a running connector over the bus, one order event fanning out to the right audiences on
the right channels, a real email and a real SMS arriving in Mailpit, every log row closed out by a
worker receipt, and a bad recipient dead-lettered rather than sent.

Phase 4 is about money not going missing. A delivered order settles exactly and the legs sum to the
total; a refused customer debit pays **nobody**; a refused merchant credit after a successful debit
**refunds the customer**; a redelivered `order.delivered` does not settle twice; and a bank outage
delays a settlement without losing it.

Phase 5 asserts properties rather than features: a token from a client this platform does not serve
is refused everywhere, one correlation id can be followed across all three schemas an order touches,
the tracking table is partitioned and bounded, and no actuator endpoint that would render a
Vault-sourced secret is reachable.

Phase 6 is the vendor cutover mechanism. The property worth naming is that the canary split is
**deterministic on the idempotency key** — route a message randomly and its retry can land on a
vendor that has never seen that key, accept it as new, and send the customer a second billed text.

```bash
cd infra && for t in smoke-test.sh smoke-test-phase2.sh smoke-test-phase3.sh smoke-test-phase4.sh smoke-test-phase5.sh smoke-test-phase6.sh; do docker run --rm --network delivery -v "$PWD/$t:/smoke.sh:ro" alpine:latest sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"; done
```

### Clients

Flutter 3.44.9 is installed at `C:\src\flutter`. All three apps analyze clean, pass their tests, and
build:

| App | Port | Surface |
| --- | --- | --- |
| Merchant Portal | 5010 | Products, image upload, publish/archive, the live order queue |
| Backoffice | 5011 | Order dashboard, category taxonomy, catalog, **Finance/reconciliation**, Connector Settings |
| Mobile app | 5012 (Chrome) or emulator | Browse, basket, checkout, live rider tracking, **in-app notifications**; rider job board |

```bash
cd clients/apps/merchant_portal && flutter run -d chrome --web-port 5010
```

Ports are fixed on purpose — Keycloak redirect URIs are an allow-list and `flutter run` otherwise
picks a random port. Full guide, including the Android emulator, in
[`clients/README.md`](clients/README.md).

**What is not verified: the browser click-through.** This environment blocks localhost from the
agent's own tooling, so the login redirect and on-screen interactions have not been driven
end-to-end by me — that last mile needs a human at a browser. Everything underneath it is verified:
the backends via the six smoke tests (290 checks), the screens via widget tests that drive the
real API clients against a stubbed transport, the PKCE implementation against the RFC 7636 test
vector, and the Keycloak redirect-URI allow-list by direct probe.

---

## Quick start

```bash
cd infra && cp .env.example .env
```

```bash
mvn install -DskipTests
```

```bash
cd infra && docker compose up -d --build
```

First run pulls PostGIS and Vault and takes a few minutes. Then:

| Service | URL | Credentials |
| --- | --- | --- |
| API Gateway | http://localhost:8100 | Bearer token |
| Keycloak | http://localhost:8180 | `admin` / `admin` |
| Config Server | http://localhost:8888 | `config` / `local-config-secret` |
| RabbitMQ | http://localhost:15673 | `delivery` / `delivery` |
| MinIO console | http://localhost:9011 | `delivery` / `delivery123` |
| Jaeger | http://localhost:16686 | — |
| Vault | http://localhost:8200 | token `delivery-root-token` |
| Postgres | `localhost:5433/delivery` | `delivery` / `delivery` |
| Mailpit | http://localhost:8025 | — (the email + SMS dev test inbox) |

Ports deliberately avoid the `lending` stack on this machine (4200, 5432, 8080–8095, 9000–9001).

### Getting a token by hand

```bash
docker run --rm --network delivery curlimages/curl:latest -s -X POST "http://keycloak:8080/realms/delivery-platform/protocol/openid-connect/token" -d "client_id=merchant-portal" -d "username=merchant" -d "password=merchant" -d "grant_type=password"
```

Unauthenticated calls to `/api/**` return 401.

The dev bank is at http://localhost:8114 (API key `simulator-dev-key` in the `X-Bank-Api-Key`
header). To make it misbehave and watch the saga cope:

```bash
curl -X POST http://localhost:8114/test/faults -H 'Content-Type: application/json' -d '{"mode":"UNAVAILABLE","latencyMs":0,"callCount":3}'
```

### Applying realm changes to a running stack

Keycloak only imports `realm-delivery-platform.json` into a realm that does not exist yet, so
editing it does nothing to a stack that is already up. The documented alternative,
`docker compose down -v`, also wipes the Postgres volume. For an environment with data worth
keeping:

```bash
cd infra && docker compose cp keycloak/apply-realm-updates.sh keycloak:/tmp/realm-updates.sh && docker compose exec -T keycloak sh /tmp/realm-updates.sh
```

The script is idempotent and the realm JSON stays the source of truth — anything added to one
belongs in the other.

---

## Layout

```
delivery/
├── docs/PROJECT_BRIEF.md      # the full plan; every "Section N" reference points here
├── pom.xml                    # Spring Boot 3.4.5 / Spring Cloud 2024.0.1, Java 17
├── platform/                  # shared libraries every service starts with wired in
│   ├── platform-security/
│   ├── platform-outbox/
│   ├── platform-observability/
│   ├── platform-storage/
│   └── platform-notifications/   # command + receipt contracts, worker/connector auto-config
├── services/                  # 15 independently deployable Spring Boot services
│   ├── config-server/  api-gateway/
│   ├── product-service/  order-manager/  order-tracking/
│   ├── notifications-manager/  app-notification/  connector-settings/
│   ├── mail-worker/  push-worker/  sms-worker/
│   ├── email-connector/  push-connector/  sms-connector/
│   └── accounting-service/  corebanking-connector/  corebanking-simulator/
├── config-repo/               # SEPARATE Git repo - Config Server's Git backend
├── infra/                     # docker-compose, Postgres init, Keycloak realm, MinIO, Vault
├── clients/                   # Flutter monorepo - 3 apps, 2 shared packages
└── .github/workflows/         # reusable per-service pipeline + callers
```

## Adding the next service

1. `services/<name>/` with a pom inheriting `com.delivery:services`, depending on the
   `platform-*` libraries it needs.
2. `config-repo/<name>/<name>.yml` (+ `-docker.yml`). Secrets go to Vault, never here.
3. Its Postgres schema owner already exists — see `infra/postgres/init/02-service-roles.sql`.
4. A compose entry on its reserved port (the map is at the top of `infra/docker-compose.yml`).
5. `.github/workflows/<name>.yml` — 12 lines calling `reusable-service-ci.yml`.
6. A Gateway route, if it has a public API. Several are already declared and waiting.

## Known deviations from the brief

- **`orders` schema, not `order`.** `ORDER` is a reserved SQL word and would force quoting in every
  query, migration and mapping. Cosmetic — no table or relationship differs.
- **`file_metadata` lives in each owning service's schema, not a shared `files` schema.** Section 4
  puts it in one place, but several independently deployed services writing one table is the
  shared-database coupling that schema-per-service exists to prevent — and the per-schema database
  roles block it outright. Same pattern as `outbox_event`. A future File Service can own a
  consolidated table; Section 5 leaves that open.
- **`CUSTOMER` realm role exists.** Section 3 recommends it; Section 12 lists it as open decision
  #1. Easy to remove — see `infra/keycloak/README.md`.
- **Products are archived, never deleted.** Past orders reference them, and Phase 4 reconciliation
  needs to name what was bought.
- **Jaeger all-in-one** stands in for the observability backend. Section 10 specifies OpenTelemetry
  and correlation IDs, not a particular backend.
- **The push connector ships a `DEV_LOG` provider alongside Firebase.** Section 7's matrix assumes
  a real dev Firebase project; there isn't one. A connector whose only provider refuses every
  message would leave the whole push path — worker, resilience, receipts, token handling —
  untested until the day it goes live. `FirebasePushClient` is built and deployed either way, so
  switching is the same Backoffice dropdown the SMS connector uses.
- **In-app notifications go over the bus like every other channel.** Section 7 describes IN_APP as
  never leaving the platform, which is true of the provider hop but not of the service boundary:
  App Notification owns `in_app_messages` and is a separate deployable, so the alternative is
  Notifications Manager writing into another service's tables.
- **The IN_APP channel has no separate worker and connector.** The other three split them to keep
  credentials away from content rendering; in-app has no external provider and no credential, so
  the split would add a process whose only job is to forward a message.
- **Both notification services share the `notification` schema**, per Section 4's data model, with
  disjoint tables and separate Flyway history tables. That forces `baseline-on-migrate` on both —
  whichever starts second finds a non-empty schema with no history of its own. The trade-off is
  spelled out in `V20__in_app_messages.sql`.
- **The connectors are not routed by the Gateway.** Their `/api/connector/send` endpoint accepts
  "send this message" with no user token and exists only on the internal network. In dev the
  compose network is the trust boundary; staging and production need mTLS between services.
- **The settlement saga lives in its own service, not in Order Manager.** Section 7 reads as though
  Order Manager owns it. It cannot: the `accounting` schema has had its own database role since
  Phase 0 and Order Manager physically cannot write to it, and a saga whose lifetime is a bank's
  availability window does not belong on the order-placement hot path. What the brief actually
  asks for holds — Order Manager publishes `order.delivered` and knows nothing about accounting,
  and the bank is never called synchronously from the order path.
- **Settlement happens at delivery, not at checkout.** There is no payment provider in this
  architecture — the bank is the ledger — so there is no authorisation to capture against. Money
  moves when the goods arrive, and an order cancelled before delivery has nothing to unwind.
- **The three settlement legs are posted one at a time**, debit → merchant → commission, rather
  than fanning the credits out together. Firing them together allows a state where the platform
  has kept its commission on an order it then refunds; sequencing removes that state instead of
  adding a reversal to clean it up. The residual case — commission failing after the merchant is
  paid — leaves the platform short its own revenue, not customer money in the wrong place.
- **`RealBankClient` refuses every posting**, loudly, naming what is missing. The simulator's
  contract is a placeholder this project invented and Section 12's open decision #5 leaves nobody
  owning the job of matching it to the bank's real spec. A speculative implementation would look
  finished, pass every test written against the simulator, and fail on the first real posting.
- **The Core Banking Simulator has its own `corebanking` schema and its own API key**, and no grant
  on any platform schema. It stands in for a system outside the platform, so it should be as unable
  to read the accounting tables as the real bank is — and it authenticates callers the way a bank
  does rather than with a Keycloak token, so the connector's auth path is exercised in dev.
- **Connector retries are invisible in `transactions.attempts`.** The connector absorbs its retries
  inside one dispatch and reports a single outcome, so the saga only ever records the final answer.
  The breaker and the DLQ cover the pathological case; per-attempt visibility would need the
  connector to report each try.
- **Token validation is on `azp`, not `aud`.** Keycloak leaves `aud` empty on these public clients
  unless an audience mapper is configured per client, and a check that silently passes when someone
  forgets one is worse than no check. See finding 1 of the security review.
- **The Core Banking Vault policy is unbound.** Section 10 asks for the bank's secret path to have
  its own policy *and* for all secrets to route through the Config Server. Those pull against each
  other — the Config Server must be able to read what it serves. The policy exists and is ready to
  bind; closing it properly is a decision for whoever owns Vault. Finding 4 of the review.
- **`docker compose` publishes every service port to the host.** A dev affordance that makes the
  "internal only" endpoints reachable from the host machine. It is the single most important thing
  not to carry into a cluster, and the Kubernetes manifests are `ClusterIP` everywhere but the
  Gateway for exactly that reason. Finding 3 of the review.
- **Delivery is now measured, but only where a vendor actually reports it.** Carrier delivery
  receipts are ingested (`POST /webhooks/dlr/{provider}`, the one public path in the platform,
  authenticated by the vendor's own signature), and the rate report separates `successRate`
  (accepted) from `deliveryRate` (confirmed arrival). The remaining honest limit is narrower than
  the old one: **`deliveryRate` is null, and reads "not measured", until receipts exist for that
  provider** — most SMS traffic produces none, and `awaitingReceipt` is reported beside the rate
  rather than folded into it, so 12 delivered out of 1000 accepted shows as 988 awaiting rather than
  as a 1.2% delivery rate. Neither vendor's callback has been exercised against a live account.
- **Connector retry attempts are not visible per provider.** During a canary ramp the rate table
  shows outcomes, not how hard each vendor had to be retried to get them.

## Open decisions blocking later phases

Section 12 lists eight. The two that gate work rather than opinion:

- **#2 — who owns the Phase 0 platform work.** The `deploy-staging` job in the CI template is a
  deliberate no-op: there is no Kubernetes target and no credentials.
- **#3 — who reviews `config-repo` PRs.** The Config Server is live and serving; nobody is named as
  the approver for a production business-parameter change.

Phase 3 has made three more of them concrete rather than theoretical:

- **#6 — MontyMobile or Twilio. This is now the only thing blocking Phase 6.** Both clients are
  built and deployed, the canary ramp and the delivery-rate monitoring that gate a cutover are
  live, and the runbook is written. The platform is not waiting on code — it is waiting on
  commercial terms and local carrier support, which cannot be established from this repository.
  See [`docs/SMS_CUTOVER_RUNBOOK.md`](docs/SMS_CUTOVER_RUNBOOK.md), which argues for piloting both
  at 5% rather than choosing on a rate card.
- **#7 — who inside `BACKOFFICE` may change connector settings.** The whole role can today. The
  Settings page can redirect real SMS traffic and, from Phase 4, real money; narrowing it to a
  `BACKOFFICE_ADMIN` sub-role is a one-line change on `ConnectorSettingsController`.
- **Firebase and SMTP projects.** Both connectors are wired and their credential slots exist in
  Vault, empty. Email works against Mailpit locally; push runs on `DEV_LOG`.

Phase 4 adds one more, and it now blocks work rather than opinion:

- **#5 — who owns the Core Banking Simulator's contract.** Still unassigned, and it is the only
  thing standing between the platform and a working real-bank integration. Everything around it is
  built and proven against the simulator: the provider abstraction, the runtime switch, the
  breaker, the idempotency key, the sync log, the compensation. `RealBankClient` is a deliberate
  refusal until someone owns matching it to the bank's published spec.

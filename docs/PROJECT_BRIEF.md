# Delivery App — Project Brief & Development Plan

**Source:** Derived from the provided "Delivery App Architecture" diagram.
**Target stack:** PostgreSQL · Spring Boot (backend) · Flutter (frontend) · Keycloak (IAM) · MinIO (object storage)
**Date:** August 2026

---

## 0. Project brief — start here

**What this is:** a role-based delivery marketplace — Customer, Delivery Rider, Merchant, and Backoffice admin — built as Spring Boot microservices behind a Flutter frontend (one mobile app, two web portals), with Keycloak for IAM, PostgreSQL for storage, MinIO for files, and a Spring Cloud Config Server + Vault for configuration and secrets. The full technical plan is Sections 1–12 below; this section is just the map to it.

**Status as of this document:** Architecture reviewed and iterated through several passes: locked in as microservices-from-day-one (no monolith-first step), with a pluggable SMS provider abstraction (MontyMobile / Twilio / dev test-inbox), a dev-only Core Banking Simulator, and a centralized Spring Cloud Config Server composited with Vault. See Sections 6–8 for what came out of that review.

**UI/UX:** a red-and-white brand system is established. Phase 1 (Login & Catalog) screens are approved. Phase 2 (Ordering & Tracking) screens are designed and delivered, pending sign-off. Phases 3 through 6 have no screens yet.

**Section 12** lists the open decisions — mostly ownership and commercial calls (which SMS vendor, who administers Vault, who reviews config-repo PRs), not technical blockers. Worth resolving during Phase 0 rather than before it, since none of them change the architecture.

**Companion files** — not embeddable in Markdown, attach these alongside this document when importing into Claude Desktop or a repo:

- `delivery_app_architecture.png` — the full microservices architecture diagram referenced throughout this document (Section 2 and others point back to it).
- `design-review.html` — interactive screen mockups, red/white brand, tabbed by phase (Phase 1 approved, Phase 2 pending review). Self-contained, opens directly in a browser.

**How to use this document:** it's the complete technical plan in one file — architecture, IAM, data model, object storage, configuration, service breakdown, client architecture, non-functional requirements, and a phase-by-phase build roadmap with rough effort estimates. Section 11 is the build order; start at Phase 0 if picking this up fresh — it's platform scaffolding (repo structure, Keycloak, Config Server + Vault, CI/CD template) that every later phase depends on, not a business feature. Appendix A at the end has the red/white design-token reference for implementing the actual Flutter theme.

---

## 1. How the diagram maps to this stack

The diagram already describes a workable microservice/event-driven architecture: three client surfaces (Mobile App, Backoffice Web App, Merchant Web Portal), three core Spring Boot domain services (Order Manager, Order Tracking, Product Manager), and a Notification & Integration layer (Notifications Manager, three channel workers, an ESB/connector tier, and external providers including a Core Banking system). This plan keeps that shape and layers in the specific technologies requested.

**PostgreSQL** becomes the single relational store, provisioned as one instance with a dedicated schema per service (`order`, `tracking`, `product`, `notification`, identity-extension, `accounting`, `settings`) so services stay logically isolated but operationally simple to run and back up.

**Spring Boot** implements every backend box in the diagram as its own independently deployable microservice from day one — Order Manager, Order Tracking, Product Manager, Notifications Manager, the three channel workers, the App Notification Service, and each of the four ESB connectors ship separately, with their own CI/CD pipeline, container image, and (where it makes sense) their own Postgres schema. This is a deliberate choice: rather than starting consolidated and splitting later, the plan builds the diagram's natural service boundaries in from the start so no later "extract this from the monolith" migration is ever needed.

**Flutter** implements all three client surfaces: the role-based Mobile App (Customer + Delivery Rider) as a native/mobile build, and the Backoffice Web App and Merchant Web Portal as Flutter Web builds sharing a common design-system package.

**Keycloak** replaces any bespoke auth and issues the tokens every client and service trusts, carrying the `DELIVERY`, `MERCHANT`, and `BACKOFFICE` roles requested (see the role note in Section 3).

**MinIO** stores every binary the diagram implies but doesn't draw explicitly — product images, proof-of-delivery photos, merchant KYC documents, and generated receipts/invoices from the accounting flow.

A few pieces aren't drawn in the original diagram but are added here because the target stack needs them to work safely at this service count: **Redis** as a cache for the highest-churn read path (rider live location); a **transactional outbox** on every domain service so events can never be silently lost; and a **Spring Cloud Config Server**, backed by Git and composited with Vault, so every service's business parameters, environment variables, and secrets come from one governed source instead of being scattered across per-service config files (Section 6).

A full architecture diagram reflecting this design is provided as a separate image file for review before implementation starts.

### Component-to-service mapping

| Diagram element | Implementation |
| --- | --- |
| Mobile App (Customer & Rider) | Flutter mobile app, role-based UI after Keycloak login |
| Backoffice Web App | Flutter Web app, `BACKOFFICE` role only |
| Merchant Web Portal | Flutter Web app, `MERCHANT` role only |
| Order Manager | Spring Boot service — order lifecycle, orchestrates Order Tracking + Product Manager, publishes notification/accounting events |
| Order Tracking | Spring Boot service — status/location tracking, PostGIS-backed |
| Product Manager | Spring Boot service — catalog, pricing, product images (MinIO) |
| Notifications Manager | Spring Boot service — routes inbound "notification events" to the right worker |
| Mail / Push / SMS Workers | Spring Boot orchestrator modules (or services) per channel |
| App Notification Service | Spring Boot service — in-app message persistence + delivery (WebSocket/polling) |
| SMS/Email/Push/Core Banking Connectors | Four separate Spring Boot microservices (Spring Integration/Camel adapters) talking to external providers, each with its own circuit breaker, retry, idempotency, and dead-letter queue |
| Core Banking System | External system, reached only via the Core Banking Connector, orchestrated from Order Manager as an async saga for accounting |

---

## 2. High-level architecture

Every box below is an independently deployable Spring Boot microservice (or, for the clients, a separate Flutter build) — see the accompanying `delivery_app_architecture.png` diagram for the full picture, including the resilience, data-layer, and configuration additions from Sections 6, 8, and 10.

Clients (Flutter Mobile App, Backoffice Web App, Merchant Web Portal) authenticate directly against Keycloak using OIDC Authorization Code + PKCE, then call the API Gateway with a bearer token. The Gateway validates the JWT and forwards claims (including realm roles) downstream; each Spring Boot service enforces role/ownership checks locally via Spring Security.

Every domain service (Order Manager, Order Tracking, Product Service) writes its outbound events into a transactional outbox table in its own schema; a relay publishes those onto a shared message bus (Kafka or RabbitMQ) as "notification events" and "domain events," which the Notifications Manager consumes — this is what guarantees an order can never be saved without its event eventually reaching the notification layer, even across service restarts.

The Notifications Manager routes to three independent worker services (Mail, Push, SMS), each of which orchestrates its own ESB connector microservice; every connector wraps its call to the external provider in a circuit breaker with retry-with-backoff, an idempotency key, and a dead-letter queue for messages that exhaust retries.

The Core Banking Connector is reached directly from Order Manager as an asynchronous saga (never a blocking call in the order-completion path), so a slow or unavailable bank never holds up order fulfillment.

Underpinning all of it, every microservice boots by pulling its configuration — business parameters, cluster/environment variables, and secrets — from the Spring Cloud Config Server described in Section 6, rather than shipping its own baked-in config.

---

## 3. Keycloak — IAM design

**Realm:** `delivery-platform`, one realm for the whole platform (simpler to operate than realm-per-tenant unless true multi-tenancy is required later).

**Clients:**

| Client ID | Type | Used by |
| --- | --- | --- |
| `mobile-app` | Public, PKCE | Flutter mobile app (Customer + Rider) |
| `backoffice-web` | Public, PKCE (or confidential if server-rendered) | Flutter Web Backoffice |
| `merchant-portal` | Public, PKCE | Flutter Web Merchant Portal |
| `backend-services` | Bearer-only / resource server | All Spring Boot services validate tokens issued for the above clients |

**Realm roles:** the user specified three — `DELIVERY`, `MERCHANT`, `BACKOFFICE`. The diagram's fourth actor, Customer, also needs to be distinguishable from a Delivery Rider inside the same "role-based" Mobile App, so this plan recommends adding a fourth realm role, `CUSTOMER`, purely so the single Mobile App codebase can branch its UI by role. If Customer access is meant to stay anonymous/guest instead, that role can be dropped and the app can treat "no delivery/merchant/backoffice role" as the default customer experience — **flag this decision back to the team before Phase 1.**

**Role-to-client mapping:** `mobile-app` issues `CUSTOMER` or `DELIVERY`; `merchant-portal` issues `MERCHANT`; `backoffice-web` issues `BACKOFFICE`. Composite/admin sub-roles (e.g., `BACKOFFICE_ADMIN` vs `BACKOFFICE_SUPPORT`) can be added later without changing the architecture.

**Backend integration:** each Spring Boot service uses `spring-boot-starter-oauth2-resource-server` with a custom `JwtAuthenticationConverter` that reads `realm_access.roles` into Spring Security authorities (e.g., `ROLE_MERCHANT`). Ownership checks (a merchant can only edit their own products; a rider only sees their own assigned orders) are enforced in service code against the `sub` (subject) claim, not by Keycloak alone.

**Flutter integration:** use `flutter_appauth` (or `openid_client`) for the Authorization Code + PKCE flow, `flutter_secure_storage` for token storage, and a Dio interceptor that attaches the access token and triggers silent refresh on 401s.

---

## 4. PostgreSQL — data model

One PostgreSQL instance, schema-per-service, with the `postgis` extension enabled for tracking. Core tables per schema:

- **`identity` schema** (extends Keycloak users with app-specific profile data — Keycloak stays the source of truth for credentials): `riders(user_id, vehicle_type, status, current_location geography)`, `merchants(user_id, business_name, kyc_status, kyc_doc_ref)`, `customers(user_id, default_address, phone)`.
- **`product` schema:** `products(id, merchant_id, name, description, price, category_id, image_refs jsonb)`, `categories(id, name, parent_id)`.
- **`order` schema:** `orders(id, customer_id, merchant_id, rider_id, status, total_amount, created_at)`, `order_items(order_id, product_id, qty, unit_price)`, `order_status_history(order_id, status, changed_at, changed_by)`, `delivery_assignments(order_id, rider_id, pickup_point geography, dropoff_point geography, assigned_at)`.
- **`tracking` schema:** `tracking_events(order_id, rider_id, location geography, recorded_at)` — high write volume; consider partitioning by date once traffic justifies it.
- **`notification` schema:** `notification_templates(id, channel, locale, body_template)`, `notification_log(id, order_id, channel, recipient, status, sent_at)`, `in_app_messages(id, user_id, title, body, read_at)`.
- **`files` schema:** `file_metadata(id, bucket, object_key, owner_id, content_type, purpose, uploaded_at)` — the Postgres-side pointer to every MinIO object, so the app never has to list a bucket to know what exists.
- **`accounting` schema:** `transactions(id, order_id, amount, direction, core_banking_ref, status)`, `core_banking_sync_log(id, transaction_id, request_payload, response_payload, synced_at)`.
- **`settings` schema:** `connector_settings(connector_type, provider, config_json, is_active, updated_by, updated_at)`, `connector_settings_audit(id, connector_type, old_value, new_value, changed_by, changed_at)` — owned by the Connector Settings Service (Section 8); secrets themselves live in Vault, this schema only holds non-secret config and references. This is separate from the Config Server's Git-backed store (Section 6) — see that section for how the two divide responsibility.

---

## 5. MinIO — object storage design

| Bucket | Contents | Access pattern |
| --- | --- | --- |
| `product-images` | Merchant product photos | Public-read via CDN/presigned GET; upload via presigned PUT (`MERCHANT` role) |
| `delivery-proof` | Proof-of-delivery photos/signatures from riders | Private; short-TTL presigned GET for customer/backoffice, upload via presigned PUT (`DELIVERY` role) |
| `merchant-kyc` | Business registration / ID documents | Private, `BACKOFFICE`-only read, `MERCHANT` upload during onboarding |
| `user-avatars` | Profile photos, all roles | Presigned PUT/GET, owner-only write |
| `receipts` | Generated invoices/receipts from the accounting flow | Private; generated by Order/Accounting service, downloadable by the owning customer and `BACKOFFICE` |

No client ever holds MinIO root credentials. A Spring Boot "file service" (or a shared library used by Order/Product/Notification services) issues short-lived presigned PUT/GET URLs after checking the caller's Keycloak role and resource ownership, and writes the corresponding row into `files.file_metadata`. Large uploads (proof-of-delivery photos, KYC docs) go directly from the Flutter client to MinIO via the presigned URL, bypassing the backend for the actual bytes. Image variants (thumbnails for product listings) can be generated asynchronously by a small worker listening to MinIO bucket notifications, deferred to a later phase if not needed at launch.

---

## 6. Spring Cloud Config Server — centralized configuration & Vault integration

Every microservice in this architecture needs two kinds of externalized configuration: **business parameters** (max delivery radius, order timeout minutes, commission percentage, notification retry counts, template defaults) and **cluster/environment variables** (message bus broker URLs, service discovery endpoints, log levels, connection pool sizes, per-environment feature flags). Rather than baking these into each service's own `application.yml` or scattering them across Kubernetes ConfigMaps, they're centralized in a Spring Cloud Config Server, and every one of the ~14 backend microservices (Gateway, Order Manager, Order Tracking, Product, Notifications Manager, the three workers, App Notification, the four connectors, and the Connector Settings Service) is a Config Client that pulls its configuration at bootstrap.

**Backend:** a Git repository (`config-repo`), organized as `{service-name}-{profile}.yml` per service and environment (dev/staging/prod), giving every configuration change a commit history, a PR review, and a rollback path — the same discipline as application code.

**Vault integration:** the Config Server is set up with a composite environment repository — Git for plain business/environment properties, and Vault (via the Spring Cloud Vault backend) for secrets — so a config client's single fetch returns one merged property set with secret values transparently resolved from Vault underneath. This covers not just the connector credentials from Section 7 (MontyMobile/Twilio/SMTP/Firebase/bank API keys) but also database passwords, message-bus credentials, and JWT/token-signing material. The Config Server authenticates to Vault using the AppRole method, with a role scoped to read-only access on exactly the secret paths it needs — it is never given broad Vault access. Client services never talk to Vault directly; they only ever call the Config Server, which keeps Vault credentials confined to one place in the system.

**Access:** the Config Server is internal-only — never exposed through the API Gateway to end users — reached by other services over the internal network with mTLS, since it is effectively a secrets-adjacent service.

**Dynamic refresh:** reuses the message bus already in the architecture via Spring Cloud Bus. A Git push (through a webhook) or an operator action triggers a refresh event published onto the bus; every config-client service picks it up and reloads its `@RefreshScope` beans without a restart or redeploy.

**Division of responsibility vs. the Connector Settings Service (Section 8):** these are deliberately two different systems, not overlapping ones. The Config Server holds **ops-managed** configuration — values an engineer changes through a Git commit and a deploy pipeline, appropriate for infrastructure tuning and business parameters that don't need a business user's hands on them. The Connector Settings Service holds **business-user-managed** configuration — specifically, which SMS provider is active — surfaced through a Backoffice UI with its own Postgres-backed audit log, because that needs to be changeable by a non-engineer without going through Git. Keeping them separate avoids two bad outcomes: non-engineers being handed Git access, and low-level infrastructure values being exposed in a business-facing settings screen.

---

## 7. Spring Boot service breakdown

Every service below is a separate deployable with its own repo (or monorepo module), pipeline, and container image from the start — none of these are planned as "extract later." All of them are Config Clients of the Config Server described in Section 6.

- **API Gateway** (Spring Cloud Gateway): single entry point for all clients, validates JWTs, applies rate limiting, and routes to downstream services.
- **Order Manager Service:** order lifecycle orchestration, calls Product Service for catalog/pricing, calls Order Tracking for status updates, writes order events to its own transactional outbox, triggers the Core Banking Connector for accounting as an async saga.
- **Order Tracking Service:** live rider location and delivery status, backed by PostGIS for geo-queries and Redis for the "current location" hot-read path (avoids hammering Postgres from a live tracking screen); publishes tracking events to the bus.
- **Product Service:** catalog and pricing, coordinates image upload with MinIO, publishes catalog-change events.
- **Notifications Manager:** a thin router service — consumes "notification events" off the bus and dispatches to the right worker service based on notification type/channel preference.
- **Mail Worker, Push Worker, SMS Worker:** three independent orchestrator microservices, one per channel, each calling its corresponding ESB connector.
- **App Notification Service:** in-app message persistence and delivery over WebSocket/STOMP with a polling fallback, its own `in_app_messages` table.
- **SMS / Email / Push / Core Banking Connectors:** four independent microservices, each isolating outbound network access and provider credentials for exactly one external system. Every connector wraps its outbound call in a Resilience4j circuit breaker plus retry-with-backoff, tags each outbound request with an idempotency key so a retried SMS or a retried bank transaction can never be double-sent, and routes exhausted retries to a dead-letter queue rather than silently dropping them. Keeping these as four separate services (not four classes in one module) means a Core Banking outage can't consume the thread pool or memory budget that SMS/Email/Push need to keep working.

### Confirmed per-connector integration choices

- **Email Provider Connector** — talks to an SMTP relay directly (`spring-boot-starter-mail` / `JavaMailSender`), not a third-party HTTP API like SendGrid/SES. SMTP host, port, and from-address come from the Config Server; credentials come from Vault through it.
- **Push Provider Connector** — integrates with Firebase Cloud Messaging (FCM) via the `firebase-admin` SDK, covering both Android and iOS device tokens through Firebase's unified API. Firebase service-account credentials are Vault-backed secrets, resolved through the Config Server, never checked into the repo.
- **SMS Provider Connector** — built around a pluggable `SmsProviderClient` interface so the underlying provider is a runtime choice, not a code change: in dev, it redirects the SMS payload to a designated test inbox via email so a developer or QA engineer can read "what the SMS would have said" without a paid SMS account or a real phone; in staging/prod, it calls whichever real provider is currently active — MontyMobile or Twilio. Both concrete provider clients are built in Phase 3 so either can be switched on later without new development, but going live with a real provider is expected to happen after initial launch (see the roadmap). Which mode/provider is active is controlled by the Connector Settings Service and its Backoffice Settings page (Section 8), not the Config Server — an admin can switch providers, or fall back to the dev test-inbox mode temporarily, without a redeploy.
- **Core Banking Connector** — talks to a **Core Banking Simulator**, a small purpose-built Spring Boot service that mimics the real bank's REST/SOAP contract (account lookup, debit/credit, transaction status) with in-memory or Postgres-backed fake accounts. The simulator is deployed only in the dev environment (never staging or prod) so the full accounting saga — Order Manager → Core Banking Connector → bank — can be built, demoed, and tested end-to-end before real bank credentials and a production banking agreement exist. Staging and prod point the same connector at the real Core Banking System via config; the simulator's API contract must be kept in lockstep with the real bank's published spec so integration surprises don't show up for the first time in staging.

A **message bus** (Kafka or RabbitMQ — RabbitMQ is the lower-ops-overhead choice for a first release) carries every domain and notification event, and doubles as the Spring Cloud Bus transport for Config Server refresh events (Section 6). Order Manager, Order Tracking, and Product Service never publish directly from application code — each writes the event to a transactional outbox table in the same database transaction as its own state change, and a relay process (or Debezium-style CDC reading the Postgres write-ahead log) forwards it onto the bus. This closes the classic dual-write gap where a service could commit its own state but fail to notify the rest of the system, or vice versa.

### Environment matrix for the connectors

| Connector | Dev | Staging / Prod | Provider selection |
| --- | --- | --- | --- |
| Email | Real SMTP relay (can point at a sandbox/test SMTP account) | Real SMTP relay (production credentials) | Fixed (SMTP) |
| Push | Firebase (real, using a dev Firebase project) | Firebase (production project) | Fixed (Firebase) |
| SMS | Routed to a test inbox via email — no real SMS provider call | MontyMobile or Twilio (whichever is set active) | Runtime-selectable via Backoffice Settings (Section 8) |
| Core Banking | Core Banking Simulator (mock service, dev-only) | Real Core Banking System | Runtime-selectable via Backoffice Settings (dev-simulator toggle) |

---

## 8. Connector Settings — Backoffice configuration

The SMS Provider Connector is built with a pluggable provider abstraction from the start — a `SmsProviderClient` interface with separate implementations for MontyMobile, Twilio, and the dev email-passthrough mode from Section 7. Only one is "active" per environment at a time, and which one is active is a runtime setting, not a code change or redeploy. This is what makes "later on, integrate MontyMobile or Twilio" a config change instead of a migration: both concrete clients get built in Phase 3 alongside the abstraction, but neither has to be the live provider until the business is ready to cut over — the dev-passthrough mode keeps everything testable in the meantime.

A new microservice, the **Connector Settings Service**, owns this and every other connector's business-user-facing runtime configuration: which SMS provider is active (MontyMobile / Twilio / dev-passthrough), and whether the Core Banking Connector points at the simulator or the real bank. It exposes a REST API behind the API Gateway, restricted to the `BACKOFFICE` role, and is the backend for a new Settings section in the Backoffice Web App where an admin can view and change these values without a deploy.

Non-secret configuration (provider name, mode, feature flags) lives in the `settings` schema in PostgreSQL (Section 4); actual secrets (MontyMobile/Twilio API keys, bank credentials) are never stored in that table or shown in the UI — the Settings Service stores only a reference to where each secret lives in Vault, and the Backoffice UI displays a masked value plus "last rotated" metadata. Every change is written to an audit log (who changed what, from what value, when) given this page can redirect real SMS/money traffic.

Connectors need to notice a settings change without a restart: the Connector Settings Service publishes a lightweight "config changed" event over the same message bus used for domain events and Config Server refresh (Section 6/7), and each connector reloads its active provider client on receipt, with a short in-memory cache in between so a settings-service blip doesn't take a connector down.

As covered in Section 6, this service is intentionally separate from the Spring Cloud Config Server: Config Server config changes through Git and a pipeline; Connector Settings changes through this UI and are meant for values a business user, not an engineer, needs to control day to day.

---

## 9. Flutter client architecture

One Mobile App codebase serves both Customer and Delivery Rider, branching navigation and screens on the Keycloak role claim after login (order placement/tracking/checkout for Customer; delivery queue, route, and proof-of-delivery capture for Rider). The Backoffice Web App and Merchant Web Portal are separate Flutter Web entry points in the same monorepo, sharing a common package for design system, networking (Dio + auth interceptor), and Keycloak login flow, so the actual business screens are the only role-specific code.

**State management:** Riverpod or Bloc (either is fine; pick one and enforce it via lint rules).

Live order tracking uses a WebSocket/STOMP connection to Order Tracking (with REST polling fallback); push notifications arrive via Firebase Cloud Messaging, delivered end-to-end through the Push Worker → Push Provider Connector → Firebase chain shown in the diagram (the Flutter app integrates the `firebase_messaging` package for token registration and foreground/background handling).

The Backoffice Web App additionally gets a **Settings section** (`BACKOFFICE` role only): a screen per connector (SMS, Email, Push, Core Banking) showing its current provider/mode, masked credential status and last-rotated date, and a change form that calls the Connector Settings Service. The SMS screen specifically offers a provider dropdown (MontyMobile / Twilio / dev-passthrough where the environment allows it) rather than free-text, so an admin can't accidentally point production at the dev test-inbox mode.

---

## 10. Non-functional considerations & architecture recommendations

- **Reliable events (transactional outbox):** covered in Section 7 — every domain service writes events to its own outbox table rather than publishing directly, so a Postgres commit and a bus publish can never disagree with each other.
- **Resilience around external providers:** every ESB connector (Section 7) gets a circuit breaker, retry-with-backoff, an idempotency key per outbound call, and a dead-letter queue. Core Banking specifically is treated as an asynchronous saga from Order Manager, never a synchronous call in the checkout path, so bank downtime never blocks an order.
- **Tracking data volume:** `tracking_events` (Section 4) is a high-write table by nature — GPS pings from every active rider. Partition it by date (or run it under the TimescaleDB extension, which layers on Postgres without a separate database) and define a retention/downsampling policy so raw ping history doesn't grow unbounded. For the "where is my rider right now" read path, Order Tracking Service caches the latest position per rider in Redis instead of querying Postgres on every poll from the Mobile App.
- **IAM depth:** role checks plus manual ownership checks in service code (Section 3) are the right starting point. If delegated access is needed later — a merchant granting a staff account limited access, a backoffice user scoped to one region — Keycloak's Authorization Services (UMA2) can express that without hand-rolled permission logic; not needed for v1.
- **Observability:** structured logging + distributed tracing (OpenTelemetry) across the Gateway, every domain/notification/connector microservice, with a correlation ID generated at the API Gateway and threaded through the message bus and into every connector's call to its external provider. Because a single customer action can now ripple through more than a dozen independently deployed services before a notification lands, this correlation ID is what makes "why didn't this SMS arrive" answerable without grepping every service by hand — treat it as a Phase 0 requirement, not a later add-on, given the service count.
- **Deployment:** containerize every Spring Boot microservice individually and run under Docker Compose for local dev, Kubernetes for staging/production, with each service getting its own Deployment, resource limits, and horizontal pod autoscaler where relevant (Order Tracking and the Notification workers are the most likely to need independent scaling). Keycloak, PostgreSQL, Redis, MinIO, the message bus, the Config Server, and Vault all run as managed or self-hosted infrastructure services alongside the app.
- **Security:** enforce TLS everywhere including service-to-service traffic, rotate Keycloak client secrets, scope MinIO presigned URLs tightly (short TTL, single-object), and route every service's secrets through the Config Server's Vault-composited backend (Section 6) rather than letting individual services hold their own Vault credentials — this keeps Vault access centralized and auditable in one place. Give the Core Banking Connector's secret path its own Vault policy, separate from every other service's, since it's the most sensitive integration in the system.
- **MinIO lifecycle:** enable object versioning and a retention policy specifically on the `delivery-proof` bucket, since proof-of-delivery photos are dispute evidence and must not be silently overwritten or deleted; use separate buckets (or a separate MinIO deployment) per environment so staging uploads can never collide with production data.
- **Infrastructure as code:** define the Keycloak realm/clients/roles, Postgres schemas, MinIO bucket policies, message bus topology, and the Config Server's own deployment/Vault AppRole binding in Terraform (or equivalent) from the start rather than configuring them by hand — with this many independently deployed services, configuration drift between environments becomes expensive to debug quickly. The `config-repo` Git repository itself is the natural place for ongoing business-parameter and environment-variable changes once the initial Terraform bootstrap is done.
- **CI/CD:** one pipeline per microservice (build, test, container image, deploy) — well over a dozen pipelines in total given the service count, including the Config Server and Connector Settings Service — plus a shared Flutter pipeline that builds the mobile app and two web targets from one repo. Standardize the pipeline template early (Phase 0) so adding the next service doesn't mean inventing a new pipeline from scratch.

---

## 11. Phased implementation roadmap

| Phase | Focus | Key deliverables | Rough effort |
| --- | --- | --- | --- |
| **Phase 0 — Foundations & platform** | Microservices scaffolding | Repo structure with a standard per-service template; per-service CI/CD pipeline pattern; Kubernetes cluster (or equivalent) for staging; Keycloak realm/clients/roles provisioned via Terraform; Vault provisioned with AppRole auth; Spring Cloud Config Server stood up with the Git + Vault composite backend, `config-repo` initialized with per-service/per-profile files; PostgreSQL instance + schemas; Redis; MinIO buckets + policies; message bus (Kafka/RabbitMQ) provisioned, doubling as the Spring Cloud Bus transport; API Gateway skeleton; shared libraries for auth, outbox publishing, Config Client bootstrap, and OpenTelemetry tracing so every later service starts with these wired in | 4–5 weeks |
| **Phase 1 — Identity & Catalog** | Auth end-to-end, product catalog | Keycloak login wired into all 3 Flutter clients; Product Service (own deployable, own schema, Config Client) with outbox; product image upload to MinIO; Merchant Web Portal MVP (register/manage products) | 3–4 weeks |
| **Phase 2 — Ordering & Tracking** | Core delivery flow | Order Manager Service and Order Tracking Service as two independent deployables from the start, PostGIS + Redis location cache; Customer order placement/checkout in Mobile App; rider assignment & status updates; Rider flow in Mobile App; Backoffice monitoring dashboard MVP | 5–6 weeks |
| **Phase 3 — Notification & Integration Infrastructure** | Full diagram notification layer, as independent services | Notifications Manager, Mail/Push/SMS Worker services, and SMS/Email/Push Provider Connector services (each with circuit breaker, retry, idempotency, DLQ) — all as separate deployables consuming events off the outbox-backed bus; Email Connector wired to SMTP; Push Connector wired to Firebase (FCM); SMS Connector built with its pluggable provider abstraction plus dev-profile email-passthrough, and concrete MontyMobile and Twilio clients (built but not yet live in prod); Connector Settings Service + `settings` schema + audit log; Backoffice Settings section wired to it (Section 8); App Notification Service (in-app messages over WebSocket) | 6–7 weeks |
| **Phase 4 — Accounting / Core Banking Integration** | Financial reconciliation | Core Banking Simulator service built and deployed to dev (mimics the bank's account/debit/credit/status contract); Core Banking Connector service (async saga from Order Manager) built and tested end-to-end against the simulator, with its dev/prod toggle exposed through the Settings page; `accounting` schema + sync logging; reconciliation view in Backoffice | 3–4 weeks |
| **Phase 5 — Hardening & Launch** | Production readiness | Security review (token scopes, MinIO policies, per-connector credential isolation, Vault AppRole scoping, Settings audit log verified), load testing (tracking write path and the full notification fan-out especially), correlation-ID tracing verified end-to-end across all services, UAT, deployment automation, go-live (SMS still in dev-passthrough or a soft-launch provider at this point — see Phase 6) | 3 weeks |
| **Phase 6 — SMS Provider Cutover** (fast-follow, post-launch) | Go live with a real SMS vendor | Confirm which of MontyMobile / Twilio is the primary vendor (commercial terms, deliverability, local carrier support); credential provisioning in Vault; switch the active SMS provider from dev-passthrough to the chosen vendor via the Backoffice Settings page in staging first, then prod; monitor delivery rates before fully retiring the test-inbox fallback | 1–2 weeks |

**Total (Phases 0–5, to initial launch):** roughly **24–29 weeks (≈6–7 months)** for a small-to-mid sized team (assume 3 backend, 2 Flutter, 1 dedicated DevOps/platform engineer, part-time QA — adjust proportionally for a different team size), plus a short Phase 6 fast-follow once a commercial decision on MontyMobile vs. Twilio is made.

This is longer than a consolidated-then-split approach would be, because Phase 0 now has to stand up the full per-service CI/CD, tracing, outbox tooling, and the Config Server/Vault composite before any business feature ships — that upfront cost is the trade-off for never having to migrate a monolith later, and for never having a service ship with ungoverned, hand-copied configuration. Phases 1 and 2 can run partly in parallel once Phase 0 is done (catalog and ordering teams can work independently against their own services), which is the fastest lever for shortening the overall timeline if needed. Because the SMS provider abstraction and Settings page are built in Phase 3, launching before the MontyMobile/Twilio decision is finalized is safe — the app can go live in dev-passthrough or a manually-operated interim mode and cut over later with no code changes.

---

## 12. Open decisions to confirm before Phase 1

**Connector integrations are now settled:** Email over SMTP, Push via Firebase, SMS pluggable between MontyMobile/Twilio/dev-passthrough and switchable through a new Backoffice Settings page, and Core Banking against a purpose-built simulator in dev with a runtime toggle to the real system (see Sections 7–8). **Centralized configuration is also settled:** a Spring Cloud Config Server with a Git-backed store for business parameters and environment variables, composited with Vault for secrets, feeding every microservice at bootstrap (Section 6).

**What's still open:**

1. Whether Customer needs a real Keycloak role (`CUSTOMER`) or can remain the "no special role" default.
2. Who owns the Phase 0 platform work (Kubernetes, per-service CI/CD template, tracing/outbox shared libraries, Config Server + Vault standup) since it now gates every other team's start date.
3. Who owns and reviews changes to the `config-repo` Git repository (i.e., who can approve a PR that changes a business parameter or environment variable in production).
4. Which SMTP relay and Firebase project to provision for staging/prod (and who holds those credentials in Vault).
5. Who owns building and maintaining the Core Banking Simulator's contract so it doesn't drift from the real bank's spec over time.
6. Which of MontyMobile or Twilio is the primary SMS vendor (a commercial/ops decision, not a technical one, since both connector implementations are built regardless).
7. Who within `BACKOFFICE` is allowed to change connector settings (all `BACKOFFICE` users, or a narrower `BACKOFFICE_ADMIN` sub-role).
8. Where Vault itself is hosted and who administers its AppRole bindings, since both the Config Server and the Connector Settings Service depend on it from Phase 0/3 onward.

---

## Appendix A — Design system quick reference

Pulled from the approved Phase 1 screens (Section on UI/UX in this brief) for implementing the actual Flutter theme — a `ThemeData`/design-tokens file should mirror this table directly rather than re-deriving colors from the mockups by eye.

| Token | Hex | Use |
| --- | --- | --- |
| Rose (primary) | `#C41D4E` | Primary buttons, active nav state, brand accents |
| Rose (dark) | `#8E1235` | Gradients, header fills, hover/pressed states |
| Rose (soft) | `#FDEDF1` | Badges, subtle tinted backgrounds, empty-state icon rings |
| Rose (line) | `#F1C6D3` | Borders on brand-tinted surfaces (e.g., dropzones) |
| Ink (text) | `#241319` | Primary text |
| Muted (text) | `#7E6A73` | Secondary / help text |
| Border | `#EAD9DF` | Card and input borders |
| Background | `#FCF6F8` | App / page background |
| White | `#FFFFFF` | Cards, surfaces, primary-button text |

Re-cut from fire-engine red to rose on 2026-08-12. The hues were rotated to ~345°, but the values
were chosen against WCAG contrast rather than by eye — white-on-primary improved from 4.98 to 5.78,
and primary-on-soft-tint from 4.30 (below AA for body text) to 5.11. `delivery_design_system` holds
these as the single source of truth and a test asserts both the exact hexes and the contrast floor;
the Keycloak login theme carries its own copy as CSS custom properties, because it is the one
surface that cannot import the Dart tokens.

**Typeface:** Inter, with system-font fallback (`-apple-system, 'Segoe UI', sans-serif`) for platforms where it isn't bundled.

Primary actions are solid red fill with white text; secondary actions are white with a 1.5px red border and red text — never both solid on the same screen at equal visual weight, so the primary action stays unambiguous.

**Status badges** use a small semantic palette layered on top of red/white, deliberately kept separate from the brand pair since these are functional indicators, not brand color: placed = blue-gray, preparing = amber, in-transit = red (reuses brand red, since "in transit" is the state the red brand naturally draws the eye to), delivered = green, offline/inactive = neutral gray. Keep this mapping consistent across Backoffice tables, Merchant Portal statuses, and in-app order tracking — a status shouldn't change color meaning between screens.

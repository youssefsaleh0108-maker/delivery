#!/bin/sh
# Enables AppRole, binds the Config Server's read-only policy to a role, and seeds dev secrets.
# Idempotent: re-running is safe and is what happens on every `docker compose up`.
set -eu

echo "==> Waiting for Vault"
until vault status >/dev/null 2>&1; do sleep 1; done

echo "==> Enabling AppRole auth"
vault auth enable approle 2>/dev/null || echo "    (already enabled)"

echo "==> Writing policies"
vault policy write config-server /policies/config-server.hcl
vault policy write corebanking-connector /policies/corebanking-connector.hcl

echo "==> Creating config-server AppRole"
vault write auth/approle/role/config-server \
  token_policies="config-server" \
  token_ttl=1h \
  token_max_ttl=4h \
  secret_id_ttl=0 \
  secret_id_num_uses=0

# LOCAL DEV ONLY -------------------------------------------------------------------------------
# Pinning a known role-id and secret-id lets docker-compose hand the Config Server its credentials
# through the environment without an orchestration dance on every boot. In staging and production
# these are generated per-deployment and delivered by the platform (Kubernetes AppRole binding),
# never fixed and never committed. If you see these literal values outside a laptop, that is a bug.
vault write auth/approle/role/config-server/role-id \
  role_id="${CONFIG_SERVER_ROLE_ID}"
# Re-registering an existing secret-id is a 500, not a no-op, so tolerate it explicitly -
# otherwise every `docker compose up` after the first fails here and blocks the Config Server.
vault write auth/approle/role/config-server/custom-secret-id \
  secret_id="${CONFIG_SERVER_SECRET_ID}" >/dev/null 2>&1 \
  || echo "    (secret-id already registered)"
# ----------------------------------------------------------------------------------------------

echo "==> Seeding dev secrets"
# Composited into the Git-backed properties by the Config Server. A client fetching its config
# receives these merged in and cannot tell they came from a different backend (Section 6).

# Shared across all services.
# Taken from the environment, not hardcoded. These are the credentials of the SHARED
# infrastructure — the same RabbitMQ and Redis the compose file starts with generated passwords —
# so a literal here means Vault hands every service a password that was correct on a laptop and is
# wrong on any box with a real .env. The service DB passwords below are different: those match
# postgres/init/02-service-roles.sql, which hardcodes them too, so both sides move together.
vault kv put secret/application \
  spring.rabbitmq.password="${RABBITMQ_PASSWORD:-delivery}" \
  spring.data.redis.password="${REDIS_PASSWORD:-delivery}"

# Per-service database credentials, matching the roles created in postgres/init/02-service-roles.sql.
# Product Service also holds MinIO credentials, because it issues presigned URLs for product
# images. Section 5: no client ever holds these - the service mints a short-lived, single-object
# URL after checking the caller's role and ownership.
vault kv put secret/product-service \
  spring.datasource.password="product_service_dev_pw" \
  delivery.storage.minio.access-key="${MINIO_ROOT_USER:-delivery}" \
  delivery.storage.minio.secret-key="${MINIO_ROOT_PASSWORD:-delivery123}"
vault kv put secret/order-manager      spring.datasource.password="order_manager_dev_pw"
vault kv put secret/order-tracking     spring.datasource.password="order_tracking_dev_pw" \
                                       spring.data.redis.password="${REDIS_PASSWORD:-delivery}"
vault kv put secret/connector-settings spring.datasource.password="connector_settings_dev_pw"

# The notification layer. Both services own tables in the `notification` schema and share its
# database role; the Keycloak client secret lets Notifications Manager read user contact details
# through a service account scoped to view-users and nothing else.
vault kv put secret/notifications-manager \
  spring.datasource.password="notification_service_dev_pw" \
  delivery.notifications.keycloak.client-secret="notifications-manager-dev-secret"
vault kv put secret/app-notification \
  spring.datasource.password="notification_service_dev_pw"

# Phase 4. accounting-service holds business rules and a database; it never sees a bank credential.
vault kv put secret/accounting-service \
  spring.datasource.password="accounting_service_dev_pw" \
  delivery.accounting.keycloak.client-secret="accounting-service-dev-secret"
# Dev only - the simulator is never deployed to staging or production.
vault kv put secret/corebanking-simulator \
  spring.datasource.password="corebanking_simulator_dev_pw"

# MinIO credentials for the file service (Section 5: no client ever holds these).
vault kv put secret/file-service \
  delivery.storage.minio.access-key="${MINIO_ROOT_USER:-delivery}" \
  delivery.storage.minio.secret-key="${MINIO_ROOT_PASSWORD:-delivery123}"

# Connector credential slots. Empty on purpose - Phase 3/4 fills them, and the SMS connector runs
# in dev-passthrough mode until a commercial decision is made between MontyMobile and Twilio
# (Section 12, open decision #6). The paths exist so the Settings Service has somewhere to point.
vault kv put secret/sms-connector \
  montymobile.api-key="" \
  twilio.account-sid="" \
  twilio.auth-token=""
vault kv put secret/email-connector \
  spring.mail.password=""
vault kv put secret/push-connector \
  firebase.service-account-json=""
# Section 10 gives this path its own policy - it is the most sensitive integration in the system.
# The simulator key is a dev constant and protects nothing; the real bank's credentials stay empty
# until the banking agreement exists, and RealBankClient refuses every posting while they are.
vault kv put secret/corebanking-connector \
  delivery.corebanking.simulator.api-key="simulator-dev-key" \
  delivery.corebanking.real.client-id="" \
  delivery.corebanking.real.client-secret=""

echo "==> Vault bootstrap complete"
vault kv list secret/

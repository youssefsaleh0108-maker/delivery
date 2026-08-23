-- The Config Server's backing store, replacing the Git repository at config-repo/.
--
-- Runs once, on first initialisation of an empty Postgres data directory, like the other scripts
-- here. Adding a property to an ALREADY RUNNING database means an INSERT by hand — this file will
-- not re-run, and editing it after the first start has no effect.
--
-- Shape is what spring-cloud-config-server's JdbcEnvironmentRepository expects: one row per
-- resolved property, looked up by (application, profile, label). The column names are prop_key and
-- prop_value rather than the default KEY and VALUE, and the query is overridden to match in the
-- Config Server's application.yml.

\connect delivery

CREATE SCHEMA IF NOT EXISTS config;

CREATE TABLE IF NOT EXISTS config.config_properties (
    id          BIGSERIAL PRIMARY KEY,
    application VARCHAR(128) NOT NULL,
    profile     VARCHAR(128) NOT NULL,
    -- 'main' throughout, matching spring.cloud.config.server.default-label. It is a label rather
    -- than a branch now, but the value is kept so that nothing else has to change.
    label       VARCHAR(128) NOT NULL DEFAULT 'main',
    prop_key    VARCHAR(512) NOT NULL,
    -- TEXT, not VARCHAR(255): the default schema in the Spring docs caps values at 255 characters,
    -- which silently truncates a long JDBC URL or a comma-joined list. Nothing here is near that
    -- limit today and the constraint buys nothing.
    prop_value  TEXT NOT NULL,
    created_on  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- One value per key per (application, profile, label). Without this a duplicated INSERT gives
    -- the lookup two rows for one key and which one wins is down to ORDER BY.
    CONSTRAINT config_properties_unique UNIQUE (application, profile, label, prop_key)
);

-- The lookup the Config Server makes on every request.
CREATE INDEX IF NOT EXISTS config_properties_lookup
    ON config.config_properties (application, profile, label);

-- ---------------------------------------------------------------------------------------------
-- Seed, converted from config-repo/. YAML nesting flattens to dot-notation keys; a YAML list
-- becomes one indexed row per element, which is the form Spring's relaxed binding expects.
-- ---------------------------------------------------------------------------------------------

-- config-repo/application.yml — served to EVERY service alongside its own properties.
--
-- The azp allow-list: which Keycloak clients' tokens this platform accepts at all. Finding 1 of
-- docs/SECURITY_REVIEW.md. AuthorizedPartyValidator DISABLES ITSELF WHEN THE LIST IS EMPTY, so
-- losing these three rows is not a startup error — it is a platform that quietly stops checking.
-- Two clients, not four: delivery-portal replaced backoffice-web, merchant-portal and
-- carrier-portal when the three web apps merged into one.
--
-- carrier-portal was never in this list, which meant every Carrier token was refused by
-- AuthorizedPartyValidator on every service. The merge removes that class of bug — there is one
-- browser client now, so there is one entry to forget.
INSERT INTO config.config_properties (application, profile, label, prop_key, prop_value) VALUES
  ('application', 'default', 'main', 'delivery.security.allowed-client-ids[0]', 'mobile-app'),
  ('application', 'default', 'main', 'delivery.security.allowed-client-ids[1]', 'delivery-portal');

-- Per-service datasource wiring. Each service's own application.yml defaults point at
-- localhost:5433 for IDE use; these override that with the in-network address. Passwords are NOT
-- here — they come from Vault, composited into the same response (Section 6).
INSERT INTO config.config_properties (application, profile, label, prop_key, prop_value) VALUES
  ('accounting-service',    'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=accounting'),
  ('accounting-service',    'docker', 'main', 'spring.datasource.username', 'accounting_service'),

  ('app-notification',      'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=notification'),
  ('app-notification',      'docker', 'main', 'spring.datasource.username', 'notification_service'),

  ('connector-settings',    'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=settings'),
  ('connector-settings',    'docker', 'main', 'spring.datasource.username', 'connector_settings'),

  ('notifications-manager', 'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=notification'),
  ('notifications-manager', 'docker', 'main', 'spring.datasource.username', 'notification_service'),

  ('onboarding-service',    'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=onboarding'),
  ('onboarding-service',    'docker', 'main', 'spring.datasource.username', 'onboarding_service'),

  ('whatsapp-service',      'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=whatsapp'),
  ('whatsapp-service',      'docker', 'main', 'spring.datasource.username', 'whatsapp_service'),

  -- order-manager had no entry in config-repo at all, and so had none here either. Its own
  -- application.yml defaults to ${DB_URL:jdbc:postgresql://localhost:5433/...} for running from an
  -- IDE, and localhost inside a container is the container — so it started, found no Postgres, and
  -- died in Flyway with "Connection to localhost:5433 refused" while every other service came up.
  --
  -- Nothing in compose ever set DB_URL, so this row is the only thing that points it at the
  -- database. Found on the first deploy where the whole stack actually had to run at once.
  ('order-manager',         'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=orders'),
  ('order-manager',         'docker', 'main', 'spring.datasource.username', 'order_manager'),

  ('order-tracking',        'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=tracking'),
  ('order-tracking',        'docker', 'main', 'spring.datasource.username', 'order_tracking'),
  ('order-tracking',        'docker', 'main', 'spring.data.redis.host',     'redis'),
  ('order-tracking',        'docker', 'main', 'spring.data.redis.port',     '6379'),

  ('product-service',       'docker', 'main', 'spring.datasource.url',      'jdbc:postgresql://postgres:5432/delivery?currentSchema=product'),
  ('product-service',       'docker', 'main', 'spring.datasource.username', 'product_service'),
  -- The in-network MinIO address. The PUBLIC endpoint that presigned URLs are signed against —
  -- what a browser must be able to reach — still comes from the environment, not from here.
  ('product-service',       'docker', 'main', 'delivery.storage.minio.endpoint', 'http://minio:9000');

-- ---------------------------------------------------------------------------------------------
-- The Config Server's own role. SELECT on one table and nothing else: this connection resolves
-- every service's configuration, so anything it can reach is effectively public to the platform.
--
-- The password here is LOCAL DEV ONLY, following the same convention as 02-service-roles.sql. In
-- staging and production this role is created with a real password and CONFIG_DB_PASSWORD carries
-- it — the Config Server cannot resolve its own credentials from itself.
-- ---------------------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'config_server') THEN
    CREATE ROLE config_server LOGIN PASSWORD 'config_server_dev_pw';
  END IF;
END
$$;

GRANT USAGE ON SCHEMA config TO config_server;
GRANT SELECT ON config.config_properties TO config_server;
-- No INSERT, UPDATE or DELETE. The Config Server reads configuration; it does not author it.

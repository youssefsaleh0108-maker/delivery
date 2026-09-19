-- One database role per service, each owning exactly its own schema.
--
-- This is what makes "schema-per-service" a real boundary rather than a naming convention: Order
-- Manager physically cannot read the product tables, so a service can never quietly grow a
-- cross-schema join that would couple two deployables together.
--
-- Passwords here are LOCAL DEV ONLY. In staging and production these roles are created by
-- Terraform and their passwords live in Vault, resolved through the Config Server (Section 6).
--
-- Not so in dev and qa: there, the services in use still log in with these role-derived passwords,
-- which the repository published. Replacing them is the production secrets refactor's work (see
-- deploy/k3s/README.md). What can be closed without it is closed below: the roles nothing logs in
-- as cannot log in at all.

\connect delivery

DO $$
DECLARE
    svc          text;
    svc_schema   text;
    services     text[][] := ARRAY[
        ['identity_service',      'identity'],
        ['product_service',       'product'],
        ['order_manager',         'orders'],
        ['order_tracking',        'tracking'],
        ['notification_service',  'notification'],
        ['file_service',          'files'],
        ['accounting_service',    'accounting'],
        ['connector_settings',    'settings'],
        ['transfer_service',      'transfer'],
        -- Dev only. Deliberately has no grant on any platform schema: the simulator is an external
        -- system as far as this architecture is concerned, and it should be as unable to read the
        -- accounting tables as the real bank is.
        ['corebanking_simulator', 'corebanking'],
        -- The merchant's WhatsApp front door: conversations, the messages in them, and the drafts
        -- a merchant turns into orders. Owns no order data — placing one goes through Order
        -- Manager like any other order.
        ['whatsapp_service',      'whatsapp'],
        -- Owns applications to join the platform and the Camunda tables behind their review.
        ['onboarding_service',    'onboarding']
    ];
    i int;
BEGIN
    FOR i IN 1 .. array_length(services, 1) LOOP
        svc        := services[i][1];
        svc_schema := services[i][2];

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = svc) THEN
            EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', svc, svc || '_dev_pw');
        END IF;

        EXECUTE format('GRANT USAGE, CREATE ON SCHEMA %I TO %I', svc_schema, svc);
        EXECUTE format('ALTER SCHEMA %I OWNER TO %I', svc_schema, svc);
        -- So Flyway-created tables are usable by the same role without a re-grant per migration.
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON TABLES TO %I', svc_schema, svc);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT ALL ON SEQUENCES TO %I', svc_schema, svc);
        -- PostGIS types live in public; tracking needs them resolvable.
        EXECUTE format('GRANT USAGE ON SCHEMA public TO %I', svc);
    END LOOP;
END
$$;

-- No deployed service logs in as these three: identity_service and file_service own schemas that
-- nothing connects to, and corebanking_simulator is dev-only and never deployed here. A login that
-- works with a password printed above opens a door for nobody, so there is none. Give a role LOGIN
-- and a password from a Secret on the day a service needs it.
ALTER ROLE identity_service NOLOGIN PASSWORD NULL;
ALTER ROLE file_service NOLOGIN PASSWORD NULL;
ALTER ROLE corebanking_simulator NOLOGIN PASSWORD NULL;

-- Read-only role for the Backoffice reconciliation views and for ad-hoc operator queries.
-- Deliberately has no write grant anywhere.
-- It cannot log in until an operator gives it a password of their own (ALTER ROLE ... LOGIN
-- PASSWORD ...): the one this file used to set was published with the repository.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'delivery_readonly') THEN
        CREATE ROLE delivery_readonly NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA identity, product, orders, tracking, notification, files, accounting, settings,
    transfer
    TO delivery_readonly;

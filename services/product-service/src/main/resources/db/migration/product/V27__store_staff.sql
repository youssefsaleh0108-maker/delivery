-- Shop staff: who works at a store, what they may do, and when they were on shift.
--
-- The OWNER is deliberately never a row here. `stores.merchant_id == sub` already IS ownership
-- (Store.isOwnedBy), the owner holds every permission by definition, and giving them an editable
-- row would create a way to lock the owner out of their own shop.
--
-- Employees authenticate as themselves: an owner mints an invite code, the employee signs up
-- through the ordinary customer path and redeems it with their own token. Nothing here creates
-- Keycloak accounts, so no merchant can mint identities.

CREATE TABLE staff_members (
    id uuid PRIMARY KEY,
    store_id uuid NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    -- Keycloak sub, same shape and reasoning as provider_users in order-manager.
    user_ref varchar(64) NOT NULL,
    role varchar(16) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'ACTIVE',
    display_name varchar(120) NOT NULL,
    email varchar(200),
    phone varchar(32),
    -- Per-person deviations from the store's role band. {} means "exactly what the role grants".
    permission_overrides jsonb NOT NULL DEFAULT '{}'::jsonb,
    -- Optional till PIN (BCrypt). Null means this member signs in normally and has no quick unlock.
    pin_hash varchar(100),
    last_seen_at timestamptz,
    added_by varchar(64) NOT NULL,
    added_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    removed_at timestamptz,
    removed_by varchar(64),
    -- Carried on staff.member_changed so each consuming service can upsert its projection by it
    -- and ignore a stale redelivery.
    version bigint NOT NULL DEFAULT 1,
    CONSTRAINT chk_member_role CHECK (role IN ('MANAGER','CASHIER','STOCKKEEPER')),
    CONSTRAINT chk_member_status CHECK (status IN ('ACTIVE','INACTIVE')),
    CONSTRAINT chk_member_removed CHECK ((removed_at IS NULL) = (removed_by IS NULL))
);

-- One active shop per person: "which shop am I standing in" must never be ambiguous at a register.
CREATE UNIQUE INDEX uq_member_active_user ON staff_members (user_ref) WHERE removed_at IS NULL;
CREATE UNIQUE INDEX uq_member_active_email ON staff_members (store_id, lower(email))
    WHERE removed_at IS NULL AND email IS NOT NULL;
CREATE INDEX idx_members_store ON staff_members (store_id, removed_at, role);

-- The "Role Permissions Config" band from the staff screen. Rows record DEVIATIONS from the
-- platform defaults only, so a store that never touches the panel stores nothing.
CREATE TABLE store_role_permissions (
    store_id uuid NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    role varchar(16) NOT NULL,
    permission varchar(32) NOT NULL,
    granted boolean NOT NULL,
    updated_by varchar(64) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (store_id, role, permission),
    CONSTRAINT chk_rp_permission CHECK (permission IN ('POS_SALES','POS_REFUNDS_VOIDS',
        'MODIFY_INVENTORY_PRICING','MANAGE_ORDERS','VIEW_REPORTS','ACCESS_SETTINGS','MANAGE_STAFF'))
);

-- Invite codes. The employee redeems one with their own token; the row binds to their sub.
CREATE TABLE staff_invites (
    code varchar(12) PRIMARY KEY,
    store_id uuid NOT NULL REFERENCES stores (id) ON DELETE CASCADE,
    role varchar(16) NOT NULL,
    display_name varchar(120),
    email varchar(200),
    phone varchar(32),
    created_by varchar(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    accepted_by varchar(64),
    accepted_at timestamptz,
    CONSTRAINT chk_invite_role CHECK (role IN ('MANAGER','CASHIER','STOCKKEEPER')),
    CONSTRAINT chk_invite_accepted CHECK ((accepted_at IS NULL) = (accepted_by IS NULL))
);
CREATE INDEX idx_staff_invites_store ON staff_invites (store_id, created_at DESC);

-- Attendance. Deliberately distinct from a POS cash-drawer session, which pos-service owns: a
-- cashier can be on shift across several drawer sessions, and a stockkeeper has no drawer at all.
CREATE TABLE staff_shifts (
    id uuid PRIMARY KEY,
    store_id uuid NOT NULL,
    member_id uuid NOT NULL REFERENCES staff_members (id) ON DELETE CASCADE,
    user_ref varchar(64) NOT NULL,
    clocked_in_at timestamptz NOT NULL DEFAULT now(),
    clocked_out_at timestamptz,
    clocked_out_by varchar(64),
    source varchar(16) NOT NULL DEFAULT 'SELF',
    CONSTRAINT chk_shift_order CHECK (clocked_out_at IS NULL OR clocked_out_at >= clocked_in_at),
    CONSTRAINT chk_shift_closed CHECK ((clocked_out_at IS NULL) = (clocked_out_by IS NULL)),
    CONSTRAINT chk_shift_source CHECK (source IN ('SELF','MANAGER','AUTO'))
);
CREATE UNIQUE INDEX uq_open_shift_per_member ON staff_shifts (member_id) WHERE clocked_out_at IS NULL;
CREATE INDEX idx_shifts_store_time ON staff_shifts (store_id, clocked_in_at DESC);

-- Who changed whose access, and when. Permission edits are exactly the kind of change a shop
-- argues about later.
CREATE TABLE staff_audit (
    id bigserial PRIMARY KEY,
    store_id uuid NOT NULL,
    member_id uuid,
    actor_ref varchar(64) NOT NULL,
    action varchar(32) NOT NULL,
    detail jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_staff_audit_store ON staff_audit (store_id, occurred_at DESC);

CREATE TRIGGER trg_members_updated_at BEFORE UPDATE ON staff_members
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

#!/bin/sh
# Applies realm changes to an ALREADY-IMPORTED realm.
#
# `start-dev --import-realm` only runs against a realm that does not exist yet, so editing
# realm-delivery-platform.json does nothing to a running stack. The documented alternative is
# `docker compose down -v && docker compose up -d`, which also wipes the Postgres volume and every
# order and product in it. This script is the non-destructive path for a dev environment that
# already has data worth keeping.
#
# The realm JSON stays the source of truth - anything added here must also be added there, or a
# fresh `down -v` environment will not match this one. Every operation below is idempotent, so
# re-running is safe and is the intended way to use it.
#
# Run with:  docker compose exec -T keycloak sh /realm-updates.sh
set -eu

KCADM=/opt/keycloak/bin/kcadm.sh
REALM=delivery-platform
ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

echo "==> Authenticating"
$KCADM config credentials --server http://localhost:8080 --realm master \
  --user "$ADMIN_USER" --password "$ADMIN_PASS"

# ---------------------------------------------------------------------------------------------
# Service-account clients.
#
# Domain events carry Keycloak subs, not contact details or account numbers. These clients are how
# a service resolves one into the other. Both are scoped to view-users and nothing else: a service
# that reads an email address or a payout account must not be able to write one.
#
# Separate clients rather than one shared "backend" account, so a compromised notification service
# cannot read anything the accounting service reads, and so the audit trail names which service
# looked a user up.
# ---------------------------------------------------------------------------------------------
service_account_client() {
  client_id=$1
  display_name=$2
  client_secret=$3

  echo "==> Service-account client $client_id"
  existing=$($KCADM get clients -r "$REALM" -q clientId="$client_id" --fields id --format csv --noquotes)

  if [ -z "$existing" ]; then
    $KCADM create clients -r "$REALM" \
      -s clientId="$client_id" \
      -s name="$display_name" \
      -s enabled=true \
      -s publicClient=false \
      -s bearerOnly=false \
      -s standardFlowEnabled=false \
      -s implicitFlowEnabled=false \
      -s directAccessGrantsEnabled=false \
      -s serviceAccountsEnabled=true \
      -s secret="$client_secret"
    echo "    created"
  else
    # Re-assert the secret so this script also serves as a rotation path.
    $KCADM update "clients/$existing" -r "$REALM" -s secret="$client_secret"
    echo "    already present, secret re-asserted"
  fi

  client_uuid=$($KCADM get clients -r "$REALM" -q clientId="$client_id" --fields id --format csv --noquotes)
  service_account_id=$($KCADM get "clients/$client_uuid/service-account-user" -r "$REALM" \
    --fields id --format csv --noquotes)

  # add-roles is a no-op when the role is already assigned, so this is safe to repeat.
  $KCADM add-roles -r "$REALM" --uid "$service_account_id" \
    --cclientid realm-management --rolename view-users \
    || echo "    (view-users already granted)"
}

service_account_client notifications-manager "Notifications Manager service account" \
  "${NOTIFICATIONS_MANAGER_SECRET:-notifications-manager-dev-secret}"
service_account_client accounting-service "Accounting Service service account" \
  "${ACCOUNTING_SERVICE_SECRET:-accounting-service-dev-secret}"

# ---------------------------------------------------------------------------------------------
# Declare the contact attributes in the realm's user profile.
#
# THIS STEP IS NOT OPTIONAL, and its absence fails silently. Since Keycloak 24 the declarative user
# profile is always on, and an attribute it does not declare is DISCARDED on write with no error
# and omitted on read. Setting phoneNumber through the admin API without this returns 204, and the
# user comes back with "attributes": null - so the notification layer resolves no phone number and
# no device token, and SMS and push simply never happen with nothing anywhere saying why.
#
# Declared rather than switching unmanagedAttributePolicy to ENABLED: this way the realm states
# exactly what the platform stores about a person, and phoneNumber gets an E.164 check at the
# identity layer instead of only in the SMS worker.
# ---------------------------------------------------------------------------------------------
echo "==> Declaring contact attributes in the user profile"
cat > /tmp/user-profile.json <<'PROFILE'
{
  "attributes": [
    { "name": "username", "displayName": "${username}",
      "permissions": { "view": ["admin", "user"], "edit": ["admin", "user"] },
      "multivalued": false },
    { "name": "email", "displayName": "${email}",
      "permissions": { "view": ["admin", "user"], "edit": ["admin", "user"] },
      "validations": { "email": {}, "length": { "max": 255 } },
      "required": { "roles": ["user"] }, "multivalued": false },
    { "name": "firstName", "displayName": "${firstName}",
      "permissions": { "view": ["admin", "user"], "edit": ["admin", "user"] },
      "validations": { "length": { "max": 255 }, "person-name-prohibited-characters": {} },
      "required": { "roles": ["user"] }, "multivalued": false },
    { "name": "lastName", "displayName": "${lastName}",
      "permissions": { "view": ["admin", "user"], "edit": ["admin", "user"] },
      "validations": { "length": { "max": 255 }, "person-name-prohibited-characters": {} },
      "required": { "roles": ["user"] }, "multivalued": false },
    { "name": "phoneNumber", "displayName": "Mobile number",
      "permissions": { "view": ["admin", "user"], "edit": ["admin", "user"] },
      "validations": { "pattern": { "pattern": "^\\+[1-9]\\d{7,14}$",
                                    "error-message": "Must be an E.164 number, e.g. +15550100001" } },
      "multivalued": false },
    { "name": "fcmToken", "displayName": "Push device token",
      "permissions": { "view": ["admin"], "edit": ["admin", "user"] },
      "multivalued": false },
    { "name": "bankAccountRef", "displayName": "Settlement account",
      "permissions": { "view": ["admin"], "edit": ["admin"] },
      "multivalued": false }
  ],
  "groups": [
    { "name": "user-metadata", "displayHeader": "User metadata",
      "displayDescription": "Attributes the platform keeps about a person" }
  ]
}
PROFILE
$KCADM update users/profile -r "$REALM" -f /tmp/user-profile.json
echo "    phoneNumber and fcmToken declared"

# ---------------------------------------------------------------------------------------------
# Contact details for the dev users.
#
# phoneNumber is a user attribute rather than the OIDC phone_number claim: Keycloak neither
# populates nor validates that claim by default. fcmToken is where the mobile app stores its push
# registration token after sign-in; the placeholders here are long enough to pass the push worker's
# token sanity check so the channel can be exercised end to end.
# ---------------------------------------------------------------------------------------------
# bankAccountRef (Phase 4) is admin-edit only: it decides where money goes, so it is not something
# a user changes about themselves through a self-service profile. The values match the fake accounts
# seeded in the Core Banking Simulator.
set_contact() {
  username=$1
  phone=$2
  token=$3
  account=$4

  user_id=$($KCADM get users -r "$REALM" -q username="$username" -q exact=true \
    --fields id --format csv --noquotes)
  if [ -z "$user_id" ]; then
    echo "    $username not found, skipping"
    return
  fi
  $KCADM update "users/$user_id" -r "$REALM" \
    -s "attributes.phoneNumber=[\"$phone\"]" \
    -s "attributes.fcmToken=[\"$token\"]" \
    -s "attributes.bankAccountRef=[\"$account\"]"
  echo "    $username -> $phone / $account"
}

echo "==> Contact and settlement attributes on dev users"
set_contact customer "+15550100001" "dev-fcm-token-customer-0000000000000000000000000000" "ACC-CUSTOMER"
set_contact rider    "+15550100002" "dev-fcm-token-rider-0000000000000000000000000000000" "ACC-RIDER"
set_contact merchant "+15550100003" "dev-fcm-token-merchant-0000000000000000000000000000" "ACC-MERCHANT"

echo "==> Realm updates applied"

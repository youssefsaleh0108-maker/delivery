#!/bin/sh
# Applies the IDENTITY changes - social sign-in and phone-as-a-verified-attribute - to an
# ALREADY-IMPORTED realm.
#
# Sibling of apply-realm-updates.sh and run the same way - copied in, then executed, because the
# compose file mounts the realm and the themes into this container and nothing else:
#
#   cd infra
#   docker compose cp keycloak/apply-identity-updates.sh keycloak:/tmp/identity-updates.sh \
#     && docker compose exec -T keycloak sh /tmp/identity-updates.sh
#
# Same reason for existing, too: `start-dev --import-realm` only runs against a realm that does not
# exist yet, so editing realm-delivery-platform.json does nothing to a stack that is already up.
#
# WHY THIS IS A SECOND SCRIPT AND NOT MORE OF THE FIRST ONE. apply-realm-updates.sh is about who
# the platform can address - service accounts, contact attributes. This one is about who a person
# is allowed to become: which providers may create an account, and what has to be proved before an
# incoming Google login is allowed to attach itself to an account that already exists, and what a
# token is allowed to say about a phone number. A failure in one should not leave the other half
# applied, and this one has a step in the middle of it that belongs to a third script.
#
# Every operation is idempotent. Re-running is safe and is the intended way to use it.
#
# WHAT THIS SCRIPT DOES NOT DO: it never touches the Google provider's own representation, which is
# where the client id and secret live. That object belongs to configure-google-idp.sh, which reads
# the credentials from the environment - see the note above the Google section for why writing it
# from here would risk the secret. This script is safe to run before any credential exists.
set -eu

KCADM=/opt/keycloak/bin/kcadm.sh
REALM=delivery-platform
ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

# The hardened replacement for the built-in "first broker login". No spaces: every subsequent call
# puts this in a URL path, and kcadm does not percent-encode what it is given.
BROKER_FLOW=youdrop-first-broker-login

echo "==> Authenticating"
$KCADM config credentials --server http://localhost:8080 --realm master \
  --user "$ADMIN_USER" --password "$ADMIN_PASS"

# ---------------------------------------------------------------------------------------------
# Realm settings that account linking silently depends on.
#
# These are already the values in realm-delivery-platform.json. They are re-asserted here because
# each one is a switch that looks harmless in the admin console and quietly turns duplicate-account
# prevention off:
#
#   duplicateEmailsAllowed=true  - the broker's "does this person already have an account?" check
#                                  is only performed against email when duplicates are forbidden.
#                                  Flip this on and every Google sign-in by an existing customer
#                                  creates a SECOND account with the same address. Their orders,
#                                  their addresses and their points stay on the first one, and
#                                  nothing anywhere reports an error.
#   registrationAllowed=true     - re-opens Keycloak's own registration form, which creates local
#                                  accounts holding an email address nobody proved. Customer
#                                  sign-up goes through onboarding-service precisely so that a
#                                  one-time code is answered first.
#   loginWithEmailAllowed=false  - would leave people who signed up by email unable to sign in with
#                                  it, because the username the platform stores IS the email.
# ---------------------------------------------------------------------------------------------
echo "==> Re-asserting the realm settings account linking depends on"
$KCADM update "realms/$REALM" \
  -s duplicateEmailsAllowed=false \
  -s registrationAllowed=false \
  -s loginWithEmailAllowed=true
echo "    duplicate emails forbidden, self-registration closed, email login on"

# ---------------------------------------------------------------------------------------------
# The first-broker-login flow.
#
# THIS IS THE PART THAT MATTERS. Everything else here is plumbing.
#
# When somebody signs in with Google and the address on that Google account already belongs to a
# local account, Keycloak has to decide what to do. The built-in "first broker login" flow offers
# the person two ways to prove the existing account is theirs, and they are ALTERNATIVEs - either
# one is enough:
#
#   1. "Verify existing account by Email"  - a link is mailed to the address on the local account.
#   2. "Verify Existing Account by Re-authentication" - sign in to the local account normally.
#
# We disable (1) and leave (2) as the only route, and the reason is the attack it closes.
#
# The account on our side is keyed by email, and an email address on an account is not necessarily
# an address anybody proved. A local account can carry an unverified address: Keycloak's own
# account console lets a signed-in user change their email, and this realm does not force
# re-verification afterwards (see the note in README.md on why verifyEmail is off). So somebody can
# park a stranger's address on their own account.
#
# Now consider the mail route with `trustEmail: true` on the Google provider - which we need,
# because Google really has verified the address and asking the user to confirm it again is where
# people abandon a sign-up. Trusting the broker's address is exactly what makes the email
# verification step satisfiable by the Google login itself rather than by the person who owns the
# mailbox. The victim signs in with Google, sees a screen saying an account with their address
# already exists, agrees to link it - because it looks like their own account - and the attacker
# who parked the address now has a password into it.
#
# The confirm-link screen does not save you. It asks "do you want to link?", not "prove this is
# yours", and to the victim the honest answer is yes.
#
# Re-authentication does save you, and it does so WITHOUT depending on whether the address was ever
# verified, on what trustEmail means in this Keycloak version, or on mail being deliverable. To
# link, you sign in to the account you are linking to. An attacker cannot, and neither can a victim
# link into an attacker's account - the attempt simply fails, visibly, and nothing is joined.
#
# The cost, stated plainly: an account with no password cannot be linked this way. Partner accounts
# are created with an UPDATE_PASSWORD required action and no password set, so a partner who has
# never signed in and then tries Google first will not get through. resetPasswordAllowed is on, so
# the route back is "forgot password" - and that is a mail round trip to an address that WAS
# verified by code during their application. That is the trade, and it is the right way round: the
# rare case costs an extra step, the common case cannot be turned into a takeover.
# ---------------------------------------------------------------------------------------------
echo "==> First-broker-login flow"

flow_exists=$($KCADM get authentication/flows -r "$REALM" --fields alias --format csv --noquotes \
  | grep -x "$BROKER_FLOW" || true)

if [ -z "$flow_exists" ]; then
  # Copied from the built-in rather than declared from scratch. A hand-written flow is a nested
  # tree of executions with hand-assigned priorities, and getting one wrong produces a realm where
  # brokered login fails at a step nobody can name. Copying takes whatever the built-in flow is in
  # the Keycloak version actually running, so an upgrade that adds a step to it is inherited rather
  # than silently dropped - and only the two decisions below are ours.
  echo "    copying \"first broker login\""
  $KCADM create 'authentication/flows/first%20broker%20login/copy' -r "$REALM" \
    -s newName="$BROKER_FLOW"
else
  echo "    already present"
fi

# Finds one execution inside the flow by its authenticator id and sets its requirement.
#
# GET .../executions returns the whole tree flattened, sub-flows included, so an authenticator is
# addressable by provider id no matter how deeply the copy nested it or what it renamed the
# enclosing sub-flow to.
set_execution_requirement() {
  provider=$1
  requirement=$2

  line=$($KCADM get "authentication/flows/$BROKER_FLOW/executions" -r "$REALM" \
    --fields id,providerId,requirement --format csv --noquotes \
    | grep ",$provider," || true)

  if [ -z "$line" ]; then
    echo "    !! $provider is not in $BROKER_FLOW - the built-in flow has changed shape."
    echo "       Refusing to guess. Open the flow in the admin console before relying on it."
    return 1
  fi

  # id is the first CSV field, requirement the last. Parameter expansion rather than cut/awk: this
  # runs inside the Keycloak image, which is a minimal UBI and not guaranteed to carry either.
  exec_id=${line%%,*}
  current=${line##*,}

  # Positional parsing of a projected CSV is an assumption about kcadm, not a guarantee from it, so
  # it is checked rather than trusted. A misparse here would PUT a requirement onto whatever id it
  # happened to pick up - silently rewiring some other step of the flow. Both halves are shaped
  # distinctively enough to confirm: a UUID and one of four known words.
  case "$exec_id" in
    ????????-????-????-????-????????????) ;;
    *)
      echo "    !! could not read an execution id out of: $line"
      echo "       kcadm's CSV field order is not what this script expects. Not writing anything."
      return 1 ;;
  esac
  case "$current" in
    REQUIRED|ALTERNATIVE|DISABLED|CONDITIONAL) ;;
    *)
      echo "    !! could not read a requirement out of: $line"
      echo "       kcadm's CSV field order is not what this script expects. Not writing anything."
      return 1 ;;
  esac

  if [ "$current" = "$requirement" ]; then
    echo "    $provider already $requirement"
    return 0
  fi

  cat > /tmp/kc-execution.json <<JSON
{ "id": "$exec_id", "requirement": "$requirement" }
JSON
  # -n so kcadm PUTs exactly this. Without it kcadm GETs the endpoint first to merge, and this
  # endpoint answers a LIST - the merge would post an array where a single execution belongs.
  $KCADM update "authentication/flows/$BROKER_FLOW/executions" -r "$REALM" -f /tmp/kc-execution.json -n
  echo "    $provider $current -> $requirement"
}

# The two decisions that make this flow ours. See the long note above.
set_execution_requirement idp-email-verification DISABLED
set_execution_requirement idp-confirm-link REQUIRED

# ---------------------------------------------------------------------------------------------
# Do not show a brand new Google user a profile form they have nothing to add to.
#
# `missing` means the review-profile screen appears only when something the realm requires was not
# supplied by the provider. Google supplies email, given_name and family_name, so for a consumer
# Google account the screen never appears and the sign-in is one tap. Set to `on` it is shown every
# time, which is a form between a person and the thing they came to do.
#
# It is also the built-in default, and it is re-asserted anyway: this is the setting that decides
# whether the sign-up is one tap or three, and a copy of a flow whose config was edited by hand in
# the console would carry the edit.
# ---------------------------------------------------------------------------------------------
echo "==> Review-profile behaviour"

cat > /tmp/kc-review-profile.json <<'JSON'
{
  "alias": "youdrop-idp-review-profile",
  "config": { "update.profile.on.first.login": "missing" }
}
JSON

review_line=$($KCADM get "authentication/flows/$BROKER_FLOW/executions" -r "$REALM" \
  --fields id,providerId,authenticationConfig --format csv --noquotes \
  | grep ",idp-review-profile" || true)

if [ -z "$review_line" ]; then
  echo "    !! idp-review-profile is not in $BROKER_FLOW - not configuring it."
else
  review_exec=${review_line%%,*}
  # Three fields when a config already exists, two when it does not. The trailing field is the
  # config id in the first case and the provider id in the second, which is how we tell them apart
  # without a JSON parser.
  review_cfg=${review_line##*,}
  case "$review_exec" in
    ????????-????-????-????-????????????) ;;
    *)
      echo "    !! could not read an execution id out of: $review_line - not writing anything."
      review_exec="" ;;
  esac
fi

if [ -n "${review_exec:-}" ]; then
  if [ "$review_cfg" = "idp-review-profile" ] || [ -z "$review_cfg" ]; then
    $KCADM create "authentication/executions/$review_exec/config" -r "$REALM" -f /tmp/kc-review-profile.json
    echo "    config created"
  else
    $KCADM update "authentication/config/$review_cfg" -r "$REALM" -f /tmp/kc-review-profile.json -n
    echo "    config updated"
  fi
fi

# ---------------------------------------------------------------------------------------------
# The Google provider.
#
# THIS SCRIPT DOES NOT WRITE THE PROVIDER REPRESENTATION, and that is a deliberate refusal rather
# than an omission.
#
# kcadm's `update` is a GET, a merge, and a PUT. The admin API returns an identity provider with
# its client secret MASKED - a row of asterisks where the value is - so the thing kcadm would merge
# into and PUT back is the mask, not the secret. Depending on the Keycloak version that either
# round-trips harmlessly or writes asterisks over a working Google credential, and the failure
# afterwards is "sign in with Google stopped working" with nothing in the realm looking wrong.
#
# Not worth finding out. configure-google-idp.sh is the one place that writes this object, because
# it is the one place that holds the credentials to write with - and it now looks up the hardened
# flow and binds to it by itself. So the check below verifies and reports; it does not write.
# ---------------------------------------------------------------------------------------------
echo "==> Google identity provider"

google_exists=$($KCADM get identity-provider/instances -r "$REALM" --fields alias --format csv --noquotes \
  | grep -x google || true)

if [ -z "$google_exists" ]; then
  echo "    not registered in this realm yet - skipping the mappers."
  echo "    Run keycloak/configure-google-idp.sh once GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET"
  echo "    exist, then run this script again to attach the flow and the mappers."
else
  current_flow=$($KCADM get identity-provider/instances/google -r "$REALM" \
    --fields firstBrokerLoginFlowAlias --format csv --noquotes || true)

  if [ "$current_flow" = "$BROKER_FLOW" ]; then
    echo "    already bound to $BROKER_FLOW"
  else
    echo "    !! bound to '$current_flow', not '$BROKER_FLOW'."
    echo "       Account linking is on the mail-link route until that changes. Re-run"
    echo "       keycloak/configure-google-idp.sh - it holds the credentials, and now that the"
    echo "       hardened flow exists it will pick it up on its own. See SOCIAL-SIGN-IN-SETUP.md."
  fi

  # ------------------------------------------------------------------------------------------
  # Mappers.
  #
  # Keycloak's Google provider already reads email, given_name and family_name off the id token by
  # itself, so two of these three are belt-and-braces. They are declared anyway because an
  # undeclared mapping is an undocumented one: what lands on the account is then a property of the
  # Keycloak version rather than of this repo, and the next person to ask "where does the name on
  # a Google account come from?" has nowhere to look.
  #
  # syncMode INHERIT means these follow the provider's own syncMode, which is IMPORT: the value is
  # written when the account is first created and never again.
  #
  # IMPORT rather than FORCE, deliberately, and email is the reason. FORCE re-copies the claims on
  # every single sign-in. Email is the key this platform links accounts on - re-copying it means a
  # change made at Google silently rewrites the address on an existing YouDrop account, and an
  # address you can change from outside is not a key you can link on. The cost of IMPORT is that a
  # customer who changes their name at Google keeps the old one here until they edit it themselves,
  # which is the smaller problem by a wide margin.
  # ------------------------------------------------------------------------------------------
  # A refused mapper is reported and stepped over rather than ending the run.
  #
  # Keycloak keeps a compatibility list per mapper type, and the `oidc-*` mapper ids are the ones
  # documented for OIDC providers - which Google is, underneath. If a Keycloak version declines one
  # of them for the `google` provider specifically, that is worth seeing in full; it is not worth
  # taking the phone-claim section below down with it, because that section has nothing to do with
  # Google and is the half a customer notices. Check the output: a "!!" line here means the mapping
  # it names is NOT in place.
  idp_mapper() {
    mapper_name=$1
    body_file=$2

    existing=$($KCADM get identity-provider/instances/google/mappers -r "$REALM" \
      --fields id,name --format csv --noquotes | grep ",$mapper_name\$" || true)

    if [ -z "$existing" ]; then
      if $KCADM create identity-provider/instances/google/mappers -r "$REALM" -f "$body_file"; then
        echo "    mapper $mapper_name created"
      else
        echo "    !! Keycloak refused the '$mapper_name' mapper. It is NOT configured."
      fi
    else
      mapper_id=${existing%%,*}
      if $KCADM update "identity-provider/instances/google/mappers/$mapper_id" -r "$REALM" -f "$body_file"; then
        echo "    mapper $mapper_name updated"
      else
        echo "    !! Keycloak refused the update to '$mapper_name'. It is unchanged."
      fi
    fi
  }

  # The username mapper is the one that is NOT decoration.
  #
  # onboarding-service creates every local account with `username = email`. If the broker derived a
  # different username - some providers use the subject id - the two paths would produce accounts
  # that look nothing alike, and every later "is this the same person?" question would have to be
  # answered on email alone. Forcing the same rule here means an account created by Google and an
  # account created by sign-up are indistinguishable afterwards, which is what makes linking, and
  # support, and every admin lookup, work the same way for both.
  cat > /tmp/kc-idp-username.json <<'JSON'
{
  "name": "username-from-email",
  "identityProviderAlias": "google",
  "identityProviderMapper": "oidc-username-idp-mapper",
  "config": {
    "syncMode": "INHERIT",
    "template": "${CLAIM.email}",
    "target": "LOCAL"
  }
}
JSON
  idp_mapper username-from-email /tmp/kc-idp-username.json

  cat > /tmp/kc-idp-email.json <<'JSON'
{
  "name": "email",
  "identityProviderAlias": "google",
  "identityProviderMapper": "oidc-user-attribute-idp-mapper",
  "config": {
    "syncMode": "INHERIT",
    "claim": "email",
    "user.attribute": "email"
  }
}
JSON
  idp_mapper email /tmp/kc-idp-email.json

  cat > /tmp/kc-idp-first-name.json <<'JSON'
{
  "name": "first-name",
  "identityProviderAlias": "google",
  "identityProviderMapper": "oidc-user-attribute-idp-mapper",
  "config": {
    "syncMode": "INHERIT",
    "claim": "given_name",
    "user.attribute": "firstName"
  }
}
JSON
  idp_mapper first-name /tmp/kc-idp-first-name.json

  cat > /tmp/kc-idp-last-name.json <<'JSON'
{
  "name": "last-name",
  "identityProviderAlias": "google",
  "identityProviderMapper": "oidc-user-attribute-idp-mapper",
  "config": {
    "syncMode": "INHERIT",
    "claim": "family_name",
    "user.attribute": "lastName"
  }
}
JSON
  idp_mapper last-name /tmp/kc-idp-last-name.json

  # Everyone who arrives through Google is a shopper. Nothing on this path can grant DELIVERY,
  # MERCHANT, CARRIER or BACKOFFICE - those are decided by the reviewed onboarding flow, and a
  # social login must never be a way around a review.
  #
  # Hardcoded rather than claim-driven on purpose: a "role from claim" mapper reads a value the
  # external provider controls, and Google is not entitled to say who administers this platform.
  cat > /tmp/kc-idp-role.json <<'JSON'
{
  "name": "customer-role",
  "identityProviderAlias": "google",
  "identityProviderMapper": "oidc-hardcoded-role-idp-mapper",
  "config": {
    "syncMode": "INHERIT",
    "role": "CUSTOMER"
  }
}
JSON
  idp_mapper customer-role /tmp/kc-idp-role.json
fi

# ---------------------------------------------------------------------------------------------
# Phone number in the token.
#
# The realm already stores phoneNumber as a declared user attribute (apply-realm-updates.sh) and
# now stores phoneNumberVerified beside it. Storing it is not enough to make it first-class: a
# service holding a token still had to call the admin API to find out whether the person it is
# talking to has a proven phone number, which is a network round trip and a service account, per
# request, to answer a question the token could have carried.
#
# These two mappers put it in the token under the OIDC standard names - `phone_number` and
# `phone_number_verified` - so a resource server can gate a phone-only action on a claim.
#
# WHY CLIENT-LEVEL MAPPERS AND NOT THE BUILT-IN `phone` CLIENT SCOPE. Keycloak ships a `phone`
# client scope that carries exactly these two mappers, reading exactly these two attribute names,
# and adding it to a client's default scopes would be the idiomatic answer. It is not used because
# turning it on for a client means writing that client's `defaultClientScopes` list into
# realm-delivery-platform.json - and README.md documents at length what happens when that list is
# written by hand and `basic` is left out of it: tokens with no `sub` claim and an ownership check
# that fails everywhere at once. A mapper attached to the client is additive, cannot drop a scope
# that was inherited, and cannot take the realm import down. If you would rather have the scope,
# add it - list every inherited scope including `basic`, and delete these two mappers when you do,
# or the claim is produced twice.
#
# The claim is on the access token as well as the id token. The id token is for the app; the access
# token is what a service sees, and the service is the one that has to decide.
# ---------------------------------------------------------------------------------------------
echo "==> Phone claims on the client tokens"

cat > /tmp/kc-pm-phone.json <<'JSON'
{
  "name": "phone number",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "user.attribute": "phoneNumber",
    "claim.name": "phone_number",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true",
    "introspection.token.claim": "true",
    "multivalued": "false",
    "aggregate.attrs": "false"
  }
}
JSON

# jsonType boolean, not String. A resource server reading this claim will write
# `token.getClaimAsBoolean("phone_number_verified")`, and the string "false" is truthy to most
# JSON-to-object mappings - so the wrong type here reads as "verified" for everyone who is not.
cat > /tmp/kc-pm-phone-verified.json <<'JSON'
{
  "name": "phone number verified",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "user.attribute": "phoneNumberVerified",
    "claim.name": "phone_number_verified",
    "jsonType.label": "boolean",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true",
    "introspection.token.claim": "true",
    "multivalued": "false",
    "aggregate.attrs": "false"
  }
}
JSON

client_protocol_mapper() {
  client_id=$1
  mapper_name=$2
  body_file=$3

  client_uuid=$($KCADM get clients -r "$REALM" -q clientId="$client_id" --fields id --format csv --noquotes)
  if [ -z "$client_uuid" ]; then
    echo "    client $client_id not found, skipping"
    return
  fi

  existing=$($KCADM get "clients/$client_uuid/protocol-mappers/models" -r "$REALM" \
    --fields id,name --format csv --noquotes | grep ",$mapper_name\$" || true)

  if [ -z "$existing" ]; then
    $KCADM create "clients/$client_uuid/protocol-mappers/models" -r "$REALM" -f "$body_file"
    echo "    $client_id: '$mapper_name' created"
  else
    mapper_id=${existing%%,*}
    $KCADM update "clients/$client_uuid/protocol-mappers/models/$mapper_id" -r "$REALM" -f "$body_file"
    echo "    $client_id: '$mapper_name' updated"
  fi
}

# mobile-app is where a customer's phone number is actually used, and delivery-portal is where
# backoffice looks at one. backend-services is bearer-only and issues nothing, so it gets neither.
for kc_client in mobile-app delivery-portal; do
  client_protocol_mapper "$kc_client" "phone number" /tmp/kc-pm-phone.json
  client_protocol_mapper "$kc_client" "phone number verified" /tmp/kc-pm-phone-verified.json
done

rm -f /tmp/kc-execution.json /tmp/kc-review-profile.json /tmp/kc-idp-username.json \
      /tmp/kc-idp-email.json /tmp/kc-idp-first-name.json /tmp/kc-idp-last-name.json \
      /tmp/kc-idp-role.json /tmp/kc-pm-phone.json /tmp/kc-pm-phone-verified.json

echo "==> Identity updates applied"

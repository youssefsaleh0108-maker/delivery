# Keycloak realm

`realm-delivery-platform.json` is imported on first boot via `start-dev --import-realm`.

> **Do not add comments to that file.** Keycloak deserialises it into `RealmRepresentation` with
> unknown-field rejection on — even a `_comment` key fails the import with
> `Unrecognized field ... not marked as ignorable`, and the container exits. All commentary about
> the realm lives here instead.

> **Do not set `defaultClientScopes` on a client unless you list `basic` in it.** Since Keycloak 20
> the `sub` (and `auth_time`) claim is emitted by the built-in **`basic`** client scope, not by the
> protocol itself. Overriding `defaultClientScopes` without it produces tokens that authenticate
> fine and carry realm roles — so `@PreAuthorize("hasRole(...)")` passes — but have **no `sub`
> claim**. Every ownership check then fails at runtime with "No authenticated subject on the current
> request", which looks like a security-config bug and is actually a missing scope. The clients here
> deliberately omit `defaultClientScopes` entirely and inherit the realm defaults.

## Scope

This file is the **local dev source of truth only**. Section 10 requires the realm, clients and
roles to be provisioned by Terraform in staging and production. This JSON is the model that
Terraform is written from, not a substitute for it.

## Realm roles

`CUSTOMER`, `DELIVERY`, `MERCHANT`, `BACKOFFICE`.

`CUSTOMER` is included as a real realm role because Section 3 recommends it: the single Mobile App
codebase branches its navigation on the role claim, and needs to tell a Customer from a Rider.

**This is Section 12 open decision #1 and is not settled.** If Customer is meant to stay
anonymous/guest instead, delete the role from this file and let the app treat "no
delivery/merchant/backoffice role" as the default customer experience. Nothing else in Phase 0
depends on the choice.

## Clients

| Client | Type | Issues roles |
| --- | --- | --- |
| `mobile-app` | public + PKCE | `CUSTOMER`, `DELIVERY` |
| `delivery-portal` | public + PKCE | `MERCHANT`, `CARRIER`, `BACKOFFICE` |
| `backend-services` | bearer-only | — validates only |
| `notifications-manager` | service account | — reads user contact details |
| `onboarding-service` | service account | — creates and updates users |
| `accounting-service` | service account | — reads settlement accounts |

`directAccessGrantsEnabled` is **on** for the three dev clients so a developer or a test script can
fetch a token with a single curl. **Turn it off in the Terraform-managed realms** — production
clients use Authorization Code + PKCE only.

## The issuer / JWKS split

The Flutter clients reach Keycloak at `http://localhost:8180`, while backend services reach it at
`http://keycloak:8080` inside the compose network. A token carries exactly one `iss`, so
`KC_HOSTNAME` pins it to the localhost form and services override `jwk-set-uri` to the internal
address to fetch signing keys. Change one without the other and every token validated inside the
network is rejected with an issuer mismatch.

## Dev users

| Username | Password | Role |
| --- | --- | --- |
| `customer` | `100001` | `CUSTOMER` |
| `rider` | `300003` | `DELIVERY` |
| `merchant` | `200002` | `MERCHANT` |
| `backoffice` | `400004` | `BACKOFFICE` |
| `carrier` | `500005` | `CARRIER` |

All of them except `backoffice` carry a `phoneNumber` and `phoneNumberVerified: true`. Those
numbers are fixtures in the `+1555…` reserved range — there is no code to answer for them, and the
verified flag is set by the seed rather than earned. Do not use one to test the verification
journey; use a number you can actually receive a message on and let onboarding-service set the
flag.

Admin console: http://localhost:8180 (`admin` / `admin`).

## Social sign-in

Setup instructions, with the exact values to paste into the Google Cloud console and the honest
account of what Apple would cost, are in **[SOCIAL-SIGN-IN-SETUP.md](SOCIAL-SIGN-IN-SETUP.md)**.
That is the file to open if you are the person holding the credentials.

What lives here:

- The `google` identity provider, **disabled**, in `realm-delivery-platform.json`. Its `clientId`
  and `clientSecret` are the literal strings `$(env:GOOGLE_CLIENT_ID)` and
  `$(env:GOOGLE_CLIENT_SECRET)` — Keycloak resolves those from the environment at import. They are
  placeholders, not credentials, and nothing in this repository holds a real one.
- Five identity-provider mappers, in the same file and re-asserted by
  `apply-identity-updates.sh`: email, first name, last name, a username template that forces
  `username = email`, and a hardcoded `CUSTOMER` role.
- `apply-identity-updates.sh`, which installs the hardened first-broker-login flow.

### Why the hardcoded role mapper is hardcoded

It grants `CUSTOMER` and nothing else, to everybody who arrives through Google. The alternative — a
"claim to role" mapper — reads a value the external provider controls, and Google is not entitled
to a say in who administers this platform. `DELIVERY`, `MERCHANT`, `CARRIER` and `BACKOFFICE` are
decided by the reviewed onboarding flow, and a social login must never be a way around a review.

### Why account linking is not left on Keycloak's defaults

An existing customer who signs in with Google on the address they already use must land in **their
own account**, not a second empty one. Keycloak gets the *detection* right by itself as long as
`duplicateEmailsAllowed` stays false — which is why `apply-identity-updates.sh` re-asserts that
setting on every run rather than trusting it.

What it does not get right by default is the *proof*. Its built-in flow accepts either a link
mailed to the existing address or a sign-in to the existing account. We disable the mailed link.
The address on a local account is not necessarily an address anybody proved — the account console
lets a signed-in user change their own email — so with a trusted broker the mailed-link route lets
the incoming Google login stand as proof for an account somebody else parked that address on. The
full argument, and the cost of the choice, is in the long comment at the top of the flow section in
`apply-identity-updates.sh`.

### Why the flow is in the script and not in the realm file

Everything else here follows the rule that the realm JSON is the source of truth and the scripts
only re-apply it. The authentication flow is the one exception, deliberately.

A flow written by hand into `authenticationFlows` is a nested tree of executions with hand-assigned
priorities and a separate `authenticatorConfig` block, and a mistake in it is not a mistake you
find on the screen it affects — the realm import fails and the container exits, which is the exact
failure this README already warns about twice. The script instead **copies whatever the built-in
flow is in the running Keycloak** and changes two requirements on it. That cannot be out of date
with the version in use, and it cannot take a fresh install down.

The consequence, stated so nobody is surprised by it: **after `docker compose down -v`, brokered
login is back on Keycloak's built-in flow until you run the script.** Google is disabled on a fresh
import anyway, so there is a window, not a hole — but run the script before you enable Google.

## Phone number as a verified attribute

The partner application flow proves a phone number before an account exists. Customer sign-up did
not, so a customer's number was a string somebody typed. This is what makes it first-class.

### What the realm stores

| Attribute | View | Edit | Meaning |
| --- | --- | --- | --- |
| `phoneNumber` | admin, user | **admin only** | E.164, validated by the user profile |
| `phoneNumberVerified` | admin, user | **admin only** | `"true"` once a code was sent to that number and answered |

Neither is user-editable, and that is the whole design. A pair where the number is self-service and
the verified flag is not is worse than having no flag: the user edits the number in the account
console, nothing clears the flag, and every service downstream now believes a number nobody proved.
Keeping both behind `manage-users` means the number and its proof move together, in one call, made
by the service that watched the code come back.

`phoneNumber` used to be user-editable. That was the change.

### What the token carries

`mobile-app` and `delivery-portal` both carry two protocol mappers, so a service does not have to
call the admin API to find out whether the person holding a token has a proven number:

| Claim | Type | Source attribute |
| --- | --- | --- |
| `phone_number` | string | `phoneNumber` |
| `phone_number_verified` | **boolean** | `phoneNumberVerified` |

Both are on the **access token** as well as the id token. The id token is for the app; the access
token is what a resource server sees, and the resource server is the one that has to decide.

Two things to know before you read the claim:

- **Absent means not verified.** An attribute that was never set produces no claim at all, so a
  service must treat a missing `phone_number_verified` as false. It must never treat a present
  `phone_number` as evidence of anything on its own.
- **`jsonType.label` is `boolean`, not `String`.** The attribute is stored as text, and the string
  `"false"` is truthy to most JSON-to-object mappings — the wrong type here would read as
  "verified" for precisely the users who are not.

These are client-level mappers rather than Keycloak's built-in `phone` client scope, which carries
the same two mappers over the same two attribute names. Using the scope would mean writing a
client's `defaultClientScopes` list into the realm file by hand, and the warning at the top of this
README is about exactly what happens when that list is written by hand and `basic` is left out of
it. A mapper attached to the client is additive and cannot drop an inherited scope. If you would
rather have the scope, add it — listing every inherited scope, `basic` included — and delete these
two mappers when you do, or the claim is produced twice.

### What Keycloak does not do here, and will not

- **It does not send the code.** `onboarding-service` owns sending and checking; see
  `VerificationService` there. The realm is where the answer is kept, not where it is obtained.
- **It cannot enforce phone verification as a login step.** A required action is a registered Java
  provider; there is no way to invent one from configuration, and registering an alias with no
  provider behind it breaks login rather than adding a step. Enforcement is therefore a claim check
  in the services that care.
- **It will not collect a number for you either.** Marking `phoneNumber` required in the user
  profile would make Keycloak's `VERIFY_PROFILE` action prompt for one at next login — and that
  was rejected on purpose. That screen *collects* a number; it does not verify one. It would leave
  accounts holding a number with `phoneNumberVerified` unset, which looks like progress and is the
  same untrusted string we started with.
- **It cannot authenticate by phone number.** Signing in with a number instead of an email needs a
  custom authenticator SPI. `loginWithEmailAllowed` covers email; there is no phone equivalent.
- **It cannot make a number unique.** Keycloak enforces uniqueness on username and email, not on
  attributes. If one phone number per account matters, that check belongs in whichever service
  writes the attribute.

## Re-importing after an edit

The import only runs against an empty realm. To pick up changes:

```bash
docker compose down -v && docker compose up -d
```

Then re-apply both scripts, in this order — a fresh import has neither the service-account secrets
nor the hardened broker flow:

```bash
cd infra
docker compose cp keycloak/apply-realm-updates.sh keycloak:/tmp/realm-updates.sh \
  && docker compose exec -T keycloak sh /tmp/realm-updates.sh
docker compose cp keycloak/apply-identity-updates.sh keycloak:/tmp/identity-updates.sh \
  && docker compose exec -T keycloak sh /tmp/identity-updates.sh
```

Both are idempotent, so running them against a realm that already has the changes is a no-op that
prints what it found.

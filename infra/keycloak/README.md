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
| `backoffice-web` | public + PKCE | `BACKOFFICE` |
| `merchant-portal` | public + PKCE | `MERCHANT` |
| `backend-services` | bearer-only | — validates only |

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
| `customer` | `customer` | `CUSTOMER` |
| `rider` | `rider` | `DELIVERY` |
| `merchant` | `merchant` | `MERCHANT` |
| `backoffice` | `backoffice` | `BACKOFFICE` |

Admin console: http://localhost:8180 (`admin` / `admin`).

## Re-importing after an edit

The import only runs against an empty realm. To pick up changes:

```bash
docker compose down -v && docker compose up -d
```

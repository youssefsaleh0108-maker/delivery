# Finish-wave backend contracts

Ground truth for the client wave. Written from the code (controllers/DTOs as of this verification
pass), not from agent reports. All endpoints require a Bearer JWT unless marked otherwise; roles are
Keycloak realm roles surfaced as `ROLE_<NAME>` (platform-security `KeycloakRealmRoleConverter`).

Conventions used below:

- Types are JSON types; `decimal` means a JSON number serialized from BigDecimal, 2 decimal places
  where money.
- "nullable" means the field can be `null` in the response; everything else is always present.
- Unless stated, business-rule errors are `{"message": string}` bodies; validation failures are
  Spring's default 400.

---

## order-manager

### POST /api/orders — place an order (changed)

Role: `CUSTOMER`. Status: **201**.

Request (`PlaceOrderRequest`) — new field only; the rest is unchanged:

| field | type | rules |
|---|---|---|
| `deliveryTier` | string enum `"STANDARD"` \| `"EXPRESS"`, optional | `null`/absent = `STANDARD`. **There is no surcharge field and never will be** — the EXPRESS price comes from server config `delivery.orders.express-surcharge` (default `2.00`), snapshotted onto the order at placement. Unknown enum value = 400. |

Response: `OrderResponse` (below). Every endpoint that returns `OrderResponse` (including
`GET /api/orders/available`, `/mine`, `/merchant`, `/carrier`, `/{id}`, transition endpoints)
now carries the two new fields.

`OrderResponse` full shape:

| field | type | notes |
|---|---|---|
| `id` | uuid | |
| `kind` | string enum (`CATALOG`, `BUTLER_*`) | |
| `customerId` | string | Keycloak subject |
| `merchantId` | string, nullable | null on errands |
| `riderId` | string, nullable | null until claimed |
| `deliveryProviderId` | uuid, nullable | the fleet; null until claimed |
| `status` | string enum `PLACED\|ACCEPTED\|PREPARING\|READY\|PICKED_UP\|DELIVERED\|CANCELLED` | |
| `totalAmount` | decimal | includes expressSurcharge, net of discount |
| `subtotal` | decimal | goods only |
| `deliveryFee` | decimal | what delivery COST (base fee), even when waived |
| `deliveryFeeCharged` | decimal | what the customer actually paid for delivery; 0 when waived |
| `deliveryTier` | string enum `STANDARD\|EXPRESS` | **new**; never changes after placement |
| `expressSurcharge` | decimal | **new**; 0 on STANDARD. Charged even when the base fee is waived — the waiver covers the delivery, not the premium. Itemise it separately on receipts ("Express +2.00"); it is NOT inside `deliveryFee` |
| `deliveryFeeWaived` / `merchantFeeWaived` / `carrierFeeWaived` | boolean | |
| `discountAmount` | decimal, nullable | |
| `promoCode` | string, nullable | canonical stored form |
| `storeId` | uuid, nullable; `storeName` | string, nullable | null on errands |
| `deliveryAddress` | string | |
| `paymentMethod` | string enum; `paymentStatus` | string enum; `paidAt` | instant, nullable | |
| `contactPhone`, `notes` | string, nullable | |
| `items` | array of line objects | |
| `availableActions` | array of string | what the calling user may do next |
| `placedAt` | instant; `acceptedAt`/`pickedUpAt`/`deliveredAt`/`cancelledAt` | instant, nullable; `cancelReason` | string, nullable | |

Total invariant: `total = subtotal + (deliveryFee unless waived) + expressSurcharge − discount`
(discount clamped so total never goes below zero).

### GET /api/orders/riders/me/performance

Role: `DELIVERY`. Rider = token subject; no parameters. Fixed 30-day window.

Response 200:

```json
{ "riderId": "kc-sub", "windowDays": 30, "claimed": 12, "delivered": 11,
  "cancelledAfterClaim": 1, "completionRate": 91.67 }
```

- `claimed`/`delivered`/`cancelledAfterClaim`: integers (long).
- `completionRate`: decimal percent, 2dp HALF_UP, **null when `claimed` = 0** (render as "—",
  never 0% or 100%).

### GET /api/orders/riders/{riderId}/performance

Roles: `BACKOFFICE` or `CARRIER`. `riderId` = Keycloak subject (string). Same response shape as
`/me/performance`.

- BACKOFFICE: the rider's whole record.
- CARRIER: only work done for the caller's own company (resolved from the caller's user id, never a
  request field). A rider who never rode for them returns all-zeros with `completionRate: null` —
  indistinguishable from a rider with no work; there is no 404 for foreign riders here.
- 404 `{"message"}`: caller holds CARRIER but belongs to no company.

### GET /api/orders/riders/delivered-today

Roles: `BACKOFFICE` (platform-wide) or `CARRIER` (own company only). No parameters.
"Today" is the platform zone (`delivery.platform.zone`, default `Asia/Beirut`), delivered_at-based.

Response 200: array, riders with zero deliveries are ABSENT (client joins onto its own roster):

```json
[ { "riderId": "kc-sub", "delivered": 4, "day": "2026-08-27" } ]
```

404 `{"message"}` for a CARRIER with no company.

### GET /api/orders/daily · /api/orders/merchant/daily · /api/orders/carrier/daily

| path | role | scope |
|---|---|---|
| `/api/orders/daily` | `BACKOFFICE` | whole platform |
| `/api/orders/merchant/daily` | `MERCHANT` | own shop (token subject) |
| `/api/orders/carrier/daily` | `CARRIER` | own company; 404 `{"message"}` if staff of no company |

Query: `days` — integer, optional, default 14, silently clamped to 1..30 (no 400 for out of range).

Response 200 (`Series`), identical shape for all three:

```json
{ "windowDays": 14, "days": [
    { "day": "2026-08-14",
      "standard": { "orders": 10, "delivered": 8, "gross": 240.50 },
      "express":  { "orders": 2,  "delivered": 2, "gross": 61.00 } }
] }
```

- `days` is complete and zero-filled: exactly `windowDays` entries, ascending, both tiers always
  present (zeros when nothing happened). Never check for missing keys.
- `orders` = placed that day regardless of outcome; `delivered` = reached a door; `gross` = sum of
  `totalAmount` over DELIVERED orders (decimal).
- **No precomputed percentages.** DoD/WoW is client arithmetic on the series.

### GET /api/orders/activity

Role: `BACKOFFICE`. Query: standard Spring paging `page` (default 0), `size` (default 20).
A poll, not a push: re-request page 0 on an interval; entries are immutable, so new rows only ever
prepend.

Response 200 (`PageResponse<Entry>`):

```json
{ "content": [
    { "occurredAt": "2026-08-27T10:15:30Z", "event": "placed", "status": "PLACED",
      "orderId": "…", "storeName": "Falafel King", "amount": 24.00 } ],
  "page": 0, "size": 20, "totalElements": 123, "totalPages": 7 }
```

- `event`: `"placed"` | `"delivered"` | `"cancelled"` | `"status-changed"` (all other statuses).
- `status`: the raw `OrderStatus` behind the event.
- `storeName`: **null on Butler errands** (no shop) — render accordingly.
- `amount`: the order's CURRENT total (decimal), not the total at the entry's moment.
- Newest first.

### Partner API keys (carrier machine credentials)

All three are human endpoints: role `CARRIER`, JWT auth, scoped to the caller's own company
(resolved from their user id; no provider id anywhere in the requests).
A caller with CARRIER but no company: 404 `{"message":"You are not a member of any delivery company"}`.

**POST /api/partner-keys** — mint. Body optional: `{ "label": string ≤80 }` (may be omitted
entirely). Status **201**:

```json
{ "id": "uuid", "secret": "ydk_<43 base64url chars>", "keyPrefix": "ydk_XXXXXXXX",
  "label": "dispatch box", "createdAt": "…" }
```

`secret` appears in this response and NOWHERE else, ever — it is hashed and not stored. Show it
once with copy-now UX. `label` nullable. `keyPrefix` = first 12 chars of the secret.

**GET /api/partner-keys** — list, newest first, revoked keys included and flagged. Status 200:

```json
[ { "id": "uuid", "keyPrefix": "ydk_XXXXXXXX", "label": null, "createdAt": "…",
    "lastUsedAt": null, "revoked": false, "revokedAt": null } ]
```

Never carries secret or hash. `label`, `lastUsedAt`, `revokedAt` nullable.

**DELETE /api/partner-keys/{id}** — revoke. **204**, effective immediately, idempotent (revoking a
revoked key is 204). Another company's key (or an unknown id): **404** RFC-7807 ProblemDetail
`{"title":"API key not found","detail":"API key <id> was not found", …}`.

### GET /api/partner/jobs — the machine surface

Auth: **`X-API-Key: ydk_…` header, no JWT.** The key resolves to the company
(`ROLE_PARTNER_API`); a revoked key, a SUSPENDED provider, or an unknown key are all refused
identically. Response 200:

```json
{ "claimable": [ { "orderId": "uuid", "status": "READY", "deliveryTier": "EXPRESS",
                   "deliveryFee": 3.25, "storeName": "…", "deliveryAddress": "…",
                   "contactPhone": "…", "placedAt": "…" } ],
  "active": [ …same shape… ] }
```

- `claimable` = offered to this company + unroutable orders every fleet sees; `active` = claimed by
  this company's riders and unfinished. Both oldest-first, capped at 100 each.
- `deliveryFee` is the BASE fee (what the company is paid from). `expressSurcharge` is deliberately
  absent — it is platform revenue. No customer id, no payment detail, no line items.

---

## onboarding-service

### POST /api/onboarding/password-reset — request a code

Auth: **none (open)**. Request: `{ "email": string, well-formed email, ≤200 }`.

- **202, empty body, always** — for known AND unknown addresses (not a directory oracle).
- 400: malformed JSON / not an email shape.
- 422 `{"message"}`: deeper normalisation refused the address.
- 429 `{"message"}`: resend cooldown (60s/destination) or daily cap (8 codes/destination/24h) —
  identical for known and unknown addresses.

Sends a 6-digit code (10-min lifetime, 5 wrong-guess cap, single-use), purpose-separated from
sign-up codes: a reset code cannot confirm a sign-up and vice versa.

### POST /api/onboarding/password-reset/confirm

Auth: **none (open)**. Request:

```json
{ "email": "≤200, email shape", "code": "≤12", "newPassword": "6–128 chars" }
```

- **204** on success. One code = one reset (consumed transactionally).
- 400: validation.
- 422 `{"message"}`: wrong / expired / spent code, attempt cap hit — and (deliberately, same
  wording as wrong-code) a correct code for an address with no account.
- 502 `{"message"}`: Keycloak refused; retryable — the code is still live (consumption rolled back).

### PATCH /api/onboarding/applications/{id} — correct a partner record

Role: `BACKOFFICE`. Request — all fields optional, absent = unchanged, whitespace-only = 422,
no way to blank a field:

```json
{ "businessName": "≤200", "contactName": "≤160", "contactEmail": "email ≤200", "contactPhone": "≤32" }
```

Response 200 (`PartnerRecordView`):

```json
{ "id": "uuid", "kind": "MERCHANT|CARRIER|RIDER", "status": "SUBMITTED|IN_REVIEW|APPROVED|REJECTED|PROVISIONED|FAILED",
  "businessName": "…", "contactName": "…", "contactEmail": "…", "contactPhone": "…",
  "emailVerifiedAt": "instant|null", "phoneVerifiedAt": "instant|null" }
```

Behaviour the client must reflect: changing the phone **nulls `phoneVerifiedAt`** (honest "not
checked"); changing `contactEmail` keeps `emailVerifiedAt` and does NOT change the sign-in
username. Every changed field writes an audit row; a no-op PATCH writes none.
422 `{"message"}`: unknown id, blank field.

### GET /api/onboarding/applications/{id}/audit

Role: `BACKOFFICE`. Response 200 — newest first, `[]` when never edited:

```json
[ { "field": "contactPhone", "oldValue": "…", "newValue": "…", "actor": "kc-sub", "at": "instant" } ]
```

### Suspension (platform side)

**POST /api/onboarding/applications/{id}/suspend** — role `BACKOFFICE`.
Request: `{ "reason": "FRAUD|ABUSE|NON_PAYMENT|POLICY_VIOLATION|PARTNER_REQUEST|OTHER" (required), "note": "≤500" (optional) }`.

Response 200 (`PartnerStandingView`):

```json
{ "suspended": true,
  "lastChange": { "suspended": true, "reason": "FRAUD", "reasonNote": "…|null",
                  "actor": "kc-sub", "at": "instant" } }
```

Revokes the partner's live realm role (MERCHANT→`MERCHANT`, CARRIER→`CARRIER`, RIDER→`DELIVERY`).
Sign-in keeps working (their history stays reachable); committing endpoints across the platform
refuse via their own `@PreAuthorize`. Idempotent: re-suspending returns the standing unchanged, no
new row, no Keycloak call.
400 missing reason · 422 `{"message"}` undecided/rejected/no sign-in account · 502 `{"message"}`
Keycloak refused (nothing recorded).

**POST /api/onboarding/applications/{id}/unsuspend** — role `BACKOFFICE`. Body OPTIONAL:
`{ "note": "≤500" }`. Response 200 `PartnerStandingView`; `lastChange` null if never touched.
Re-grants the role; idempotent the same way.

**GET /api/onboarding/applications/{id}/suspension** — role `BACKOFFICE`. Response 200:

```json
{ "suspended": false, "lastChange": { …StandingChangeView|null }, "history": [ …newest first, [] if untouched ] }
```

`reason` inside a StandingChangeView is null on reinstatement rows.

### Suspension (carrier side — own riders only)

Same shapes and semantics, role `CARRIER`, double-gated on every call: the caller must actually run
`{providerId}` (checked against Order Manager's staff record, never trusted from the URL — 403
`{"message":"That is not your delivery company"}` otherwise) AND application `{id}` must be a RIDER
application addressed to that company (422 otherwise).

- `POST /api/onboarding/applications/for-company/{providerId}/{id}/suspend`
- `POST /api/onboarding/applications/for-company/{providerId}/{id}/unsuspend`
- `GET  /api/onboarding/applications/for-company/{providerId}/{id}/suspension`

### Provider profile (company settings: logo, dispatch regions, operating hours)

Base: `/api/onboarding/providers/{providerId}/profile`. All CARRIER writes are ownership-checked
against Order Manager (403 `{"message"}` if the caller does not run `{providerId}`).

**GET** — roles `CARRIER` (own company) or `BACKOFFICE` (any company, read-only). Response 200
(`ProfileView`); a company that never saved settings gets the empty shape, never 404:

```json
{ "providerId": "uuid", "logoUrl": "https://…|null",
  "dispatchRegions": ["…"], "operatingHours": { "MONDAY": { "open": "08:00", "close": "22:00" } },
  "updatedBy": "kc-sub|null", "updatedAt": "instant|null" }
```

A day absent from `operatingHours` means closed that day.

**PUT** — role `CARRIER`. PUT semantics — the whole form replaces the stored one (a deleted region
stays deleted). Request:

```json
{ "dispatchRegions": ["…"], "operatingHours": { "MONDAY": { "open": "HH:mm", "close": "HH:mm" } } }
```

Both fields required (may be empty). Deep validation server-side (day names, HH:mm, open <
close, region cap): 422 `{"message"}`. Response 200 `ProfileView`.

**POST …/logo/presign** — role `CARRIER`. Request `{ "contentType": "image/…, ≤128" }`.
Response **201**:

```json
{ "fileId": "uuid", "uploadUrl": "…", "objectKey": "…", "contentType": "…",
  "expiresAt": "instant", "maxSizeBytes": 123 }
```

Client then PUTs the bytes straight to `uploadUrl` (never through this service).

**POST …/logo/confirm** — role `CARRIER`. Request `{ "fileId": "uuid" }`. Response 200
`ProfileView` with the new `logoUrl`. Storage problems: 422
`{"message":"That upload could not be completed. Upload the file again."}`.

---

## order-tracking

Base: `/api/tracking/riders`. Errors here are RFC-7807 ProblemDetail with `title`, `detail`,
`status`, and `correlationId`.

### GET /api/tracking/riders/me/duty/hours

Role: `DELIVERY`. Rider = token subject. Query: `days` — integer, optional, default 7, min 1,
max 30; **out of range = 400** (unlike order-manager's daily series, which clamps).

Response 200 (`HoursOnline`):

```json
{ "riderId": "kc-sub", "zone": "UTC", "from": "2026-08-21", "to": "2026-08-27",
  "days": [ { "date": "2026-08-26", "secondsOnline": 3600, "hoursOnline": 1.00, "sessions": 1 } ] }
```

- `zone`: the configured day-splitting zone (`delivery.tracking.duty-session.day-zone`, default
  `UTC`) — echoed so the client never guesses. A 23:00–01:00 shift splits across the midnight of
  this zone.
- `from`/`to`: the requested window inclusive; `to` is today in `zone`.
- `days`: ONLY dates with on-duty time, ascending; `[]` when none — the client draws its own zeros.
- `secondsOnline` (long): use for any arithmetic. `hoursOnline` (decimal) = seconds/3600 at 2dp
  HALF_UP: use for display. `sessions` (int) = distinct shifts touching that date.
- Live behaviour: an open shift counts up to now while the rider is pinging; once quiet, only to
  their last sighting — the figure can therefore only ever go up or stay, never shrink later.

### GET /api/tracking/riders/{riderId}/duty/hours

Roles: `BACKOFFICE` or `CARRIER`. Path `riderId` = Keycloak subject (string). Query `days` as
above. Response 200: same `HoursOnline` shape.

- BACKOFFICE: any rider; unknown rider → 404.
- CARRIER: fleet resolved from the caller's own membership row, never the request; the rider must
  belong to that fleet. Foreign rider and unknown rider return the **identical 404**
  (`{"title":"Rider not found","detail":"No presence information for that rider", "correlationId": …}`)
  — non-enumerable by design.
- CARRIER with no membership: **403**
  `{"title":"No delivery company","detail":"You are not a member of any delivery company", …}`.
- History starts at the feature's migration (V13); nothing is backfilled.

---

## Cross-service invariants the client may rely on

- Ids: riders/customers/merchants/staff are Keycloak subjects (opaque strings); delivery companies
  are UUIDs, and the SAME UUID everywhere (`deliveryProviderId` on orders/events, `providerId` in
  onboarding paths, the carrier scope in tracking).
- The express surcharge is platform revenue: it is inside `totalAmount`, outside `deliveryFee`, and
  settlement pays merchants from `subtotal` and carriers/riders from `deliveryFee` — so no client
  screen should ever add the surcharge to a merchant or carrier payout figure.
- A delivery-fee waiver (and FREE_DELIVERY promos) covers the base fee only; the express surcharge
  stays payable. A general discount clamps against the whole bill, so 100%-off is genuinely free.
- Series/list endpoints never invent zeros for absent entities (delivered-today, duty hours), but
  the daily trade Series IS zero-filled per day. Read each contract's note.

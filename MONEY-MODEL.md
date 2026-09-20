# YouDrop money model (reconciliation deep test, 2026-09-19)

Mapped from outer `main` decd784 and order-manager `main` 8365282. Dev ran sha-14747c9 when I tested, then
sha-12a3b27; the accounting code is identical in both and in `main`.

## 0. Conventions

- **Currency.** Every server figure is USD, `numeric(12,2)`, `BigDecimal`, HALF_UP to 2 dp. There is no
  currency column except `accounting.*.currency` ("USD" from config). Points round DOWN.
- **LBP** is only ever a conversion. transfer-service stores `split_lbp_in_usd` and `rate_used`
  (`MARKET_LBP_PER_USD`, 90000 on dev/qa). The lira face value is `round_half_up(usd × rate / 1000) × 1000`,
  computed on read. product-service `/api/market/config` serves the display copy of the rate from
  the same key and the same env var (`delivery.market.lbp-per-usd` ← `MARKET_LBP_PER_USD`), so
  display and collection cannot drift; it was unbound and stuck at the 90000 default until
  2026-09-20. Clients convert with `double`
  (`MarketRates.lbpRounded`). The ledger has no lira at all.
- **Calendars.** `delivery.accounting.statements.zone` = **UTC** (statements, carrier cash page);
  `delivery.rider-earnings.zone` = **UTC**; `delivery.accounting.payroll.zone` = **Asia/Beirut**;
  order-manager dashboards and payroll delivered-counts = **Asia/Beirut**.
- **Settlement mode** `LEDGER_ONLY`. No Core Banking connector is deployed and nothing consumes
  `accounting.posting.requested`.

## 1. Flows and the events that drive them

### 1.1 Pricing (order-manager, at placement)

`total = subtotal + (deliveryFeeWaived ? 0 : deliveryFee) + expressSurcharge − discount + giftWrapFee`

The discount is clamped to `subtotal + charged fee + express` and never touches the wrap. A DB CHECK (OM V32)
holds the rule.

| Part | Source | Who it belongs to |
|---|---|---|
| subtotal | product-service `POST /api/products/{id}/price`, re-priced server-side | shop (less commission) |
| deliveryFee | store zone terms (`/api/delivery-zones/terms/{storeId}`), else the flat store fee | carrier or own-fleet rider (less 10% cut) |
| expressSurcharge | `delivery.orders.express-surcharge` 2.00, EXPRESS only | platform (lands in the residue) |
| giftWrapFee | `GiftWrapPolicy` 3.00 | shop, in full |
| discount | promo code (PERCENT_OFF / AMOUNT_OFF / FREE_DELIVERY), 100% platform-funded | platform bears it |
| waivers | offers: CUSTOMER (fee not charged), MERCHANT (no commission), CARRIER (no cut, decided at READY) | platform bears it; budget in `orders.platform_revenue_ledger` |

- **Multi-shop checkout** (`POST /api/orders/checkout`, Idempotency-Key required): one order per shop,
  same `checkoutId`, each priced alone. `PromoSplit` spreads the code by largest remainder. One
  `promo_redemptions` row holds the **whole** discount, on the first order.
- **Errands** (BUTLER_BUY / BUTLER_SEND): `total = goodsCost + 3.50`. No promo, no waiver, cash, no provider.
- **Service orders** (SERVICE): one line, cash, STANDARD. A PICKUP has fee 0 and is paid at the shop's
  counter; `POST /api/orders/{id}/collected` makes it DELIVERED.
- **Gifts**: never cash. With the shipped `accepted-methods: CASH`, `gift-terms` offers no method, so no
  gift can be placed.
- **Payment** (OM `PaymentService`, DEV provider): CASH `DUE → COLLECTED` at delivery; CARD/WALLET
  `AUTHORIZED → CAPTURED` at delivery. Cancel sets `FAILED`. `REFUNDED` exists and is never set.

### 1.2 Events (transactional outbox → topic `delivery.events`, routing key = event type)

`messageId` is the outbox row id. The relay backs off per row (8 tries), so events of one order can publish
out of order. There are no publisher confirms.

| Event | When | Consumed by accounting? |
|---|---|---|
| `order.placed` | each order placed, each order of a checkout | no |
| `order.status_changed` | ACCEPTED, PREPARING, READY, PICKED_UP | no |
| `order.rider_assigned` | claim | no |
| `order.cancelled` | cancel, in PLACED/ACCEPTED/PREPARING/READY | **no** |
| `order.delivered` | rider deliver, or shop marks a pickup collected | **yes: settles** |
| `order.tipped` | (not published by OM) | yes: refused (online tips) |

`OrderSnapshot` fields: `orderId, kind, customerId, merchantId, riderId, deliveryProviderId,
deliveryProviderAccount (null = own fleet), status, totalAmount, subtotal, deliveryFee (base cost, even when
waived), deliveryTier, expressSurcharge, gift, giftWrapFee, deliveryFeeWaived, merchantFeeWaived,
carrierFeeWaived, discountAmount, promoCode, storeId, storeName, checkoutId, paymentMethod, paymentStatus,
deliveryAddress, pickup/dropoff lat/lng, cancelReason, fulfilment, serviceCategory, estimatedReadyAt, items[],
placedAt, occurredAt`.

There is **no** refund, payment-captured or post-delivery-cancel event.

### 1.3 Settlement (`SettlementService.settle`, on `order.delivered`)

It settles only when `paymentStatus` is COLLECTED or CAPTURED; otherwise the event is dropped for good. It is
idempotent on `existsByOrderId` plus `UNIQUE(order_id, leg)`. The listener catches every exception and acks,
so a failed settlement is not retried.

| Leg (`accounting.transactions`) | Dir | Amount | Counterparty |
|---|---|---|---|
| `CASH_COLLECTED` | DEBIT | total (cash; omitted when total = 0) | holder: RIDER, or MERCHANT for a pickup |
| `CUSTOMER_DEBIT` | DEBIT | total (card/wallet) | none |
| `MERCHANT_CREDIT` | CREDIT | `goods − round(12.5% × goods)`; the whole goods if merchant waived | MERCHANT |
| `GIFT_WRAP_CREDIT` | CREDIT | wrap fee | MERCHANT |
| `PROVIDER_CREDIT` | CREDIT | `fee − round(10% × fee)`, or fee if carrier waived (external fleet) | CARRIER |
| `RIDER_CREDIT` | CREDIT | same, own fleet with a named rider; errand: `total − 12.5% × (total − goods)` | RIDER |
| `PLATFORM_COMMISSION` | CREDIT | residue `= total − all credits`, when > 0 (includes express) | PLATFORM |
| `PLATFORM_SUBSIDY` | DEBIT | `−residue`, when < 0 | PLATFORM |
| `CASH_REMITTANCE` | CREDIT | what a holder paid the platform; `order_id` = the remittance id | none |
| `CUSTOMER_REFUND` | CREDIT | BANK-mode saga only (unused) | none |

Status: `SETTLED_IN_CASH` for every settlement leg in LEDGER_ONLY. `CASH_REMITTANCE` is written `PENDING` and
waits for a bank.

### 1.4 Cash custody (`accounting.cash_float`)

| Row | Holder | Written by | Clears |
|---|---|---|---|
| COLLECTED | RIDER (`carrier_ref` = company or null) or MERCHANT (pickup) | settlement | — |
| TRANSFERRED | RIDER | carrier hand-over `POST /api/accounting/carrier/cash/riders/{r}/handovers`, or a pay run's PAYROLL_DEDUCTION | the rider's rows for that company |
| COLLECTED custody copy (`handover_id`) | PROVIDER | same transaction as TRANSFERRED | — |
| REMITTED | RIDER / PROVIDER / MERCHANT | Back Office `POST /api/accounting/float/{ref}/remit` | everything outstanding of that holder (kind) |
| RETAINED | MERCHANT | same, the shop's own share of its till | (paired with REMITTED) |

Locks: `outstandingFor` / `lockHeldForCarrier` take PESSIMISTIC_WRITE. `request_key` is unique.

### 1.5 Rider money (`accounting.rider_ledger`, `rider_cash_out`)

Row types: JOB_EARNING (payable PLATFORM or CARRIER), REIMBURSEMENT (errand goods), TIP (IN_HAND or
PLATFORM), CASHOUT_HELD (−), CASHOUT_RELEASED (+), CASHOUT_PAID (0), ADJUSTMENT.

- `balance = Σ amount WHERE payable_by = PLATFORM`
- `available = balance − outstanding COLLECTED held as RIDER` (all companies' cash included)
- Cash-out: request (hold, one open per rider) → pay (MANUAL provider, operator reference) | reject
  (release).

### 1.6 Points (`accounting.points_ledger`, `points_redemption`), the only payout path in code

- Earning: merchant 5/USD of subtotal, carrier or own rider 10/USD of fee, customer 5/USD of total.
  One point is worth 0.01 USD.
- Redemption: request (HELD −points, one open per owner) → approve → paid (0-point row) | reject/cancel
  (RELEASED +points).

### 1.7 Carrier payroll (`accounting.carrier_pay_*`)

- Policy terms: per delivery, hourly, overtime, late/absence deductions; cycle MONTHLY or SEMI_MONTHLY.
- A run covers one period in Asia/Beirut.
- Payslip: `net = gross − deductions − cash netted`. Cash is netted all-or-nothing, and only cash collected
  before the period end.
- Approve: one hand-over per netted rider (key `payroll-…`). Then mark paid, or pay all against the
  confirmed total.

### 1.8 Transfers (transfer-service `money_transfers`, `split_plans`)

- One intent per order: `amount_usd = split_usd + split_lbp_in_usd` (CHECK), plus `rate_used`.
- The amount is taken from the client, and a re-post replaces the row.
- Nothing publishes or consumes transfer events.

## 2. Reports and screens

| Surface | Endpoint | Role |
|---|---|---|
| Reconciliation landing | `/api/accounting/summary`, `/unsettled`, `/transactions`, `/orders/{id}` | BACKOFFICE |
| Cash on hand, carrier cash | `/api/accounting/float`, `/float/carriers`, `/float/{ref}/remit` | BACKOFFICE |
| Statements | `/api/accounting/statements/counterparties`, `/{kind}/{ref}`, `/{kind}/{ref}/send` | BACKOFFICE |
| Own statement | `/api/accounting/statements/mine` (kind from role, ref from token) | MERCHANT, DELIVERY, CARRIER |
| Carrier cash | `/api/accounting/carrier/cash`, `/riders/{r}`, `/handovers`, `/owed` | CARRIER (company from token) |
| Payroll | `/api/accounting/carrier/payroll/*` | CARRIER |
| Rider | `/api/rider/earnings`, `/balance`, `/cash-outs` (+ `/queue`, `/pay`, `/reject` BACKOFFICE) | DELIVERY |
| Points | `/api/points/*` | owners; queue and decisions BACKOFFICE |
| Dashboards | `/api/orders/merchant/summary|daily`, `/carrier/earnings|summary|daily`, `/api/orders/daily|stats` | per role |

Statement lines:
- **Merchant:** goods sold, commission (only when provable), gift wrapping, share kept at the counter,
  commission to pay from the counter.
- **Carrier:** delivery fees, cash handed over by riders, cash paid to the platform.
- **Rider:** earnings, tips, reimbursed, adjustments, cash paid out, cash collected, cash banked, cash handed
  to company.
- **Platform:** commission earned, subsidies paid.

Every statement is balance-checked (`Statement.of`).

## 3. Invariants

| # | Invariant | Checked |
|---|---|---|
| I1 | Per order, Σ DEBIT = Σ CREDIT (remittances excluded) | SQL, unit |
| I2 | The collection leg equals `orders.total_amount`; no collection leg when total = 0 | SQL |
| I3 | MERCHANT_CREDIT = subtotal − round(12.5% × subtotal) (whole subtotal when waived); GIFT_WRAP_CREDIT = wrap | SQL, unit |
| I4 | PROVIDER/RIDER_CREDIT = fee − round(10% × fee) (whole fee when carrier waived) | SQL, unit |
| I5 | COMMISSION − SUBSIDY = total − Σ payee credits | SQL |
| I6 | total = subtotal + charged fee + express − discount + wrap | SQL (OM CHECK) |
| I7 | Per checkout: Σ order discounts = the code's discount; Σ order totals = checkout total | e2e |
| I8 | Every DELIVERED order paid COLLECTED/CAPTURED has legs; no non-delivered order has legs | SQL |
| I9 | ≤ 1 COLLECTED per (order, holder kind); door COLLECTED = total | SQL |
| I10 | TRANSFERRED = Σ rider rows it cleared = Σ custody copies it created | SQL |
| I11 | REMITTED (rider/provider) = Σ rows it cleared; shop: REMITTED + RETAINED = Σ cleared | SQL |
| I12 | Every `cleared_by` points at a REMITTED / TRANSFERRED / RETAINED row | SQL |
| I13 | Rider JOB_EARNING = RIDER_CREDIT (own fleet) or PROVIDER_CREDIT (company fleet) | SQL |
| I14 | Rider available = Σ PLATFORM rows − cash they owe the **platform** | unit |
| I15 | A redemption / cash-out has one hold and at most one of {release, paid}; balances never go negative | SQL, Postgres test |
| I16 | Each statement's lines sum to its net, and the net equals an independent SQL over the ledger | e2e |
| I17 | CASH_REMITTANCE legs = REMITTED float rows (count, sum), and settle to a terminal status | SQL |
| I18 | Transfer intent amount = order total; USD + lira-in-USD = amount | code review |
| I19 | Promo redemptions and waiver budget count only orders that were not cancelled | SQL |
| I20 | One calendar (Asia/Beirut) for every day and period boundary | e2e, unit |

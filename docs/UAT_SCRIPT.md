# User acceptance test script

For a human, in a browser and on a phone. Everything in this document is the part the automated
suites cannot reach — the 234 smoke checks prove the backend behaves, and the widget tests prove the
screens render, but **nobody has yet driven this platform through a browser end to end.** That is
the gap this script closes, and it is the last thing standing between the platform and a go/no-go.

Expect it to take about 90 minutes for one tester, or 45 with two people running the merchant and
customer halves in parallel.

## Before you start

```bash
cd infra && docker compose up -d --build
```

Wait until every container reports healthy — 15 JVMs starting together on one machine takes several
minutes, and services whose dependencies are not ready yet will exit and need a second
`docker compose up -d`.

| What | Where | Sign in as |
| --- | --- | --- |
| Customer app | http://127.0.0.1:5012 | `customer` / `customer` |
| Merchant portal | http://127.0.0.1:5010 | `merchant` / `merchant` |
| Backoffice | http://127.0.0.1:5011 | `backoffice` / `backoffice` |
| Rider | same app as customer | `rider` / `rider` |
| Test inbox (email + SMS) | http://127.0.0.1:8025 | — |
| Dev bank | http://127.0.0.1:8114 | header `X-Bank-Api-Key: simulator-dev-key` |

**Use `127.0.0.1`, not `localhost`.** On Docker Desktop with WSL2, `localhost` resolves to `::1`
first and the connection is reset — this has cost time twice already.

Record the result of every step. A step that "sort of worked" is a fail; write down what you saw.

---

## 1. Sign-in and role separation

| # | Do this | Expect |
| --- | --- | --- |
| 1.1 | Open the customer app, sign in as `customer` | Redirected to Keycloak, back to the app, catalog visible |
| 1.2 | Sign out, sign in as `rider` | The **rider job board**, not the customer catalog — one app, branched on role |
| 1.3 | Open the Backoffice, sign in as `customer` | Refused with "does not have Backoffice access", not a blank screen or a crash |
| 1.4 | Sign in to the Backoffice as `backoffice` | Orders dashboard |
| 1.5 | In the merchant portal, sign in as `merchant` | Product list |

## 2. Catalog

| # | Do this | Expect |
| --- | --- | --- |
| 2.1 | Merchant: create a product without an image, try to publish | Refused — a product needs an image first |
| 2.2 | Merchant: upload an image, publish | Published; the image appears |
| 2.3 | Customer: browse the catalog | The new product is visible with its image |
| 2.4 | Backoffice: open Catalog | The same product, read-only |
| 2.5 | Backoffice: add a category; merchant: create a product in it | The new category is selectable in the merchant portal |

## 3. The order lifecycle

Keep the customer app and the merchant portal side by side.

| # | Do this | Expect |
| --- | --- | --- |
| 3.1 | Customer: add to basket, check out | Order placed, visible under My Orders as PLACED |
| 3.2 | Customer: try adding a second merchant's product to the basket | Refused — one merchant per basket |
| 3.3 | Merchant: refresh the order queue | The order appears |
| 3.4 | Merchant: Accept → Start preparing → Mark ready | Status advances; the customer's screen follows |
| 3.5 | Customer: try to cancel after it was accepted | The cancel button is gone — buttons come from the server's `availableActions` |
| 3.6 | Rider: open the job board | The order is claimable |
| 3.7 | Rider: Claim, then Picked up | It leaves the board for other riders |
| 3.8 | Customer: watch the live map | The rider's position appears and updates |
| 3.9 | Rider: Delivered | Both sides show DELIVERED |

## 4. Notifications

| # | Do this | Expect |
| --- | --- | --- |
| 4.1 | Customer: open the Alerts tab | In-app messages for the order's milestones |
| 4.2 | Check the unread badge before opening | A count, clearing when the messages are read |
| 4.3 | Open http://127.0.0.1:8025 | A confirmation email to `customer@dev.local` **and** a work-item email to `merchant@dev.local` — different wording for different audiences |
| 4.4 | Look for mail addressed to `sms-test-inbox@dev.local` | The SMS, with the intended phone number in the subject |
| 4.5 | Backoffice: Finance is not where notifications live — skip | — |

## 5. Settlement and reconciliation

| # | Do this | Expect |
| --- | --- | --- |
| 5.1 | Backoffice: open **Finance** | "At risk" reads $0.00 if everything settled |
| 5.2 | Filter to Posted | Three legs for the delivered order: customer charged, merchant payout, commission |
| 5.3 | Check the arithmetic | Merchant payout + commission = the order total, exactly |
| 5.4 | Click the receipt icon on any leg | The sync log shows what was sent to the bank and what came back |
| 5.5 | `curl -H "X-Bank-Api-Key: simulator-dev-key" http://127.0.0.1:8114/api/core-banking/accounts` | Balances moved: customer down, merchant and platform up |

## 6. Connector settings

| # | Do this | Expect |
| --- | --- | --- |
| 6.1 | Backoffice: open **Settings** | Four connectors, each showing its provider and a masked credential |
| 6.2 | Confirm no screen anywhere shows a real credential | Only `********` and a Vault path |
| 6.3 | Change SMS to Twilio | A confirmation dialog warning about real recipients and cost |
| 6.4 | Confirm it | The card updates to Twilio |
| 6.5 | Open History | Your change, naming you, with the old and new values |
| 6.6 | Change SMS back to the dev test inbox | Confirmed and recorded |
| 6.7 | Try the Email connector's dropdown | Disabled — SMTP is the only provider |

## 7. Failure behaviour

The point of this section is that the platform degrades rather than breaks. Do it last.

| # | Do this | Expect |
| --- | --- | --- |
| 7.1 | `curl -X POST http://127.0.0.1:8114/test/faults -H 'Content-Type: application/json' -d '{"mode":"UNAVAILABLE","latencyMs":0,"callCount":3}'` | The dev bank is now down |
| 7.2 | Place and deliver another order | **Checkout and delivery are unaffected** — the bank is never in the order path |
| 7.3 | Backoffice → Finance, watch for a minute | The legs settle anyway once the injected outage expires |
| 7.4 | `docker compose stop mailpit`, then place an order | The order succeeds; email fails but nothing else does |
| 7.5 | `docker compose start mailpit` | — |
| 7.6 | `docker compose stop sms-connector`, place an order, restart it | In-app, email and push still arrive — one channel down does not stop the others |

## 8. The things most likely to be wrong

Not features — the parts no automated test in this repo has ever exercised.

| # | Check | Why it is here |
| --- | --- | --- |
| 8.1 | The login redirect works from a **phone on the same Wi-Fi** | Needs `infra/set-host-address.ps1`; the LAN IP has broken sign-in twice |
| 8.2 | The live map updates on a real device, not just in Chrome | Nothing has tested the mobile build's tracking loop |
| 8.3 | Tapping a push notification opens the right order | The deep link is built by the push worker and has never been tapped |
| 8.4 | The in-app list updates **without** pulling to refresh | Proves the 15-second poll, the only live path in the mobile client |
| 8.5 | Every screen at a narrow window width | A DataTable overflow was already found this way in a widget test |
| 8.6 | Sign out and back in on all three clients | Token refresh and PKCE round-trip |

---

## Known limitations to confirm rather than raise as defects

These are deliberate and documented in the README. A tester should confirm the behaviour matches
rather than filing them.

- **Push notifications are logged, not delivered.** There is no Firebase project; the push connector
  runs on `DEV_LOG`. Check `docker compose logs push-connector` instead of a device.
- **SMS goes to an email inbox.** Deliberate until the MontyMobile/Twilio decision is made.
- **The real bank refuses everything.** Switching Core Banking to REAL fails every posting on
  purpose — the bank's contract does not exist yet.
- **In-app notifications are up to 15 seconds late.** The client polls; the WebSocket is live
  server-side but the mobile app uses the REST fallback.

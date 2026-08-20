# SMS provider cutover

Phase 6 of the roadmap: go live with a real SMS vendor. Everything the cutover *mechanism* needs is
built and verified (27 checks in `infra/smoke-test-phase6.sh`). What is not decided is the vendor,
and that is not an engineering decision.

---

## The decision nobody here can make

**Section 12, open decision #6 is still open: MontyMobile or Twilio.** Both clients are built,
deployed and switchable at runtime, so the platform is not waiting on code. It is waiting on
commercial terms, deliverability in the target market, and local carrier support — none of which
can be established from this repository.

What can be said from here, and it is deliberately limited:

| | MontyMobile | Twilio |
| --- | --- | --- |
| Client implemented | Yes | Yes |
| Contract confidence | **Low.** Written against the published v1 SendSMS shape; the base URL, send path and field names are all configurable precisely because that spec must be confirmed against the account's own documentation | **Higher.** Programmable Messaging is stable and widely documented; the error codes mapped in `TwilioSmsClient` are from its published list |
| Error classification | Guessed status strings (`INVALID_MOBILE_NUMBER`, `BLACKLISTED`, …) — **must be checked against real responses** | Numeric codes 21211 / 21408 / 21610 / 21614, from the documented set |
| Idempotency | `clientMessageId` sent as a client reference; whether the vendor honours it as a dedupe key is **unconfirmed** | No general idempotency header; retry safety rests on our own budget and the breaker |
| What would change the answer | Local carrier relationships and price per segment in the target market | Price, and whether its regional deliverability is acceptable |

**The honest recommendation is to pilot, not to pick.** The canary ramp exists so both can carry
real traffic at 5% and be compared on the delivery rates the platform now measures, rather than
choosing on a rate card and finding out afterwards. Run each for a week at 5% and let the numbers
decide.

Whichever is chosen, **the error classification must be validated against real responses before
going past 5%.** A vendor failure misclassified as retryable turns one bad number into a retry
storm; misclassified as permanent it drops messages that would have gone through.

---

## Before you start

- [ ] Vendor chosen, contract signed, account provisioned
- [ ] Credentials in Vault at `secret/sms-connector` — `montymobile.api-key`, or
      `twilio.account-sid` / `twilio.auth-token` / `twilio.from`
- [ ] Sender ID or originating number registered with the vendor and approved for the target market
- [ ] A real handset available for the smoke check. Not a colleague's description of one.
- [ ] Someone who can approve a rollback available for the whole window

Verify the credentials reached the connector without sending anything:

```bash
curl -s http://sms-connector:8112/api/connector/status | jq
```

`availableProviders` must list the vendor. It will, whether or not credentials exist — the client
ships either way — so this confirms the deployment, not the credentials.

---

## Staging first

**1. Point the primary at the vendor in staging.** Backoffice → Settings → SMS → choose the vendor.
Confirm the dialog. This is a full switch in staging, not a ramp — staging has no real customers, so
there is nothing to protect and a partial rollout would only slow down finding problems.

**2. Send one real message to a real handset.** Place an order in staging with your own number on
the account. It must arrive, and the notification log must say `SENT` with the vendor named:

```bash
curl -s "$GW/api/notification-log/orders/<orderId>" -H "Authorization: Bearer $TOKEN" | jq '.[]|select(.channel=="SMS")'
```

**3. Force each failure mode and check the classification.** This is the step most likely to be
skipped and most likely to matter:

- an invalid number (`+15550000000`) → must be **permanent**, must not retry
- a number outside the enabled region → must be **permanent**
- credentials temporarily wrong → must fail loudly and permanently, not retry forever

Watch `docker compose logs sms-connector` and confirm the DLQ receives what it should:

```bash
curl -s -u delivery:delivery http://rabbitmq:15672/api/queues/%2F/notification.dlq | jq '.messages'
```

**4. Leave it for a day and read the rates.** Backoffice → Settings → SMS, or:

```bash
curl -s "$GW/api/notification-rates?windowHours=24" -H "Authorization: Bearer $TOKEN" | jq '.[]|select(.channel=="SMS")'
```

Do not proceed on a 100% success rate over five messages. The denominator is on screen for a reason.

---

## Production, as a ramp

Production is never a switch. The primary stays on `DEV_PASSTHROUGH` and the vendor takes a slice.

**5. Start at 5%.** Backoffice → Settings → SMS → "Try <vendor> at 5%".

Roughly one message in twenty goes to the vendor; the rest keep going to the test inbox. Confirm the
ramp reached the connector:

```bash
curl -s http://sms-connector:8112/api/connector/status | jq '{activeProvider, canaryProvider, canaryPercentage}'
```

**6. Hold for 24 hours.** Then compare the two providers on the same channel — this is what the
per-provider breakdown is for, and why an averaged channel rate would be useless here.

**Proceed only if all of these hold:**

| Gate | Threshold |
| --- | --- |
| Vendor success rate | ≥ 95%, over at least 200 completed sends |
| Vendor vs test-inbox success rate | within 2 percentage points |
| `notification.dlq` depth | not growing |
| Connector circuit state | `CLOSED` throughout |
| Average time to send | not more than 3× the test inbox |

**7. Ramp 5% → 25% → 50%, holding 24 hours at each step**, re-checking the same gates. Each step is
one click and is audited.

**8. Complete at 100%.** At 100% every message goes to the vendor. The primary is still nominally
`DEV_PASSTHROUGH`, which is deliberate: it makes rollback a single click rather than a provider
switch.

**9. Retire the fallback — not before a week at 100%.** Set the primary to the vendor and clear the
ramp. Only now is the test-inbox path out of production.

---

## Rollback

**One action, no confirmation dialog, at any point:** Backoffice → Settings → SMS → **Stop ramp**.

Or without a browser:

```bash
curl -X PUT "$GW/api/settings/connectors/SMS" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"provider":"DEV_PASSTHROUGH","config":{"senderId":"Delivery"}}'
```

It takes effect within about a second — the connector reloads on a bus event, with a TTL refresh
behind it as the safety net. No deploy, no restart.

**Roll back on any of:** success rate below 90% over 50+ sends, the circuit breaker opening, the DLQ
growing, or a customer report of a duplicate message. The last one is the most serious: it would
mean the idempotency assumption is wrong for this vendor, and the ramp should stop at once rather
than being reduced.

**Messages already sent are not recalled by a rollback.** Anything in flight at the vendor stays
there. Rollback stops new traffic; it does not undo.

---

## What this cannot tell you

- **Deliverability is not the same as acceptance — and the report now shows both.** `successRate`
  is what the vendor accepted; `deliveryRate` is what a carrier confirmed arrived. Judge a pilot on
  the second. **Before you can, the vendor's delivery-report callback has to be pointed at
  `https://<host>/webhooks/dlr/TWILIO` or `/webhooks/dlr/MONTYMOBILE` and its signing secret loaded
  into Vault** — without that, `deliveryRate` stays null and reads "not measured", which is the
  honest answer rather than a bad one. Confirm receipts are landing (`awaitingReceipt` stops
  climbing) before reading anything into a delivery number, and note that MontyMobile's callback
  shape and status vocabulary are as unconfirmed as its send contract: validate both against real
  responses during the 5% pilot, exactly as you would the error classification.
- **Cost is not measured.** The SMS worker records a segment count per message in the command
  metadata, but nothing aggregates it into spend. During a ramp, watch the vendor's own billing
  dashboard.

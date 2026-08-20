# Phase 5 load test

Run 2026-08-09 against the full compose stack on one laptop (Docker Desktop / WSL2, 24 containers
including Postgres, Redis, RabbitMQ, Keycloak and MinIO on the same machine as the services).

**Read the absolute numbers as a floor, not a capacity plan.** Every service, the database and the
broker are contending for the same cores here. What the run establishes is the *shape* of each path
— where the bottleneck is and whether the asynchronous half keeps up — which does transfer.

Scripts are in `infra/load-test/`.

---

## 1. Rider position writes

Section 10 names this the highest-write path in the platform: an INSERT into `tracking_events` plus
a Redis SET, once per active rider every few seconds.

| Run | Target | Pacing | Result |
| --- | --- | --- | --- |
| A | Gateway | flat out, 250 VUs | **20.25 accepted/s**, 93,818 × 429, 0 × 5xx |
| B | Order Tracking direct | flat out, 250 VUs | **322 accepted/s**, 0 failures, p95 1.30 s |
| C | Order Tracking direct | 10 s interval, 250 riders | 10.6/s, 0 failures, **p95 105 ms**, max 223 ms |

### Run A is the rate limiter, not the write path

20.25/s is exactly the configured `replenishRate: 20`. Zero 5xx. The Gateway shed everything above
the limit and never passed load downstream.

This is the limiter working, but it is worth being precise about *why* it triggered: all 250 virtual
riders authenticate as the same dev user, and the limiter keys on the authenticated user, so they
share one bucket. Real riders are distinct users with a bucket each, so this is not a production
ceiling — **it is a measurement of what one client can extract before being throttled**, which is
the useful reading of it. A looping or compromised app gets 20 rps and no more.

It does mean any future load test through the Gateway must provision distinct users per VU, or it
will only ever measure the limiter again.

### Run B is the real capacity number

322 pings/s sustained with no failures and no errors. At the configured ping interval of 10 s that
is **roughly 3,200 concurrent riders** on this hardware before the write path becomes the
bottleneck — comfortably beyond anything a first release needs.

p95 of 1.30 s at that load is queueing, not per-request cost: 250 VUs sending as fast as they can is
about 2,500× the per-rider rate of a real fleet. It is the right number for "where does it saturate"
and the wrong one for "what does a rider experience".

### Run C is what a rider experiences

250 riders at the real 10 s interval: **p95 105 ms, max 223 ms, zero failures.** That is the number
to hold the service to, and there is roughly a 30× headroom margin between it and run B.

### Partitioning held

Runs B and C wrote through the daily-partitioned table added in `V11` with three indexes declared on
the parent, including the GIST index on the generated geography column. No degradation was
observable against the pre-partitioning behaviour, and partition routing did not appear as a cost.

---

## 2. Notification fan-out

One order placement fans out to five notifications across four channels, each of which is a template
render, a bus publish, a worker, a connector call and a receipt back.

**600 orders at a sustained 10/s**, arrival-rate driven so the load does not slow itself down when
the system does.

Synchronous half — what the customer waits for at checkout:

```
orders placed        : 600   (10.00/s, 0 failures)
order_place_latency  : avg 201ms  med 157ms  p90 356ms  p95 502ms  max 1.69s
```

Asynchronous half — measured afterwards from `notification_log`, because k6 stops at the HTTP
response and the interesting work happens after it:

```
notifications  : 3000
sent           : 3000
still pending  : 0
failed         : 0
created -> sent: avg 0.64s   p95 1.61s   max 2.20s
```

**The pipeline drained faster than orders arrived.** 50 notifications/s sustained across all four
channels, everything reaching a terminal state, nothing left pending, nothing dead-lettered. Queue
depths after the run were zero on every dispatch queue, the order-events queue and the receipts
queue.

That is the result the per-channel queue design was for: no channel backed up behind another, and
the outbox → bus → manager → worker → connector → receipt chain stayed ahead of a 10/s order rate
without any of it being tuned for the test.

---

## What this did not test

- **Sustained load over hours.** Everything here runs for 60–100 seconds. Connection-pool
  exhaustion, memory growth and partition-boundary rollover are all things that only appear over a
  longer run.
- **A slow provider under load.** The connectors' breakers were exercised functionally in the Phase
  3 and 4 smoke tests, but never while the pipeline was saturated — which is exactly when a breaker
  opening matters most and when its behaviour is hardest to predict.
- **Concurrent settlement.** The accounting saga was not part of either scenario; the fan-out run
  placed orders but never delivered them, so no bank postings were generated.
- **Multiple instances.** Everything ran single-instance. The stateless services are designed to
  scale as competing consumers, but that is asserted, not measured — and App Notification's
  in-memory STOMP broker is known not to survive it (see the README's deviations).

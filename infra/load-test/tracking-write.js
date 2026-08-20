// Load test: the rider position write path.
//
//   cd infra && docker run --rm --network delivery -v "$PWD/load-test:/scripts:ro" \
//     -e ORDER_ID=<uuid> -e RIDER_TOKEN=<jwt> grafana/k6:0.53.0 run /scripts/tracking-write.js
//
// Section 10 singles this out as the highest-write path in the platform: every active rider pings
// every few seconds, and every ping is an INSERT into tracking_events plus a Redis SET. The
// question this answers is not "how fast is it" but "at what rider count does it stop keeping up",
// because that number is the platform's capacity ceiling for concurrent deliveries.
//
// Ramped rather than flat. A flat load says whether one number works; a ramp shows where the knee
// is, which is the thing worth knowing before launch.

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const pingLatency = new Trend('ping_latency', true);
const pingFailures = new Rate('ping_failures');
// Broken out by status, because "95% failed" is useless on its own: throttled at the edge and
// falling over downstream are opposite problems with opposite fixes.
const accepted = new Counter('status_202_accepted');
const throttled = new Counter('status_429_throttled');
const serverErrors = new Counter('status_5xx');
const otherStatus = new Counter('status_other');

// Two targets, and both runs are needed to say anything useful.
//
// Through the Gateway you measure the rate limiter, not the write path: every VU here shares one
// rider's token, so they share one per-user bucket and the run flatlines at replenishRate no matter
// how fast Postgres is. That run is still worth doing — it proves the limiter works and shows what
// a single compromised or looping client can extract — but it says nothing about capacity.
//
// Pointed straight at order-tracking, you measure what Section 10 actually asks about: how many
// pings a second the INSERT-plus-Redis-SET path sustains before it becomes the bottleneck.
const TARGET = __ENV.TARGET || 'http://api-gateway:8100';
const ORDER_ID = __ENV.ORDER_ID;
const TOKEN = __ENV.RIDER_TOKEN;

// 0 means flat out, which finds the ceiling. Set it to the real interval
// (delivery.tracking.rider-ping-interval-seconds, 10s) to measure what a rider actually
// experiences — an unpaced run reports the latency of a saturated queue, which is a true number
// about the wrong question.
const PING_INTERVAL_MS = Number(__ENV.PING_INTERVAL_MS || 0);

export const options = {
  scenarios: {
    riders: {
      executor: 'ramping-vus',
      // Each VU is one rider pinging on a loop, which is what a real fleet looks like — not a
      // burst of unrelated requests.
      stages: [
        { duration: '20s', target: 25 },
        { duration: '30s', target: 100 },
        { duration: '30s', target: 250 },
        { duration: '20s', target: 0 },
      ],
      gracefulRampDown: '5s',
    },
  },
  thresholds: {
    // The write is fire-and-forget from the rider's phone (202, no body), so latency matters much
    // less than not dropping pings. A dropped ping is a gap in the customer's live map.
    ping_failures: ['rate<0.01'],
    'ping_latency': ['p(95)<1000'],
  },
};

// Roughly Beirut, wandering. Real coordinates matter because the geography column is GENERATED and
// indexed — feeding it the same point every time would not exercise the GIST index honestly.
function nextPosition(iteration) {
  const drift = (iteration % 200) * 0.0001;
  return {
    lat: 33.8886 + drift,
    lng: 35.4955 + drift,
    accuracyM: 5 + (iteration % 10),
  };
}

export default function () {
  const body = JSON.stringify(nextPosition(__ITER));

  const res = http.post(`${TARGET}/api/tracking/orders/${ORDER_ID}/ping`, body, {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${TOKEN}`,
    },
    tags: { name: 'ping' },
  });

  pingLatency.add(res.timings.duration);

  if (res.status === 202) {
    accepted.add(1);
  } else if (res.status === 429) {
    throttled.add(1);
  } else if (res.status >= 500) {
    serverErrors.add(1);
  } else {
    otherStatus.add(1);
  }

  // 202 is the only success. A 429 counts as a failure here on purpose: the Gateway shedding rider
  // pings is a capacity problem even though the Gateway is behaving exactly as configured.
  const ok = check(res, { 'accepted (202)': (r) => r.status === 202 });
  pingFailures.add(!ok);

  if (PING_INTERVAL_MS > 0) {
    sleep(PING_INTERVAL_MS / 1000);
  }
}

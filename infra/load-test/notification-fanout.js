// Load test: the full notification fan-out.
//
//   cd infra && docker run --rm --network delivery -v "$PWD/load-test:/scripts:ro" \
//     -e CUSTOMER_TOKEN=<jwt> -e MERCHANT_TOKEN=<jwt> -e PRODUCT_ID=<uuid> \
//     grafana/k6:0.53.0 run /scripts/notification-fanout.js
//
// The other path Section 10 names. One order placement fans out to five notifications across four
// channels, each of which is a template render, a bus publish, a worker, a connector and a provider
// call — so the interesting number is not the HTTP latency of placing an order, it is whether the
// asynchronous tail keeps up with the rate of orders.
//
// This drives the SYNCHRONOUS half and records how fast orders can be accepted. The asynchronous
// half is measured afterwards by run-load-test.sh, which reads the notification log and reports how
// long the fan-out actually took to drain — the number that matters, and one k6 cannot see because
// it happens after the response.

import http from 'k6/http';
import { check } from 'k6';
import { Trend, Rate, Counter } from 'k6/metrics';

const placeLatency = new Trend('order_place_latency', true);
const placeFailures = new Rate('order_place_failures');
const ordersPlaced = new Counter('orders_placed');

const GATEWAY = __ENV.GATEWAY || 'http://traefik:8100';
const CUSTOMER = __ENV.CUSTOMER_TOKEN;
const PRODUCT_ID = __ENV.PRODUCT_ID;

export const options = {
  scenarios: {
    checkout: {
      // Arrival-rate, not VUs. Orders arrive at a rate set by customers, not by how fast the
      // platform answers — a VU-based test would quietly slow its own load down as the system got
      // slower and hide the very problem it is looking for.
      executor: 'constant-arrival-rate',
      rate: 10,
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 30,
      maxVUs: 120,
    },
  },
  thresholds: {
    order_place_failures: ['rate<0.01'],
    // Checkout is the one path a customer waits on, so this threshold is real rather than nominal.
    order_place_latency: ['p(95)<1500'],
  },
};

export default function () {
  const body = JSON.stringify({
    items: [{ productId: PRODUCT_ID, qty: 1 }],
    deliveryAddress: '1 Load Test Avenue',
    contactPhone: '+15550100001',
  });

  const res = http.post(`${GATEWAY}/api/orders`, body, {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${CUSTOMER}`,
      // Tagged so the notification log can be filtered to this run afterwards.
      'X-Correlation-Id': `loadtest-${__ENV.RUN_ID}-${__VU}-${__ITER}`,
    },
    tags: { name: 'place_order' },
  });

  placeLatency.add(res.timings.duration);
  const ok = check(res, { 'created (200/201)': (r) => r.status === 200 || r.status === 201 });
  placeFailures.add(!ok);
  if (ok) {
    ordersPlaced.add(1);
  }
}

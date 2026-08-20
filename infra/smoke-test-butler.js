// Butler: the errand with no catalog behind it.
//
// Covers the negotiation (request, claim, quote, agree) and the crossing into an order, including
// the states that must NOT be reachable — a shopper who has already paid their own money is the
// thing this state machine exists to protect.
//
//   node infra/smoke-test-butler.js
const { execSync } = require('child_process');

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
const token = (user) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${user}" -d "password=${user}"`
  + ' -d "grant_type=password" -d "scope=openid"')).access_token;

const customer = token('customer');
const rider = token('rider');
const back = token('backoffice');

const call = (m, p, body, tok = customer) => {
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}" -H "Authorization: Bearer ${tok}"${data} "http://127.0.0.1:8100${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, body, tok) => split(call(m, p, body, tok));
const get = (p, tok) => JSON.parse(split(call('GET', p, null, tok)).body);
const detailOf = (body) => { try { return JSON.parse(body).detail ?? ''; } catch { return ''; } };
const pad = (s, n) => String(s).slice(0, n).padEnd(n);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + pad(label, 52) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + pad(label, 52) + (detail ?? '')); }
};

const BUY = {
  mode: 'BUY',
  what: 'A USB-C phone charger and a bottle of still water',
  sourceHint: 'Any pharmacy near Hamra',
  budgetCap: 30.00,
  dropoffAddress: '12 Test Street, Flat 4',
  contactPhone: '+9611234567',
};
const SEND = {
  mode: 'SEND',
  what: 'A4 envelope with documents, nothing fragile',
  pickupAddress: '8 Clemenceau Street, reception desk',
  recipient: 'Rana, +9617654321',
  dropoffAddress: '12 Test Street, Flat 4',
};

console.log('--- terms ---');
const terms = get('/api/butler/terms');
check('the fee is known before anyone commits', Number(terms.errandFee) > 0, `${terms.errandFee}`);

console.log('\n--- a BUY errand ---');
const created = send('POST', '/api/butler', BUY);
check('a customer can open a request', created.code === '201', `HTTP ${created.code}`);
const buy = JSON.parse(created.body);
check('it starts on the open board', buy.status === 'REQUESTED', buy.status);
check('with no price yet', buy.goodsCost === null, `goodsCost=${buy.goodsCost}`);
check('but the fee is already set by the server',
  Number(buy.deliveryFee) === Number(terms.errandFee), `${buy.deliveryFee}`);

console.log('\n--- what a shopper may not skip ---');
check('a customer cannot quote their own request',
  send('POST', `/api/butler/${buy.id}/quote`, { goodsCost: 1 }).code === '403');
// 422 and not 404: the rider can see this on their own board, so hiding it would be a lie. The
// useful answer names the missing step.
const quoteUnclaimed = send('POST', `/api/butler/${buy.id}/quote`, { goodsCost: 22.4 }, rider);
check('an unclaimed request cannot be quoted', quoteUnclaimed.code === '422',
  detailOf(quoteUnclaimed.body).slice(0, 46));
check('and cannot be approved before it is priced',
  send('POST', `/api/butler/${buy.id}/approve`, null).code === '422');

console.log('\n--- claiming ---');
// Asked for a large page deliberately. The board pages at 20, and every run of this suite leaves
// another open errand behind — so once 20 had accumulated, the errand this run just created was on
// page 2 and the check failed for a reason that had nothing to do with the board working.
const board = get('/api/butler/available?size=200', rider);
check('it appears on the rider board', board.content.some(r => r.id === buy.id),
  `${board.totalElements} open`);
check('a rider claims it', send('POST', `/api/butler/${buy.id}/claim`, null, rider).code === '200');
check('a second rider cannot claim it again',
  send('POST', `/api/butler/${buy.id}/claim`, null, rider).code === '422');
check('and it leaves the open board',
  !get('/api/butler/available', rider).content.some(r => r.id === buy.id));

console.log('\n--- quoting ---');
const quoted = send('POST', `/api/butler/${buy.id}/quote`, { goodsCost: 22.40, receiptRef: 'R-9912' }, rider);
check('the shopper reports what it cost', quoted.code === '200', `HTTP ${quoted.code}`);
const q = JSON.parse(quoted.body);
check('the total is goods plus fee',
  Number(q.payableTotal) === Number(q.goodsCost) + Number(q.deliveryFee),
  `${q.goodsCost} + ${q.deliveryFee} = ${q.payableTotal}`);
check('under the cap, so nothing is flagged', q.overBudget === false, `cap ${buy.budgetCap}`);
// A shopper who fat-fingers the number should fix it, not force the customer to decline.
const requoted = send('POST', `/api/butler/${buy.id}/quote`, { goodsCost: 34.00 }, rider);
check('a wrong number can be corrected', requoted.code === '200');
check('and going over the cap is flagged', JSON.parse(requoted.body).overBudget === true, '34.00 > 30.00');

console.log('\n--- the shopper is protected once they have paid ---');
// This is the point of the state machine: the money has left the shopper's pocket.
const cancelAfterQuote = send('POST', `/api/butler/${buy.id}/cancel`, null);
check('the customer cannot simply cancel a priced errand', cancelAfterQuote.code === '422',
  detailOf(cancelAfterQuote.body).slice(0, 48));
check('the refusal says what to do instead',
  detailOf(cancelAfterQuote.body).includes('Decline'));

console.log('\n--- crossing into an order ---');
const approved = send('POST', `/api/butler/${buy.id}/approve`, null);
check('the customer approves the price', approved.code === '200', `HTTP ${approved.code}`);
const a = JSON.parse(approved.body);
check('and an order now exists', !!a.orderId, `${a.orderId}`);
check('the request is terminal', a.status === 'APPROVED', a.status);

const order = get(`/api/orders/${a.orderId}`);
check('the order is a BUTLER_BUY', order.kind === 'BUTLER_BUY', order.kind);
check('it carries the agreed total', Number(order.totalAmount) === Number(a.payableTotal),
  `${order.totalAmount} vs ${a.payableTotal}`);
check('goods are the subtotal, the errand fee is the delivery fee',
  Number(order.subtotal) === 34.00 && Number(order.deliveryFee) === Number(terms.errandFee),
  `subtotal ${order.subtotal}, fee ${order.deliveryFee}`);
check('it has no merchant, because no shop sold it', !order.merchantId, `${order.merchantId}`);
check('it has no lines, because there was no catalog', (order.items || []).length === 0);
check('what was asked for is on the order', (order.notes || '').includes('USB-C'));
check('the rider who shopped is already on it', !!order.riderId);
// READY, not PLACED: the states in between belong to a merchant, and there is not one.
check('it starts ready for delivery', order.status === 'READY', order.status);

console.log('\n--- one errand, one order ---');
const twice = send('POST', `/api/butler/${buy.id}/approve`, null);
check('approving twice is refused', twice.code === '422', detailOf(twice.body).slice(0, 44));
check('and names the order already carrying it', detailOf(twice.body).includes(a.orderId));

console.log('\n--- a SEND errand ---');
const sendCreated = send('POST', '/api/butler', SEND);
check('a pickup can be opened', sendCreated.code === '201', `HTTP ${sendCreated.code}`);
const mv = JSON.parse(sendCreated.body);
check('a SEND without a pickup address is refused',
  send('POST', '/api/butler', { ...SEND, pickupAddress: '' }).code === '422');
check('a rider claims it', send('POST', `/api/butler/${mv.id}/claim`, null, rider).code === '200');
// Nothing was bought, so there is nothing to price and no quoting step to pass through.
check('a SEND cannot be quoted at all',
  send('POST', `/api/butler/${mv.id}/quote`, { goodsCost: 10 }, rider).code === '422');
const sendApproved = send('POST', `/api/butler/${mv.id}/approve`, null);
check('it goes straight from claimed to approved', sendApproved.code === '200',
  `HTTP ${sendApproved.code}`);
const sendOrder = get(`/api/orders/${JSON.parse(sendApproved.body).orderId}`);
check('the order is a BUTLER_SEND', sendOrder.kind === 'BUTLER_SEND', sendOrder.kind);
check('nothing was bought, so the goods total is zero', Number(sendOrder.subtotal) === 0);
check('and the customer pays the fee alone',
  Number(sendOrder.totalAmount) === Number(terms.errandFee), `${sendOrder.totalAmount}`);
check('the collection address is on the order', (sendOrder.notes || '').includes('Clemenceau'));

console.log('\n--- visibility ---');
check('a customer sees their own requests',
  get('/api/butler/mine').content.some(r => r.id === buy.id));
check('a rider sees what they claimed',
  get('/api/butler/claimed', rider).content.some(r => r.id === buy.id));
// An unclaimed request is on every rider's board, so a rider may open it — answering "not found"
// for a row they can see in a list would be a lie, and they need the detail before deciding.
const unclaimed = JSON.parse(send('POST', '/api/butler', BUY).body);
check('a rider can read an open request before claiming it',
  send('GET', `/api/butler/${unclaimed.id}`, null, rider).code === '200');
check('but is told to claim it before pricing it',
  send('POST', `/api/butler/${unclaimed.id}/quote`, { goodsCost: 5 }, rider).code === '422');
// A merchant is none of the three: not the customer, not the rider, and has no board.
const merchant = token('merchant');
const stranger = send('GET', `/api/butler/${unclaimed.id}`, null, merchant);
check('someone with no part in it gets a flat not-found', stranger.code === '404',
  `HTTP ${stranger.code}`);
check('backoffice can read any request',
  send('GET', `/api/butler/${buy.id}`, null, back).code === '200');
check('a rider cannot open a request as a customer',
  send('POST', '/api/butler', BUY, rider).code === '403');
check('a customer cannot see the rider board',
  send('GET', '/api/butler/available', null, customer).code === '403');

// ---------------------------------------------------------------- the money
//
// An errand pays entirely different parties from a basket: there is no merchant, and on a BUY most
// of what the rider receives is their own money coming back. Until this existed a delivered errand
// produced no ledger rows at all — the shopper was simply out of pocket.
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const TERMINAL_LEG = new Set(['POSTED', 'SETTLED_IN_CASH', 'FAILED', 'ABANDONED']);

/** Waits for settlement to FINISH, not merely to start — legs post in sequence. */
function settledLegs(orderId) {
  let last = [];
  for (let i = 0; i < 25; i++) {
    const legs = get(`/api/accounting/orders/${orderId}`, back);
    if (Array.isArray(legs) && legs.length > 0) {
      last = legs;
      if (legs.every(l => TERMINAL_LEG.has(l.status))) return legs;
    }
    sleep(1000);
  }
  return last;
}

function deliver(orderId) {
  for (const step of ['pick-up', 'deliver']) send('POST', `/api/orders/${orderId}/${step}`, null, rider);
}

const amountOf = (legs, leg) => {
  const found = legs.find(l => l.leg === leg);
  return found ? Number(found.amount) : null;
};

console.log('\n--- an errand pays the rider, not a merchant ---');
deliver(a.orderId);
const buyLegs = settledLegs(a.orderId);
check('a delivered errand settles at all', buyLegs.length > 0, `${buyLegs.length} legs`);
check('nobody is credited as a merchant', !buyLegs.some(l => l.leg === 'MERCHANT_CREDIT'));
// Errands are cash, so the collection is an obligation against the rider rather than a bank
// debit against the customer — who handed over notes and whose account never moved.
check('the customer hands over what they agreed',
  amountOf(buyLegs, 'CASH_COLLECTED') === 37.50, `${amountOf(buyLegs, 'CASH_COLLECTED')}`);
check('and no bank debit is invented for them',
  !buyLegs.some(l => l.leg === 'CUSTOMER_DEBIT'));
// Goods 34.00 straight back, plus 3.50 fee less 12.5% of the FEE (0.44) = 37.06.
check('the rider gets the goods back in full plus their share of the fee',
  amountOf(buyLegs, 'RIDER_CREDIT') === 37.06, `${amountOf(buyLegs, 'RIDER_CREDIT')}`);
check('commission is taken from the fee, not from the goods',
  amountOf(buyLegs, 'PLATFORM_COMMISSION') === 0.44,
  `${amountOf(buyLegs, 'PLATFORM_COMMISSION')} — 12.5% of 3.50, not of 37.50`);
check('the legs sum to exactly what the customer paid',
  amountOf(buyLegs, 'RIDER_CREDIT') + amountOf(buyLegs, 'PLATFORM_COMMISSION')
    === amountOf(buyLegs, 'CASH_COLLECTED'));
// POSTED, not merely present. A leg that exists is not a leg that paid anybody.
// Settled, not POSTED: the cash leg never goes to a bank and never will.
check('and every leg actually settled',
  buyLegs.every(l => ['POSTED', 'SETTLED_IN_CASH'].includes(l.status)),
  buyLegs.map(l => `${l.leg}=${l.status}`).join(' '));

console.log('\n--- a pickup bought nothing, so it is a fee split ---');
const sendOrderId = JSON.parse(sendApproved.body).orderId;
deliver(sendOrderId);
const sendLegs = settledLegs(sendOrderId);
check('the customer hands over the fee alone',
  amountOf(sendLegs, 'CASH_COLLECTED') === 3.50, `${amountOf(sendLegs, 'CASH_COLLECTED')}`);
check('the rider keeps the fee less commission',
  amountOf(sendLegs, 'RIDER_CREDIT') === 3.06, `${amountOf(sendLegs, 'RIDER_CREDIT')}`);
check('there is nothing to reimburse', !sendLegs.some(l => l.leg === 'MERCHANT_CREDIT'));
check('every leg settled', sendLegs.every(l => ['POSTED', 'SETTLED_IN_CASH'].includes(l.status)),
  sendLegs.map(l => `${l.leg}=${l.status}`).join(' '));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);

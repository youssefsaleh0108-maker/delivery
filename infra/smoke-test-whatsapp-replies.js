// Talking back: outbound replies, and the simulator that stands in for WhatsApp.
//
//   node infra/smoke-test-whatsapp-replies.js
//
// Getting a real WhatsApp number takes weeks of business verification. Until then the alternative to
// a simulator is a feature nobody can try — the same reasoning that produced the Core Banking
// simulator in Phase 4.
//
// The check that matters most here is the last one: the simulator must NOT be a way around the
// signature on the public webhook. It signs its envelope with the real app secret and goes through
// the real endpoint, so a wrong secret breaks the simulator rather than opening a hole.
const { execSync } = require('child_process');

const GW = 'http://127.0.0.1:8100';
// The simulator is deliberately NOT routed by the Gateway — same as the connectors and the Core
// Banking simulator — so it is reached on the service's own port.
const SVC = 'http://127.0.0.1:8116';

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const merchant = token('merchant');
const otherMerchant = token('merchant2');

const call = (m, base, p, body, tok) => {
  const auth = tok ? ` -H "Authorization: Bearer ${tok}"` : '';
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}"${auth}${data} "${base}${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, GW, p, b, t));
const get = (p, t) => JSON.parse(send('GET', p, null, t).body);
const sim = (m, p, b) => split(call(m, SVC, p, b, null));

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

const tag = Date.now().toString(36).slice(-6);
const NUMBER = `PN-rep-${tag}`;
const BRANCH = `PN-branch-${tag}`;
const CUSTOMER_WA = `961${String(Date.now()).slice(-9)}`;

console.log('--- the simulator stands in for a customer ---');
send('POST', '/api/whatsapp/numbers', { phoneNumberId: NUMBER, label: 'Orders' }, merchant);
sim('DELETE', '/simulator/sent');

const spoke = sim('POST', '/simulator/inbound', {
  phoneNumberId: NUMBER, from: CUSTOMER_WA, name: 'Rana', body: 'hello, are you open?',
});
check('a simulated message is accepted', spoke.code === '200', `HTTP ${spoke.code}`);

const convo = get('/api/whatsapp/conversations', merchant).find(c => c.customerWaId === CUSTOMER_WA);
check('and lands in the merchant\'s inbox', !!convo, convo && convo.customerName);
const thread = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
check('with the text intact', thread[0].body === 'hello, are you open?', thread[0].body);
check('marked INBOUND', thread[0].direction === 'INBOUND', thread[0].direction);

console.log('\n--- the merchant answers ---');
const reply = send('POST', `/api/whatsapp/conversations/${convo.id}/reply`,
  { body: 'Yes, until midnight. What can we send you?' }, merchant);
check('the reply is accepted', reply.code === '202', `HTTP ${reply.code}`);
const replied = JSON.parse(reply.body);
check('and reports that it actually went out', replied.sent === true, `sent=${replied.sent}`);
check('recorded as OUTBOUND', replied.message.direction === 'OUTBOUND', replied.message.direction);
check('carrying the provider\'s id', !!replied.message.id, 'identified');

const afterReply = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
check('the thread now shows both halves',
  afterReply.length === 2 && afterReply[1].direction === 'OUTBOUND', `${afterReply.length} messages`);
check('oldest first', new Date(afterReply[0].sentAt) <= new Date(afterReply[1].sentAt), 'ordered');

const delivered = JSON.parse(sim('GET', '/simulator/sent').body);
check('and the message really reached the provider',
  delivered.some(m => m.to === CUSTOMER_WA && m.body.startsWith('Yes, until midnight')),
  `${delivered.length} sent`);
check('sent from the number the customer wrote to',
  delivered.find(m => m.to === CUSTOMER_WA).from === NUMBER, NUMBER);

console.log('\n--- our own reply is not something waiting for us ---');
const listed = get('/api/whatsapp/conversations', merchant).find(c => c.id === convo.id);
// It moves up the list, because something happened. It does not become an unread.
check('replying does not create an unread', listed.unreadCount === 1, `${listed.unreadCount}`);
check('but does move the conversation up',
  new Date(listed.lastMessageAt) >= new Date(convo.lastMessageAt), 'bumped');

console.log('\n--- a shop with two numbers answers on the right one ---');
send('POST', '/api/whatsapp/numbers', { phoneNumberId: BRANCH, label: 'Branch line' }, merchant);
sim('POST', '/simulator/inbound', {
  phoneNumberId: BRANCH, from: CUSTOMER_WA, name: 'Rana', body: 'trying the branch',
});
send('POST', `/api/whatsapp/conversations/${convo.id}/reply`, { body: 'Branch here.' }, merchant);
const branchSends = JSON.parse(sim('GET', '/simulator/sent').body)
  .filter(m => m.to === CUSTOMER_WA && m.body === 'Branch here.');
// Answering on the number they are not looking at is the same as not answering.
check('the reply follows where they last wrote',
  branchSends.length === 1 && branchSends[0].from === BRANCH,
  branchSends.length ? branchSends[0].from : 'nothing sent');

console.log('\n--- one shop cannot answer for another ---');
check('a different merchant cannot reply',
  send('POST', `/api/whatsapp/conversations/${convo.id}/reply`,
    { body: 'Actually we are closed' }, otherMerchant).code === '404', 'absent, not forbidden');
check('and nothing was sent',
  !JSON.parse(sim('GET', '/simulator/sent').body).some(m => m.body.includes('Actually we are closed')),
  'nothing left the building');
check('an empty reply is refused',
  send('POST', `/api/whatsapp/conversations/${convo.id}/reply`, { body: '   ' }, merchant).code === '400',
  'validation');

console.log('\n--- placing an order tells the customer, unprompted ---');
// The thing they are sitting there waiting for, and the thing a merchant most often forgets to do
// by hand.
const store = get('/api/stores/mine', merchant).content.find(s => s.availability !== 'CLOSED');
const item = (get('/api/products/mine?size=50', merchant).content || [])
  .find(p => p.storeId === store.id && p.status === 'ACTIVE'
    && get(`/api/whatsapp/drafts/products/${p.id}/options`, merchant).every(g => !g.required));

if (item) {
  let draft = JSON.parse(send('POST', `/api/whatsapp/drafts/conversations/${convo.id}`,
    { requestText: 'one please' }, merchant).body);
  draft = JSON.parse(send('POST', `/api/whatsapp/drafts/${draft.id}/lines`,
    { productId: item.id, qty: 1 }, merchant).body);
  send('PUT', `/api/whatsapp/drafts/${draft.id}/delivery`,
    { deliveryAddress: `Hamra (${tag})` }, merchant);

  const placed = send('POST', `/api/whatsapp/drafts/${draft.id}/place`, null, merchant);
  check('the order is placed', placed.code === '200', `HTTP ${placed.code}`);

  const confirmations = JSON.parse(sim('GET', '/simulator/sent').body)
    .filter(m => m.to === CUSTOMER_WA && m.body.includes('confirmed'));
  check('the customer is told without the merchant typing it',
    confirmations.length === 1, `${confirmations.length} confirmation(s)`);
  // "How much is it" is otherwise the next message.
  const order = get(`/api/orders/${JSON.parse(placed.body).orderId}`, merchant);
  check('and told the total', confirmations[0].body.includes(String(order.totalAmount)),
    confirmations[0].body.slice(0, 60));
  check('it appears in the thread too',
    get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant)
      .some(m => m.direction === 'OUTBOUND' && m.body.includes('confirmed')), 'visible');
} else {
  fail++;
  console.log('  FAIL  no option-free product available; confirmation path not exercised');
}

console.log('\n--- the simulator is not a way past the signature ---');
// The whole point. If this endpoint could inject a message without a valid signature, it would be a
// hole in the one public path in the platform rather than a development convenience.
const unclaimed = sim('POST', '/simulator/inbound', {
  phoneNumberId: `PN-nobody-${tag}`, from: '96170000000', name: 'Nobody', body: 'let me in',
});
check('a message to an unclaimed number is dropped', unclaimed.code === '200', `HTTP ${unclaimed.code}`);
check('and reaches no merchant',
  get('/api/whatsapp/conversations', merchant).every(c => c.customerWaId !== '96170000000'), 'clean');

// The simulator posts through the real webhook, so it must be subject to the same rejections. A
// forged signature on that path is already covered by smoke-test-whatsapp.js; what is checked here
// is that the simulator has no separate, unsigned door of its own.
check('the simulator is not reachable through the Gateway',
  send('POST', '/simulator/inbound',
    { phoneNumberId: NUMBER, from: CUSTOMER_WA, name: 'Rana', body: 'via gateway' }, merchant)
    .code === '404',
  'unrouted, like the connectors');
check('nor is /simulator/sent',
  send('GET', '/simulator/sent', null, merchant).code === '404', 'unrouted');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);

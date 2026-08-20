// WhatsApp ordering — the inbound half.
//
//   node infra/smoke-test-whatsapp.js
//
// Almost every small shop in this market already takes orders on WhatsApp. This checks the front
// door: a customer's message arrives, is proved to have come from the provider, and lands in the
// right merchant's inbox — and nobody else's.
//
// Two things are worth more than the rest here. The webhook is the only path in this service
// reachable from the internet, so every way in that must stay shut is checked explicitly. And
// WhatsApp redelivers any callback it believes was not acknowledged, so the same message arriving
// twice must produce one line in the thread, not two.
const { execSync } = require('child_process');
const crypto = require('crypto');

const GW = 'http://127.0.0.1:8100';
// Matches WHATSAPP_APP_SECRET in infra/docker-compose.yml. In a deployment this is Meta's app
// secret and comes from Vault; here it is what lets the test sign a payload the way Meta would.
const SECRET = process.env.WHATSAPP_APP_SECRET || 'local-webhook-secret';

const sh = (c) => execSync(c, { encoding: 'utf8', maxBuffer: 2e7 });
const token = (u) => JSON.parse(sh('curl -s -X POST "http://127.0.0.1:8180/realms/delivery-platform/protocol/openid-connect/token"'
  + ` -d "client_id=mobile-app" -d "username=${u}" -d "password=${u}" -d "grant_type=password" -d "scope=openid"`)).access_token;

const merchant = token('merchant');
// A second, unrelated shop. The interesting isolation question is not "can a customer read the
// inbox" — it is whether one merchant can read another merchant's customers, and only a second
// MERCHANT token asks that. A backoffice token is stopped by the role check long before ownership
// is ever considered, so it proves nothing about tenancy.
const otherMerchant = token('merchant2');
const backoffice = token('backoffice');
const customer = token('customer');

const call = (m, p, body, tok) => {
  const auth = tok ? ` -H "Authorization: Bearer ${tok}"` : '';
  const data = body !== undefined && body !== null
    ? ` -H "Content-Type: application/json" -d "${JSON.stringify(body).replace(/"/g, '\\"')}"` : '';
  return sh(`curl -s -X ${m} -w "~~%{http_code}"${auth}${data} "${GW}${p}"`);
};
const split = (r) => { const i = r.lastIndexOf('~~'); return { body: r.slice(0, i), code: r.slice(i + 2).trim() }; };
const send = (m, p, b, t) => split(call(m, p, b, t));
const get = (p, t) => JSON.parse(send('GET', p, null, t).body);

let pass = 0, fail = 0;
const check = (label, cond, detail) => {
  if (cond) { pass++; console.log('  PASS  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
  else { fail++; console.log('  FAIL  ' + String(label).slice(0, 58).padEnd(58) + (detail ?? '')); }
};

const tag = Date.now().toString(36).slice(-6);
const NUMBER = `PN-${tag}`;
// Digits from the clock, not from a base36 tag with its letters stripped. That derivation collapsed
// six characters into two or three digits and collided across runs — two runs then shared one
// conversation, and the thread-length checks failed in a way that read like a product bug.
const CUSTOMER_WA = `961${String(Date.now()).slice(-9)}`;

// ---------------------------------------------------------------- posting a signed callback
//
// The signature covers the raw bytes, so the body has to go over the wire byte-for-byte as signed.
// Written to a file and posted with --data-binary @file rather than inlined: a shell would mangle
// the quotes, and re-encoding is precisely what the signature exists to detect.
const fs = require('fs');
const os = require('os');
const path = require('path');
const bodyFile = path.join(os.tmpdir(), `wa-${tag}.json`);

const postWebhook = (payload, { secret = SECRET, signature = null, header = true } = {}) => {
  const raw = JSON.stringify(payload);
  fs.writeFileSync(bodyFile, raw, 'utf8');
  const sig = signature !== null ? signature
    : 'sha256=' + crypto.createHmac('sha256', secret).update(raw, 'utf8').digest('hex');
  const sigHeader = header ? ` -H "X-Hub-Signature-256: ${sig}"` : '';
  return split(sh(`curl -s -X POST -w "~~%{http_code}" -H "Content-Type: application/json"`
    + `${sigHeader} --data-binary "@${bodyFile}" "${GW}/webhooks/whatsapp"`));
};

let seq = 0;
const envelope = (text, over = {}) => {
  const message = {
    from: over.from || CUSTOMER_WA,
    id: over.id || `wamid.${tag}.${++seq}`,
    timestamp: String(Math.floor(Date.now() / 1000)),
    type: over.type || 'text',
    ...(over.type ? over.payload : { text: { body: text } }),
  };
  return {
    object: 'whatsapp_business_account',
    entry: [{
      id: 'WABA',
      changes: [{
        field: 'messages',
        value: {
          messaging_product: 'whatsapp',
          metadata: { display_phone_number: '96170000000', phone_number_id: over.number || NUMBER },
          contacts: [{ profile: { name: over.name || 'Rana' }, wa_id: over.from || CUSTOMER_WA }],
          messages: [message],
        },
      }],
    }],
  };
};

console.log('--- the shop connects its own number ---');
// A form, not a pull request against the config repository. The alternative makes every shop that
// signs up an engineering change.
const connected = send('POST', '/api/whatsapp/numbers',
  { phoneNumberId: NUMBER, label: 'Front counter', displayNumber: '+96170000000' }, merchant);
check('a merchant connects a number', connected.code === '201', `HTTP ${connected.code}`);
check('and sees it in their list',
  get('/api/whatsapp/numbers', merchant).some(n => n.phoneNumberId === NUMBER), NUMBER);

const stolen = send('POST', '/api/whatsapp/numbers',
  { phoneNumberId: NUMBER, label: 'Mine now' }, backoffice);
// BACKOFFICE is not a merchant, so this is 403 before ownership is even considered.
check('a non-merchant cannot connect one', stolen.code === '403', `HTTP ${stolen.code}`);

const renamed = send('POST', '/api/whatsapp/numbers',
  { phoneNumberId: NUMBER, label: 'Main line', displayNumber: '+96170000000' }, merchant);
check('reconnecting your own number renames it', renamed.code === '201'
  && JSON.parse(renamed.body).label === 'Main line', JSON.parse(renamed.body).label);

console.log('\n--- the webhook is shut to everyone but the provider ---');
// This endpoint is the only one in the service reachable from the internet. Everything in this
// block is a way in that must stay shut.
check('an unsigned callback is refused',
  postWebhook(envelope('let me in'), { header: false }).code === '401', 'no signature');
check('a signature from the wrong secret is refused',
  postWebhook(envelope('let me in'), { secret: 'not-the-secret' }).code === '401', 'forged');
check('a made-up signature is refused',
  postWebhook(envelope('let me in'), { signature: 'sha256=' + 'a'.repeat(64) }).code === '401', 'garbage');
check('a bare digest with no algorithm prefix is refused',
  postWebhook(envelope('let me in'), {
    signature: crypto.createHmac('sha256', SECRET).update('{}', 'utf8').digest('hex'),
  }).code === '401', 'no prefix');

// A genuine signature over a different body — the exact attack signing the bytes prevents.
const genuine = envelope('genuine');
const rawGenuine = JSON.stringify(genuine);
const goodSig = 'sha256=' + crypto.createHmac('sha256', SECRET).update(rawGenuine, 'utf8').digest('hex');
check('a real signature over other bytes is refused',
  postWebhook(envelope('swapped'), { signature: goodSig }).code === '401', 'replayed signature');

console.log('\n--- the registration handshake ---');
const challenge = split(sh(`curl -s -w "~~%{http_code}" "${GW}/webhooks/whatsapp`
  + `?hub.mode=subscribe&hub.verify_token=delivery-local-verify&hub.challenge=abc123"`));
check('the right verify token echoes the challenge',
  challenge.code === '200' && challenge.body.trim() === 'abc123', challenge.body.trim());
const wrongToken = split(sh(`curl -s -w "~~%{http_code}" "${GW}/webhooks/whatsapp`
  + `?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=abc123"`));
check('a wrong one gets nothing', wrongToken.code === '403', `HTTP ${wrongToken.code}`);

console.log('\n--- a customer\'s message reaches the merchant ---');
const first = envelope('hi, do you deliver to Hamra?');
check('a signed callback is accepted', postWebhook(first).code === '200', 'accepted');

const inbox = get('/api/whatsapp/conversations', merchant);
const convo = inbox.find(c => c.customerWaId === CUSTOMER_WA);
check('a conversation appears in the inbox', !!convo, convo ? convo.customerName : 'missing');
check('named as WhatsApp reports them', convo && convo.customerName === 'Rana', convo && convo.customerName);
check('showing one unread', convo && convo.unreadCount === 1, convo && `${convo.unreadCount} unread`);

const thread = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
check('the thread holds the message', thread.length === 1, `${thread.length} message(s)`);
check('verbatim', thread[0] && thread[0].body === 'hi, do you deliver to Hamra?', thread[0] && thread[0].body);
check('marked INBOUND', thread[0] && thread[0].direction === 'INBOUND', thread[0] && thread[0].direction);

console.log('\n--- WhatsApp redelivers; the merchant must not see it twice ---');
// The single most consequential property here. A provider retries any callback it believes was not
// acknowledged, and a duplicated request in the thread invites sending the same order twice.
const replayCode = postWebhook(first).code;
check('a redelivered callback is still accepted', replayCode === '200', `HTTP ${replayCode}`);
const afterReplay = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
check('but adds nothing to the thread', afterReplay.length === 1, `${afterReplay.length} message(s)`);
const convoAfter = get('/api/whatsapp/conversations', merchant).find(c => c.id === convo.id);
check('and does not double the unread count', convoAfter.unreadCount === 1,
  `${convoAfter.unreadCount} unread`);

console.log('\n--- the conversation accumulates ---');
postWebhook(envelope('and how long does it take?'));
const grown = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
check('a second message joins the same thread', grown.length === 2, `${grown.length} messages`);
check('oldest first, which is how a conversation reads',
  new Date(grown[0].sentAt) <= new Date(grown[1].sentAt), 'ordered');
check('one conversation per customer, not per message',
  get('/api/whatsapp/conversations', merchant).filter(c => c.customerWaId === CUSTOMER_WA).length === 1,
  'single');

console.log('\n--- what the platform cannot read, it does not pretend to lose ---');
postWebhook(envelope(null, { type: 'audio', payload: { audio: { id: 'MEDIA1', voice: true } } }));
const withVoice = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
const voice = withVoice[withVoice.length - 1];
// A merchant seeing nothing where a voice note arrived concludes the platform lost it.
check('a voice note appears as a voice note', voice.messageType === 'AUDIO', voice.messageType);
check('with no invented body', voice.body === null || voice.body === '', JSON.stringify(voice.body));

postWebhook(envelope(null, {
  type: 'image', payload: { image: { id: 'MEDIA2', caption: '2 of these please' } },
}));
const withPhoto = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant);
const photo = withPhoto[withPhoto.length - 1];
// Often the whole order.
check('a photo keeps its caption', photo.body === '2 of these please', photo.body);

console.log('\n--- a message to a number nobody has claimed ---');
const orphan = postWebhook(envelope('anyone there?', { number: `PN-nobody-${tag}` }));
// 200, not an error: the callback was genuine and retrying it would not help. It is simply not
// stored, because no merchant could ever read it.
check('is accepted and dropped, not queued forever', orphan.code === '200', `HTTP ${orphan.code}`);
check('and creates nothing in this merchant\'s inbox',
  get('/api/whatsapp/conversations', merchant).every(c => c.customerWaId !== 'anyone'), 'clean');

console.log('\n--- one shop cannot read another\'s customers ---');
check('a customer token cannot open the inbox',
  send('GET', '/api/whatsapp/conversations', null, customer).code === '403', 'forbidden');
check('nor can backoffice',
  send('GET', '/api/whatsapp/conversations', null, backoffice).code === '403', 'forbidden');
check('an anonymous caller gets nothing',
  send('GET', '/api/whatsapp/conversations', null, null).code === '401', 'unauthorised');

// The real tenancy check: another MERCHANT, who passes the role gate and is stopped only by
// ownership. 404 rather than 403 on purpose — "that exists but is not yours" confirms a customer is
// talking to a competitor, which is not ours to reveal.
check('another shop cannot open the conversation',
  send('GET', `/api/whatsapp/conversations/${convo.id}`, null, otherMerchant).code === '404',
  'absent, not forbidden');
check('nor read its messages',
  send('GET', `/api/whatsapp/conversations/${convo.id}/messages`, null, otherMerchant).code === '404',
  'absent');
check('nor mark it read',
  send('POST', `/api/whatsapp/conversations/${convo.id}/read`, null, otherMerchant).code === '404',
  'absent');
check('nor archive it',
  send('POST', `/api/whatsapp/conversations/${convo.id}/archive`, null, otherMerchant).code === '404',
  'absent');
check('and sees none of it in their own inbox',
  get('/api/whatsapp/conversations', otherMerchant).every(c => c.id !== convo.id), 'isolated');

// Claiming a number someone else holds would hand over their live conversations — customers, phone
// numbers, order history — and the request would look like a success.
check('nor claim the number out from under them',
  send('POST', '/api/whatsapp/numbers', { phoneNumberId: NUMBER, label: 'Mine now' },
    otherMerchant).code === '409', 'conflict');
check('nor disconnect it',
  send('DELETE', `/api/whatsapp/numbers/${NUMBER}`, null, otherMerchant).code === '404', 'absent');
check('and the number is still the first shop\'s',
  get('/api/whatsapp/numbers', merchant).some(n => n.phoneNumberId === NUMBER), 'held');

console.log('\n--- the merchant works their inbox ---');
const read = send('POST', `/api/whatsapp/conversations/${convo.id}/read`, null, merchant);
check('marking read clears the badge',
  read.code === '200' && JSON.parse(read.body).unreadCount === 0, `HTTP ${read.code}`);

const archived = send('POST', `/api/whatsapp/conversations/${convo.id}/archive`, null, merchant);
check('archiving files it away',
  archived.code === '200' && JSON.parse(archived.body).archived === true, `HTTP ${archived.code}`);
check('and it leaves the open inbox',
  get('/api/whatsapp/conversations', merchant).every(c => c.id !== convo.id), 'gone');
check('but is still there when asked for',
  get('/api/whatsapp/conversations?archived=true', merchant).some(c => c.id === convo.id), 'archived');

postWebhook(envelope('actually, I want to order'));
const reopened = get('/api/whatsapp/conversations', merchant).find(c => c.id === convo.id);
// A merchant who tidied this away last week has a new question in front of them now. Leaving it
// archived would hide the one thing that changed.
check('a new message un-archives it', !!reopened && reopened.archived === false, 'back in the inbox');
check('with an unread waiting', reopened && reopened.unreadCount === 1, reopened && `${reopened.unreadCount}`);

console.log('\n--- releasing a number ---');
const beforeRelease = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant).length;
check('a merchant disconnects their own',
  send('DELETE', `/api/whatsapp/numbers/${NUMBER}`, null, merchant).code === '204', 'released');

const afterRelease = postWebhook(envelope('still open?'));
check('a callback to it is still accepted', afterRelease.code === '200', `HTTP ${afterRelease.code}`);
const afterCount = get(`/api/whatsapp/conversations/${convo.id}/messages`, merchant).length;
check('but nothing more is routed to the shop', afterCount === beforeRelease,
  `${afterCount} vs ${beforeRelease}`);
// "Disconnect" must not mean "delete every customer this shop has ever spoken to". A merchant
// switching providers would otherwise lose their whole history to a button.
check('and the history survives', afterCount > 0, `${afterCount} messages kept`);
check('the conversation is still readable',
  send('GET', `/api/whatsapp/conversations/${convo.id}`, null, merchant).code === '200', 'intact');

try { fs.unlinkSync(bodyFile); } catch { /* best effort */ }

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);

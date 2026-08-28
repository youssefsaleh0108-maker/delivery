// Where this site's back end lives, set per deployment rather than baked into register.js.
//
// register.js falls back to the loopback addresses a developer running the whole stack on their own
// machine would have, which is right there and wrong everywhere else. A deployment overrides both
// here — one file to change, and the application logic never has to know which environment it is
// in.
window.DELIVERY_API_BASE = 'https://api-dev.youdrop.shop';

// Keycloak, for the one thing on this site that signs somebody in: the receipt's document panel.
//
// The applicant's passcode is exchanged for a token by a direct grant against the realm's token
// endpoint, with the mobile app's public client id — the same client the phone uses, which is why
// this origin had to be added to that client's Web Origins before any of it could work from a
// browser. Nothing else on this site authenticates, and no token is ever written to storage.
window.DELIVERY_IAM_BASE = 'https://iam-dev.youdrop.shop';
window.DELIVERY_IAM_REALM = 'delivery-platform';

// Where this site's API lives, set per deployment rather than baked into register.js.
//
// register.js falls back to 127.0.0.1:8100, which is right for a developer running the stack on
// their own machine and wrong everywhere else. A deployment overrides it here — one file to change,
// and the application logic never has to know which environment it is in.
window.DELIVERY_API_BASE = 'https://api-dev.youdrop.shop';

# Social sign-in — what is built, and what you have to supply

The Figma design puts **Google** and **Apple** buttons on the welcome screen. Everything on this
platform's side of those buttons is written. Neither can be switched on without an account that
only you can open, so this file is the handover: exactly which screen, exactly which values, and
exactly where they go.

Read it top to bottom once before touching the Google console. The order matters — step 0 is a
blocker, and doing it after the OAuth client is registered means registering it twice.

---

## Status

| Piece | State |
| --- | --- |
| Google identity provider in the realm | configured, **disabled**, no credentials |
| Mappers (email, first name, last name, username, CUSTOMER role) | written, in the realm file and in `apply-identity-updates.sh` |
| Account linking (existing account + same email must link, not duplicate) | hardened flow written, see [Account linking](#account-linking) |
| Redirect URI to register | known exactly, [below](#step-2--create-the-oauth-client) |
| Google Cloud project + OAuth client | **you** |
| Apple Sign In | **you**, and it needs a paid developer account — see [Apple](#apple) |
| The Google button in the mobile app | drawn, deliberately wired to `null` until credentials exist |

Nothing in this repo contains a Google client id or secret, and nothing in it contains a stand-in
for one. If you find a string that looks like a credential, it is not one and it did not come from
here.

---

## Step 0 — Keycloak needs a real hostname and TLS. Already done.

Google's OAuth client form rejects plain `http` on anything other than `localhost`, rejects bare
IP addresses, and rejects a port on a public host — so a redirect URI has to be a real HTTPS
hostname before anything else can happen.

It is. The deployed box already publishes

```
KEYCLOAK_PUBLIC_URL=https://iam-dev.youdrop.shop
```

behind Traefik with a Let's Encrypt certificate (verified against the live `.env` and the running
container on 2026-08-27, during the TLS cutover earlier that week). There is nothing to do here;
the redirect URI in step 2 can be registered as written. The paragraph exists so nobody re-derives
the requirement and thinks it is outstanding.

---

## Step 1 — Google Cloud project and consent screen

1. <https://console.cloud.google.com> → create a project, or pick the one you want to own this.
   The project name is shown to nobody; the **app name** in the next step is.
2. **APIs & Services → OAuth consent screen.** Newer consoles have moved this to **Google Auth
   Platform → Branding** and **→ Audience**; it is the same thing under a new menu.
   - User type / audience: **External**.
   - App name: `YouDrop` — this is the text a customer reads on the Google screen, above your
     logo. It is worth getting right the first time; changing it later can re-trigger review.
   - User support email: yours.
   - App logo: optional, and uploading one moves the app into Google's brand-verification queue.
     Skip it until you are ready for that wait.
   - Authorised domain: `youdrop.shop`
   - Developer contact email: yours.
3. **Scopes.** Add exactly three, and no more:
   - `openid`
   - `.../auth/userinfo.email`
   - `.../auth/userinfo.profile`

   These are Google's "non-sensitive" scopes. An app that asks for only these does **not** need
   Google's security review, which is a multi-week process with a questionnaire. Adding anything
   else — contacts, calendar, a Gmail scope — triggers it. We do not need anything else: the
   platform wants an address and a name, and the phone number comes from our own verification.
4. **Audience / publishing status.** While it says *Testing*, only the Google accounts you list as
   test users can sign in, and their consent expires after 7 days. That is the right setting while
   you try it. Press **Publish app** when you want real customers, and with only non-sensitive
   scopes that takes effect immediately with no review.

---

## Step 2 — Create the OAuth client

**APIs & Services → Credentials → Create credentials → OAuth client ID → Web application.**

Name it something you will recognise in a list, e.g. `YouDrop — Keycloak (dev)`.

### Authorised redirect URIs

This is the field that matters, and it is the one people get wrong. Add these two, exactly:

```
https://iam-dev.youdrop.shop/realms/delivery-platform/broker/google/endpoint
http://localhost:8180/realms/delivery-platform/broker/google/endpoint
```

The second is for a developer laptop running the compose stack. Google makes a specific exception
for `http://localhost` on any port, so it is allowed where the IP form is not.

Google matches this string **character for character**. A trailing slash, `http` instead of
`https`, `www.`, or a port on the public host all produce `redirect_uri_mismatch` on Google's own
page.

### Authorised JavaScript origins

**Leave this empty.** It is not needed and adding hosts here will not fix anything.

That field only applies to flows where a browser calls Google's token endpoint directly — Google
Identity Services in a page, or the implicit flow. Keycloak does neither: the browser is redirected
to Google, comes back to the redirect URI above with a `code`, and **Keycloak's server** exchanges
that code for tokens over a back-channel call the browser never makes. The origin is never sent, so
Google never checks it.

If you would rather have it filled in for the sake of a future JS integration, the only value that
would ever be correct is `https://iam-dev.youdrop.shop`.

### Which of our hosts go where — the short answer

| Host | Register with Google? | Why |
| --- | --- | --- |
| `iam-dev.youdrop.shop` (Keycloak) | **Yes** — redirect URI, as above | This is the only address Google ever redirects to |
| `localhost:8180` (Keycloak, laptop) | **Yes** — redirect URI, as above | Same, for local dev |
| `api-dev.youdrop.shop` (gateway) | No | Never part of a login. It receives the finished token |
| `portal-dev.youdrop.shop` (portal) | No | Redirects **back to itself** — that is a Keycloak client redirect URI, and it is already registered on the `delivery-portal` client in the realm file |
| `youdrop.shop` / `www` / `app-dev` (website) | No | Marketing site. No login on it |
| `com.delivery.app://oauth2redirect` (the app) | No — and Google would reject it | Between the app and Keycloak. Registered on the `mobile-app` client in the realm file |

The single sentence to remember: **Google only ever talks to Keycloak. Everything else in the
platform talks to Keycloak too, and Google does not need to know any of it exists.**

---

## Step 3 — Where the client id and secret go

Google shows them once, on a dialog, after you press Create. The secret is retrievable later; the
dialog is not.

On the box, in `infra/.env` — which is gitignored, and is the same file the rest of the stack's
credentials live in:

```
GOOGLE_CLIENT_ID=<the value ending in .apps.googleusercontent.com>
GOOGLE_CLIENT_SECRET=<the value starting GOCSPX->
```

Then, from `infra/`, run these three in this order. The order is not decoration: step A creates the
hardened linking flow, step B is the only thing that holds credentials and so is the only thing
that writes the provider — including which flow it binds to — and step C attaches the mappers now
that the provider exists.

```bash
# A — install the hardened first-broker-login flow.
#     It will report that Google is bound to the built-in flow. That is expected here.
docker compose cp keycloak/apply-identity-updates.sh keycloak:/tmp/identity-updates.sh \
  && docker compose exec -T keycloak sh /tmp/identity-updates.sh

# B — register Google with your credentials, and bind it to the flow step A just created.
./keycloak/configure-google-idp.sh

# C — same script as A. Now it confirms the binding and (re)asserts the mappers.
docker compose exec -T keycloak sh /tmp/identity-updates.sh
```

Step B reads both values from the environment, registers the provider on the running Keycloak, and
enables it. **It never writes them to a file in this repository**, and the realm file in git holds
`$(env:GOOGLE_CLIENT_ID)` — a literal placeholder Keycloak resolves at import time, not a value.

All three are idempotent. Re-run A and C any time; re-run B whenever the credentials change.

If step C still says Google is bound to `first broker login`, step B did not run or did not
succeed — do not carry on until it says `already bound to youdrop-first-broker-login`.

**Read step C's output rather than just its exit code.** Any line beginning `!!` names something
that is *not* configured — a mapper Keycloak declined, or a flow whose shape the script did not
recognise. It steps over those deliberately so one refused mapper does not take the rest of the run
down with it, which means the script can finish successfully with a gap in it. The `!!` line is the
gap.

**Do not put these two values in `.env.contabo`, `.env.dev.example`, `docker-compose.dev.yml`, or
anywhere else that is tracked or shared.** `.env.dev.example` is committed on purpose as a template
and must stay credential-free.

If the secret ever leaks: Google Cloud → Credentials → the client → **Add secret**, then delete the
old one. Re-run `configure-google-idp.sh` in between and no user session is affected — an identity
provider secret is used only for the back-channel code exchange, not for anything already issued.

---

## Step 4 — Turn the button on in the app

`clients/apps/mobile_app/lib/main.dart` currently passes `onGoogle: null` to `WelcomeScreen`, with
a comment saying why: a control that cannot work should not be shown. The handler
(`_signInWithGoogle`) is written and correct and is deliberately kept rather than deleted.

Once step 3 is done, that becomes `onGoogle: _signInWithGoogle`. That is a one-line change in the
Flutter client and it is not in this directory — it belongs to whoever owns `clients/`.

---

## Account linking

**The thing this had to get right:** a customer who signed up with `sam@gmail.com` and a password,
and who later taps *Continue with Google* on the same address, must end up in **the account they
already have** — with their orders, their addresses and their points — and must not quietly get a
second, empty one.

Three things make that hold, and all three are already configured:

1. **`duplicateEmailsAllowed` is false.** Keycloak only checks an incoming brokered email against
   existing accounts when duplicate emails are forbidden. Turn this on and every returning customer
   signing in with Google gets a fresh empty account with their own address on it, and nothing
   anywhere reports a problem. `apply-identity-updates.sh` re-asserts it on every run for that
   reason.

2. **The username mapper forces `username = email`.** `onboarding-service` creates every local
   account that way, so a Google-created account and a sign-up-created account are the same shape
   and match on both fields rather than only on one.

3. **Linking requires signing in to the existing account.** This is the part that is ours rather
   than Keycloak's default, and it is worth understanding before you change it.

   Keycloak's built-in flow offers two ways to prove that an existing account is yours: click a
   link mailed to it, or sign in to it. Either is enough. We **disable the mailed link** and leave
   signing in as the only route.

   The reason: the address on a local account is not necessarily an address anybody proved.
   Keycloak's account console lets a signed-in user change their own email. So somebody can park a
   stranger's address on their own account — and then, on the mailed-link route with a trusted
   broker, the stranger's Google login is itself treated as the proof. The stranger sees a screen
   saying "an account with this address already exists, link it?", answers yes because it looks
   like their own account, and has just handed a password-holder the keys to it.

   Signing in to the existing account cannot be satisfied that way. It also does not depend on mail
   being deliverable, which on this box it currently is not for anybody outside Mailpit.

   **The cost, stated plainly:** an account that has never had a password set cannot be linked this
   way. Partner accounts are created with an `UPDATE_PASSWORD` action and no password, so a partner
   who has never signed in and tries Google first will be stopped. The route back is *Forgot
   password*, which mails the address their application already verified by code.

If you ever want the mailed-link route back, it is one line — re-enable `idp-email-verification` in
the `youdrop-first-broker-login` flow — but read the paragraph above first, because that is the
hole it re-opens.

---

## Apple

**Apple Sign In cannot be turned on from this repository, and it is not a matter of pasting two
values like Google.** Here is the whole truth, so you can decide whether it is worth it now.

**What it costs.**

- **Apple Developer Program membership: US$99 per year.** There is no free tier for Sign in with
  Apple. Without a paid membership none of the identifiers below can be created.
- Time. Expect the key and identifier setup to take longer than Google's, and the private key to be
  downloadable exactly once.

**What you would have to create, in the Apple Developer portal:**

| Thing | What it is |
| --- | --- |
| App ID | With the *Sign in with Apple* capability enabled |
| **Services ID** | This is the OAuth `client_id`. It is not the App ID |
| Return URL on the Services ID | `https://iam-dev.youdrop.shop/realms/delivery-platform/broker/apple/endpoint` |
| **Sign in with Apple key (.p8)** | Downloadable **once**. Lose it and you make a new one |
| Key ID | 10 characters, shown with the key |
| Team ID | 10 characters, top right of the portal |

**Why it is more work than Google, and this is the part that usually surprises people:**

1. **Apple has no client secret.** What Apple calls the client secret is a **JWT that you generate
   and sign yourself** with the `.p8` key, using ES256, with your Team ID as issuer and the
   Services ID as subject. **Apple caps its lifetime at six months.** So it is not a value you
   paste once — it is a value something has to regenerate, forever, or Apple sign-in stops working
   on a date nobody has in a calendar.

2. **Keycloak has no built-in Apple provider.** Its social providers are Google, Facebook, GitHub,
   GitLab, Bitbucket, Instagram, LinkedIn, Microsoft, PayPal, Stack Overflow, Twitter and OpenShift
   — Apple is not among them, in any version, including the 26.0 this stack runs. Two ways round
   it, and both are real work rather than configuration:
   - install a community Apple identity-provider extension into the Keycloak image (a `.jar` in
     `providers/`, which means owning its upgrade path and its security), or
   - register Apple as a **generic OIDC provider** and run a scheduled job that regenerates the
     client-secret JWT and writes it into Keycloak before it expires.

3. **Apple's private email relay changes the linking maths.** A user may choose *Hide My Email*,
   in which case the address you receive is a per-app relay like
   `a1b2c3d4e5@privaterelay.appleid.com`, not their real one. That address is stable for as long as
   the user keeps the app authorised — and stops working if they revoke it. Everything in
   [Account linking](#account-linking) above keys on email, so an Apple user cannot be matched to
   an existing YouDrop account by address at all. They would need a separate, deliberate linking
   path, and that is a design decision, not a config value.

4. **Apple sends the name exactly once** — on the very first authorisation, and never again. If it
   is not captured then, it is gone, and the account is nameless unless you ask for it in the app.

**Recommendation.** Ship Google. Come back to Apple when there is an iOS App Store release, because
that is also the point at which Apple's own review guidelines start to *require* Sign in with Apple
for apps that offer other social logins — which is the real reason to pay for it. Doing it before
then buys a recurring bill, a secret-rotation job and a linking problem, for a button.

---

## Verifying it actually works

After step 3, in this order:

1. `https://iam-dev.youdrop.shop/realms/delivery-platform/account` should show a Keycloak page, over
   HTTPS, with a valid certificate. If not, stop — step 0 is not done.
2. Admin console → `delivery-platform` → Identity providers → Google should be **Enabled**, with a
   client id present, and *First login flow override* / *First broker login flow* set to
   `youdrop-first-broker-login`. Its **Mappers** tab should list five: `username-from-email`,
   `email`, `first-name`, `last-name`, `customer-role`.
3. Sign in as a **brand new** Google address. Expect: one tap on Google, no profile form, and a new
   account in Users with the email, a first and last name, and the `CUSTOMER` role.
4. Sign in with a Google address that **already has a YouDrop account**. Expect: a screen saying an
   account already exists, then a password prompt for that account, then one account — not two.
   Check Users: there must still be exactly one row for that address, and *Identity provider links*
   on it must now list Google.
5. Sign out, sign in again with Google. Expect: straight in, no linking screens.

If step 4 produces two accounts, `duplicateEmailsAllowed` has been turned on somewhere. Re-run
`apply-identity-updates.sh`, then merge the duplicate by hand — there is no automatic repair, which
is exactly why the setting is re-asserted on every run.

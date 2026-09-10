# Sign in with Google

What the app does when somebody taps **Google**, what the platform grants them, and the handful of
things only the project owner can do to switch it on. Everything on the platform's side is built;
the provider stays **disabled** in the realm file until a real Google OAuth client exists.

For the Google Cloud Console walkthrough in more depth (consent screen, scopes, publishing, the
account-linking hardening) see [`infra/keycloak/SOCIAL-SIGN-IN-SETUP.md`](../infra/keycloak/SOCIAL-SIGN-IN-SETUP.md).
That file's shell commands are for the `docker compose` stack; **this** file covers the k3s cluster
(`delivery-dev`, `delivery-qa`), which is what `iam-dev.youdrop.shop` / `iam-qa.youdrop.shop` are.

---

## What the person sees

0. When the app starts, and again after every sign-out, it asks Keycloak whether the Google
   provider is enabled (see [The availability check](#the-availability-check)). While the answer
   is *no*, Create Account shows **no** Google button and the sign-in screen's Google button says
   *"Google sign-in is coming soon."* Nobody is asked customer / rider / seller for a sign-in that
   cannot happen.
1. They tap **Google** — in the sign-in screen's social row, or **Continue with Google** on
   Create Account.
2. A sheet asks **How will you use YouDrop?** — *Customer* (I want to order), *Rider* (I want to
   deliver), *Seller* (I want to sell). Nothing is pre-chosen on the sign-in screen; on Create
   Account the sheet starts on the role card already picked there. Dismissing it starts nothing.
   The sheet says riding and selling are reviewed and that an account can apply for only one of
   them — which is what the server enforces.
3. Before any browser opens, the app asks Keycloak again. If the provider was switched off since:
   *"Google sign-in isn't available yet. Please use your email or phone for now."* — no browser,
   and the buttons change as in step 0.
4. The browser opens straight on Google (`kc_idp_hint=google`, Authorization Code + PKCE, redirect
   `com.delivery.app://oauth2redirect`). Closing it: *"Google sign-in was cancelled. Nothing was
   changed."* Any other failure: *"Google sign-in did not complete."*
5. Back in the app, the answer decides what happens:

| They picked | Account already holds | What happens | Lands on |
| --- | --- | --- | --- |
| Customer | `CUSTOMER` | nothing to do | customer shell |
| Customer | not `CUSTOMER` | `POST /api/onboarding/me/customer` grants `CUSTOMER`, token refreshed | customer shell |
| Rider | `DELIVERY` (pending or live) | nothing to do | rider shell (pending banner if `APPLICANT`) |
| Seller | `MERCHANT` (pending or live) | nothing to do | merchant shell (pending banner if `APPLICANT`) |
| Rider / Seller | not that role, no application, no other partner role | the normal partner application, **for this account**: prefilled with the Google name and email, no email code, no passcode | on submit: `POST /api/onboarding/applications/mine`, token refreshed, then the rider / merchant shell with the pending banner |
| Rider / Seller | not that role, no application, but **another** partner role (`DELIVERY`, `MERCHANT` or `CARRIER`) | nothing; *"This account is already a YouDrop partner, and an account can hold only one partner role."* | wherever the account's roles route |
| Rider / Seller | not that role, **undecided** application of the same kind | the server re-asserts the applicant roles (finishes a half-done attempt), token refreshed | that shell |
| Rider / Seller | not that role, **decided** application of the same kind (approved then suspended, declined, or setup failed) | nothing resumed; *"The partner application on this account has already been decided, so it can't be reopened here. Please contact support."* | wherever the account's roles route — for no role, **One more step** |
| Rider / Seller | not that role, application of the **other** kind | nothing new; *"This account already has an application…"* | wherever the account's roles route |

An account that ends up holding **no role at all** — a new Google user who backs out of the
application, or a role grant that failed — is shown **One more step**, the same three answers as a
screen, with *Sign out* under it. It is never dropped into the customer shell without the role.

A partner approved the old way has their account on `provisioned_user_ref`, which
`GET /applications/mine` does not read, so the app cannot see their application before the form.
If one of them (suspended, say) picks their old role, they fill the form in and the server hands
back the decided application with nothing granted; the form then says the decided-application
sentence above and offers *Close* instead of *Try again*. Seeing it before the form needs
`GET /applications/mine` to read both columns — see [Known gaps](#known-gaps).

The choice is also a routing preference for the session: somebody holding both `DELIVERY` and
`MERCHANT` who picks *Seller* lands in the shop, not the rider queue.

Where it lives: the sheet and the no-role screen in
`clients/apps/mobile_app/lib/src/google_sign_in.dart`; the decision in
`clients/packages/delivery_core/lib/src/auth/broker_sign_in.dart` (`BrokerSignIn`); routing in
`clients/apps/mobile_app/lib/src/home_route.dart` (`homeFor`); the up-front availability check in
`clients/apps/mobile_app/lib/main.dart` (`_googleAvailable`).

---

## The gates — why this is not a way around the review

- **Nothing a Google login carries grants a role.** The realm has no role mapper on the Google
  provider (see [the mapper decision](#the-customer-role-mapper-removed)); every role comes from
  onboarding-service acting on the person's answer.
- **Both endpoints are authenticated and act only on the caller's own token subject.** Neither takes
  an account id in the path or the body. The email and whether it is verified come from the token's
  `email` / `email_verified` claims; an unverified address is refused (422), exactly as customer
  sign-up refuses one.
- **A rider or seller gets what an applicant account gets on the open form:** `APPLICANT` **and
  then** the live role (`DELIVERY` / `MERCHANT`). The order matters: a failure between the two
  grants leaves `APPLICANT` alone, which can do nothing. `APPLICANT` is what the committing
  endpoints (publish, claim) refuse on.
- **Only the existing approval path takes `APPLICANT` off:** the same Camunda review, the same
  auto-approval settings (`AutoApprovalPolicy`, per kind, backoffice-controlled), approving through
  the reviewer's own `OnboardingService.approve`.
- **Idempotent.** One account carries one application (`applicant_user_ref` is unique). A second
  call returns the same application (200 instead of 201); the other kind is refused (422).
- **No role can be re-obtained by re-applying, and no working partner is blocked by applying.** An
  account already holding **any** live partner role — `DELIVERY`, `MERCHANT` or `CARRIER`, not only
  the one asked for — is refused (422): `APPLICANT` is realm-wide, so granting it to a shop that
  asked to ride would stop the shop publishing, and a rejection never takes `APPLICANT` off again.
  A partner found by `provisioned_user_ref` (for example, suspended) gets their existing
  application back and nothing is granted.
- **Delivery companies are not offered.** `CARRIER` is refused on this path; a company applies
  through the company wizard.
- **Refusals the app can translate.** Each 422 this path knows carries a `code` beside its English
  `message` — `already-partner`, `other-application`, `email-unverified`, `name-missing`,
  `shop-name-missing`, `kind-not-offered` — and the app shows its own sentence, in the reader's
  language, for the ones a person can meet. A 502 (Keycloak would not set the roles) is known by its
  status. A refusal without a code (the domain's own) is shown as the server wrote it, as on the
  open form.

Server code: `services/onboarding-service/.../api/AccountOnboardingController.java`,
`.../service/AccountApplicationService.java`.

---

## The `customer-role` mapper: removed

The realm used to carry a hardcoded-role mapper, `customer-role`, that gave **every** Google account
`CUSTOMER` at first login. It is removed from both realm files
(`deploy/k3s/base/assets/keycloak/realm-delivery-platform.json` and
`infra/keycloak/realm-delivery-platform.json`), and `infra/keycloak/apply-identity-updates.sh` now
**deletes** it from a realm that has it instead of re-creating it.

Why: the app now asks the question, so the mapper would make somebody who came to ride a shopper
before they had answered, and would leave the question deciding nothing for the customer case. The
guarantee the mapper was protecting — Google cannot grant a partner role — holds more tightly
without it: no role at all comes from the login.

What that required, and is done: the customer answer grants `CUSTOMER` explicitly
(`POST /api/onboarding/me/customer`), and a role-less account is routed to **One more step** instead
of the old "anything else is a customer" fall-through in `main.dart`.

**The running dev and qa realms still have the mapper**, because they were imported from the realm
file on 2026-09-04, when it still contained it, and `--import-realm` never re-imports an existing
realm. Remove it once per environment — step 2 below does it. Until you do, a new Google user simply
gets `CUSTOMER` early; nothing breaks.

---

## What you (the owner) must do

Nothing in this repository contains a Google client id or secret, and nothing should.

> **The one rule: do not enable Google until its first-login flow is
> `youdrop-first-broker-login`.** The provider is registered with *Trust email* on. On Keycloak's
> built-in `first broker login` flow that combination is an account takeover: somebody parks a
> stranger's address on their own account, and the stranger's Google login is then treated as the
> proof that links it in — see *Account linking* in `SOCIAL-SIGN-IN-SETUP.md`. With this feature it
> is worse: a victim who then picks *Rider* or *Seller* puts their application, documents and bank
> details on the attacker's account. The steps below are ordered so that state never exists.

### 1. Create the Google OAuth client

In <https://console.cloud.google.com>, in the project that should own this:

1. **APIs & Services → OAuth consent screen** (newer consoles: **Google Auth Platform → Branding /
   Audience**). User type **External**. App name `YouDrop`. Support and developer contact: your
   address. Authorised domain: `youdrop.shop`.
2. **Scopes**: `openid`, `.../auth/userinfo.email`, `.../auth/userinfo.profile` — nothing else, so
   no Google security review is triggered.
3. **Audience**: while *Testing*, only listed test users can sign in. **Publish app** when real
   users should.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID → Web application.**
   Name it e.g. `YouDrop — Keycloak`.
   - **Authorised redirect URIs** — exactly these, character for character:
     ```
     https://iam-dev.youdrop.shop/realms/delivery-platform/broker/google/endpoint
     https://iam-qa.youdrop.shop/realms/delivery-platform/broker/google/endpoint
     ```
     Add `http://localhost:8180/realms/delivery-platform/broker/google/endpoint` only if you also
     want it on a developer laptop running the compose stack.
   - **Authorised JavaScript origins**: leave empty. Keycloak exchanges the code server-side.
   - Do **not** register `com.delivery.app://oauth2redirect` with Google — that redirect is between
     the app and Keycloak, and is already on the `mobile-app` client in the realm.
5. Copy the **Client ID** (`….apps.googleusercontent.com`) and **Client secret** (`GOCSPX-…`).
   One client can serve both environments, or make one per environment; either works.

### 2. Install the hardened first-login flow and remove the old mapper — first, with Google still off

`apply-identity-updates.sh` is idempotent. It re-asserts duplicate-email prevention, copies the
built-in first-login flow to `youdrop-first-broker-login` with the mailed-link route off (linking an
existing account requires signing in to it), sets review-profile to `missing`, attaches the four
mappers, and **deletes `customer-role`** if present.

It needs no credentials and works while the provider is **disabled**: the flow is created whatever
state Google is in, and the Google provider is already registered in both environments (the
2026-09-04 import brought it in, disabled), so the mapper section runs too. On k3s, from the repo
root on the box:

```sh
NS=delivery-dev            # then again with delivery-qa
POD=$(kubectl -n "$NS" get pod -l app=keycloak -o jsonpath='{.items[0].metadata.name}')
# The Keycloak image has no tar, so stream the script in rather than `kubectl cp`.
kubectl -n "$NS" exec -i "$POD" -- sh -c 'cat > /tmp/identity-updates.sh' \
  < infra/keycloak/apply-identity-updates.sh
# Single quotes: the admin credentials expand INSIDE the container, from its own environment,
# so they never appear on this machine's command line.
kubectl -n "$NS" exec "$POD" -- sh -c \
  'KEYCLOAK_ADMIN="$KC_BOOTSTRAP_ADMIN_USERNAME" KEYCLOAK_ADMIN_PASSWORD="$KC_BOOTSTRAP_ADMIN_PASSWORD" sh /tmp/identity-updates.sh'
```

Read the output. At this point it prints `!! bound to 'first broker login'` followed by *"Google is
disabled, so nothing is exposed yet"* — expected; step 3 binds the flow. Any **other** line
starting `!!` names something that is *not* configured. If it ever prints `!! AND GOOGLE IS
ENABLED`, the provider is live on the built-in flow: bind the flow or disable Google straight away.
If the bootstrap admin has been replaced, use your admin's credentials instead.

Without the script, the mapper can be deleted by hand (console → Identity providers → google →
**Mappers** → delete `customer-role`), but the hardened flow cannot sensibly be built by hand — run
the script.

### 3. Put the credentials in and bind the flow — still disabled

How Keycloak receives configuration on k3s, as it stands (checked in the manifests):

- The Keycloak Deployment (`deploy/k3s/base/identity.yaml`) gets its environment from
  `platform-secrets` (admin bootstrap, database password) and `platform-env` (`KEYCLOAK_PUBLIC_URL`).
  It has **no** `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` variables, and `platform-secrets`
  (`deploy/k3s/scripts/gen-secrets.sh`) has no such keys.
- **Vault and the `vault-reseed` sidecar are not involved.** They seed config-server's KV store for
  the Spring services from `platform-secrets`; Keycloak reads nothing from Vault.
- The realm file's `"clientId": "$(env:GOOGLE_CLIENT_ID)"` placeholders are resolved **only during
  `--import-realm`**, which only runs against an empty Keycloak database. Both environments' realms
  already exist, so neither the realm file nor an env var changes the running provider.

So on dev and qa the values go into **Keycloak's own database, through the admin console** — that
is the one place they take effect, and it keeps the secret out of shell history and out of git:

1. Open `https://iam-dev.youdrop.shop/admin/` and sign in as the Keycloak admin (the bootstrap
   admin's credentials are `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` in that namespace's
   `platform-secrets`).
2. Realm **delivery-platform → Identity providers → google**.
3. Paste **Client ID** and **Client Secret**.
4. **First login flow override**: `youdrop-first-broker-login`. If it is not in the dropdown,
   **stop** — step 2 has not run (or did not finish) in this environment. Run it, reload the page,
   and pick it then. Never leave this on `first broker login`.
5. Leave *Trust email* **on** — the signed-in application path relies on Google's
   `email_verified`, and it is safe only because of the flow chosen in 4.
6. Leave **Enabled** **off** for now, and **Save**.
7. Repeat on `https://iam-qa.youdrop.shop/admin/`.

Optional, for a rebuilt environment: to have a fresh `--import-realm` pick the values up, add them
to that namespace's `platform-secrets` and give the Keycloak container two
`secretKeyRef` env entries (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `optional: true`) in
`deploy/k3s/base/identity.yaml`. That is not done in this change; the realm file still imports the
provider **disabled** and on the built-in flow (the hardened one does not exist until step 2 has
run), so an import alone never switches Google on — and after one, steps 2 to 4 apply again.

### 4. Enable the provider

1. Run step 2's commands again. The Google section must now say
   `already bound to youdrop-first-broker-login`. If it says anything else, do not enable Google —
   go back to step 3.
2. Console → **Identity providers → google** → toggle **Enabled** on, **Save**. Repeat per
   environment.

There is **no app release to make**. The app asks Keycloak whether the provider is enabled when it
starts, after every sign-out, and again before opening a browser; a phone that was already open
while you enabled it picks Google up at its next launch or sign-out.

The app must be pointed at the TLS host, which the dev/qa builds are:
`--dart-define=KEYCLOAK_ISSUER=https://iam-dev.youdrop.shop/realms/delivery-platform` (and the
matching `API_BASE_URL`). A build still on the LAN-IP default issuer cannot use Google — Google will
not accept a redirect URI on a bare IP over http.

---

## First-login friction (the review-profile form)

- Keycloak's built-in first-login flow already uses `update.profile.on.first.login = missing`: the
  profile form appears only when Google did not supply something the realm requires. For a normal
  Google account (email, given name, family name) it never appears.
- It **cannot be set safely in the realm JSON.** The realm file declares no `authenticationFlows`,
  and Keycloak imports `authenticatorConfig` only together with `authenticationFlows` — so setting it
  there means restating every built-in flow by hand in the import, which risks a realm where login
  breaks at a step nobody can name. `apply-identity-updates.sh` sets it on the hardened copy instead.
- **Remaining friction you may want to decide on:** the realm's user profile marks `lastName` as
  required, and some Google accounts have no family name. Those people see the profile form once,
  asking for a last name. Making `lastName` optional in the declarative user profile would remove it;
  that is a realm-wide change to what every account must have, so it is left to you.
- **Existing passcode users** whose Google address matches their account see Keycloak's "account
  already exists" page and must sign in to that account once to link it. That is deliberate — see
  *Account linking* in `SOCIAL-SIGN-IN-SETUP.md`.

---

## The availability check

`kc_idp_hint` fails open: with the provider missing or disabled, Keycloak ignores the hint and shows
its own login page. So `AuthService.brokerAvailable` sends the same authorization request the
browser would (client `mobile-app`, the app's redirect URI, a PKCE S256 challenge, the hint) **without
following redirects**:

- a redirect to `…/broker/google/login…` → enabled, go ahead;
- `200` (Keycloak's login form) → not available, say so;
- anything else, or no answer → go ahead and let the round trip report the real problem.

The app asks it up front — at launch and after every sign-out (`BrokerSignIn.available`, kept in
`main.dart` as `_googleAvailable`) — so the buttons already know before anybody is asked
customer / rider / seller, and `BrokerSignIn.start` asks again before the browser opens. Only a
*no* from Keycloak hides Google; no answer leaves it offered.

It signs nobody in and stores nothing. It depends on the realm using Keycloak's built-in browser
flow (with its *Identity Provider Redirector*), which it does; a custom browser flow without that
step would make the app report Google as unavailable.

---

## Known gaps

- **The approval email still says to sign in with a passcode.** `NotifyApplicant` builds the
  approved body as "Sign in with the passcode you chose when you applied", and a Google applicant
  chose none. The fix is to word it by how the account signs in (or neutrally, "Sign in to the
  app"); it was left out of this change because that file carries other uncommitted work.
- **`GET /applications/mine` reads only the applicant column**, so a partner provisioned the old
  way meets the "already decided" sentence at the end of the form rather than before it (see
  above). Making that lookup read `provisioned_user_ref` as well, as
  `AccountApplicationService.existingFor` does, would move it before the form; it also feeds the
  document and payout endpoints, so it needs its own look.

---

## Verifying

1. Tap Google, pick **Customer**, sign in with a brand-new Google address. Expect: no profile form,
   the customer shell; in the admin console the user has `CUSTOMER` and nothing else (no
   `customer-role` mapper once step 2 is done).
2. New Google address, pick **Rider**, finish the application. Expect: the rider shell with the
   pending banner; the user holds `APPLICANT` and `DELIVERY`; the application is in the backoffice
   queue (or approved at once if auto-approval is on for riders, in which case `APPLICANT` is gone).
3. Back out of the application instead. Expect: **One more step**, not the customer shell.
4. Sign in again with a Google account that already rides and pick **Rider**. Expect: straight in, no
   second application.
5. Sign in with a Google account that already sells and pick **Rider**. Expect: *"This account is
   already a YouDrop partner…"* and the shop, with no application form and no `APPLICANT` added.
6. With the provider disabled, open the app. Expect: no Google button on Create Account, and the
   sign-in screen's Google button says "Google sign-in is coming soon." — no sheet, no browser.
7. `redirect_uri_mismatch` on Google's page means step 1's redirect URI does not match the host the
   app used, character for character.

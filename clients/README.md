# Flutter clients

Three surfaces from one monorepo (Section 9): a role-based mobile app, and two Flutter Web portals.

```
clients/
├── packages/
│   ├── delivery_design_system/   # Appendix A tokens, ThemeData, status badge
│   └── delivery_core/            # Keycloak OIDC (web + mobile), Dio client, catalog API
└── apps/
    ├── mobile_app/               # Customer + Rider, branched on the role claim
    ├── backoffice_web/           # BACKOFFICE only — categories + live catalog
    └── merchant_portal/          # MERCHANT only — Phase 1 MVP
```

`packages/` is shared; `apps/` holds only the role-specific screens.

## Prerequisites

Flutter **3.44.9** (Dart 3.12.2) is installed at `C:\src\flutter` and is on your user PATH. A new
terminal picks it up automatically; in an existing one:

```bash
$env:Path = "$env:Path;C:\src\flutter\bin"
```

The backend must be running — see [`../infra/README.md`](../infra/README.md).

## Ports

| App | Port | Keycloak client |
| --- | --- | --- |
| Merchant Portal | **5010** | `merchant-portal` |
| Backoffice | **5011** | `backoffice-web` |
| Mobile app in Chrome | **5012** | `mobile-app` |

> **These ports are not arbitrary and must not drift.** A Keycloak client's redirect URIs are an
> allow-list, and `flutter run` picks a *random* port unless told otherwise — which fails the
> `redirect_uri` check on every run with a Keycloak error page. Always pass `--web-port`.
>
> They are 50xx rather than 80xx because the `lending` stack on this machine already holds
> 8080–8095.

## Running with hot reload (day to day)

```bash
cd clients/apps/merchant_portal && flutter run -d chrome --web-port 5010
```

```bash
cd clients/apps/backoffice_web && flutter run -d chrome --web-port 5011
```

The mobile app in a browser, for quick UI work:

```bash
cd clients/apps/mobile_app && flutter run -d chrome --web-port 5012 --dart-define=KEYCLOAK_ISSUER=http://localhost:8180/realms/delivery-platform --dart-define=API_BASE_URL=http://localhost:8100 --dart-define=OIDC_REDIRECT_URL=http://localhost:5012/
```

## Running the built bundles (no Flutter needed)

```bash
cd clients/apps/merchant_portal && flutter build web --release
```

```bash
cd clients && docker compose -f docker-compose.web.yml up -d
```

Serves Merchant Portal on <http://localhost:5010> and Backoffice on <http://localhost:5011> via
nginx. Rebuild then `docker compose -f docker-compose.web.yml restart` to pick up changes.

## Addressing: one host, three clients

Everything uses **`127.0.0.1`**. Not a LAN IP, and not the literal name `localhost`:

| | Why not |
| --- | --- |
| LAN IP (`192.168.x.x`) | Moves with DHCP, and needs an inbound Windows Firewall rule matching your network profile |
| `localhost` | Resolves to `::1` first, where Docker Desktop's `wslrelay` shadows the published port and resets the connection (`ERR_CONNECTION_RESET`) |
| `10.0.2.2` | Emulator-only, so the issuer it forces is unreachable from a desktop browser |

This matters more than it looks. **Keycloak stamps exactly one issuer into every token**, and a
token whose `iss` does not match what the services expect is rejected at the Gateway — which
presents as an auth bug, not an addressing one. One address for every client avoids that entirely.

`infra/.env` holds it:

```
KEYCLOAK_PUBLIC_URL=http://127.0.0.1:8180
MINIO_PUBLIC_ENDPOINT=http://127.0.0.1:9010
```

## Mobile app on the Android emulator

1. Start the emulator (`Pixel_Fold_API_35` already exists), or pick it in Android Studio.
2. **Run `infra/adb-reverse.ps1`.** This forwards the device's own loopback to the host's for 8100,
   8180 and 9010, which is what lets the app use the same `127.0.0.1` as the browser.
3. `flutter run` (or Run in Android Studio).

```powershell
.\infra\adb-reverse.ps1
```

> **Re-run it after every emulator reboot or reconnect** — `adb reverse` mappings do not survive
> either. Symptom if you forget: the app hangs on sign-in and then fails to connect, because it is
> trying to reach a port nothing is listening on inside the device.

`adb reverse` works on a USB-attached physical phone too, so the same setup covers a real device
without the firewall and DHCP problems below.

## Mobile app on a physical Android device over Wi-Fi (harder)

Open `clients/apps/mobile_app` in Android Studio, plug the phone in with USB debugging on, pick it
in the device dropdown, and Run. The Flutter plugin handles the rest.

### The address problem — read this first

A phone is not the host machine, and three separate things hand it URLs:

| | Wrong on a device | Correct |
| --- | --- | --- |
| API front door (Traefik) | `localhost` / `10.0.2.2` | `http://<LAN-IP>:8100` |
| Keycloak issuer | `localhost` / `10.0.2.2` | `http://<LAN-IP>:8180` |
| MinIO image URLs | `localhost` | `http://<LAN-IP>:9010` |

`localhost` on a phone is the phone. `10.0.2.2` is an emulator-only alias for the host. Miss any one
of the three and you get a different confusing symptom: the app can't sign in, or signs in but every
API call 401s, or works perfectly except every product photo is a broken thumbnail.

**All three are already wired to one variable.** This machine's Wi-Fi IP (`10.182.9.119`) is set in
`infra/.env`:

```
KEYCLOAK_PUBLIC_URL=http://10.182.9.119:8180
MINIO_PUBLIC_ENDPOINT=http://10.182.9.119:9010
```

and matched by the `--dart-define` defaults in `lib/main.dart`.

> **DHCP will move this IP.** When it does: update both values in `infra/.env`, run
> `docker compose up -d` in `infra/`, and pass the new host via Android Studio (**Run > Edit
> Configurations > Additional run args**) rather than editing `main.dart`:
>
> ```
> --dart-define=API_BASE_URL=http://NEW.IP:8100 --dart-define=KEYCLOAK_ISSUER=http://NEW.IP:8180/realms/delivery-platform
> ```
>
> Find the current one with `ipconfig`. The issuer is baked into every token, so a stale value fails
> validation at the Gateway rather than failing to connect — the error will look like an auth bug.

### Open the firewall (once, elevated PowerShell)

Windows Firewall is on and blocks these ports inbound, so the phone cannot reach the stack until
this is run. It is scoped to **private networks only** — do not widen it to `Any`:

```powershell
New-NetFirewallRule -DisplayName "Delivery dev stack (LAN)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8100,8180,9010 -Profile Private
```

Make sure Windows classifies your Wi-Fi as **Private**, not Public, or the rule won't apply. The
phone must be on the same Wi-Fi, and many guest/corporate networks block device-to-device traffic
entirely — if it still fails, that is usually why.

Sanity check from the phone's browser before debugging the app: open
`http://10.182.9.119:8180` — you should see the Keycloak page.

### Android specifics, already configured

- **Cleartext HTTP** is permitted only for local addresses via
  `android/app/src/main/res/xml/network_security_config.xml`. Android blocks plain HTTP from API 28
  onward; without it every call fails with *"Cleartext HTTP traffic to ... not permitted"*. The LAN
  IP is listed there too — **update it alongside `infra/.env` when the IP changes**, since Android
  does not accept CIDR ranges. Never add a public hostname.
- **`appAuthRedirectScheme`** in `android/app/build.gradle.kts` registers the intent-filter for
  `com.delivery.app://oauth2redirect`. Without it the browser tab reaches the redirect and silently
  stops, with no error anywhere — the login just appears to hang.

### Emulator instead

The same settings work on an emulator (it can reach the host's LAN IP too). An AVD named
`Pixel_Fold_API_35` already exists.

> A `flutter build apk` from this agent's shell fails with
> `java.io.IOException: Unable to establish loopback connection` — the sandbox blocks Gradle's
> daemon socket. Building from Android Studio, or from your own terminal, is unaffected.

## Dev users

| Username | Password | Lands on |
| --- | --- | --- |
| `merchant` | `merchant` | Merchant Portal — product list |
| `backoffice` | `backoffice` | Backoffice — categories + catalog |
| `customer` | `customer` | Mobile app — catalog browse |
| `rider` | `rider` | Mobile app — rider placeholder |

Signing into the Merchant Portal as `customer` correctly shows "not registered as a merchant" —
the role gate is real, and the API would 403 anyway.

## Auth: two implementations, one API

`flutter_appauth` is **mobile/desktop only — it has no web support at all.** So `AuthService` sits
on an `OidcClient` interface chosen by conditional import:

| | |
| --- | --- |
| `oidc_client_io.dart` | AppAuth drives a system browser tab |
| `oidc_client_web.dart` | Hand-rolled Authorization Code + PKCE redirect |

The web flow parks the PKCE verifier in `sessionStorage`, navigates the page to Keycloak, and
redeems the code on the *next* load — which is why `signIn()` returns `null` on web and the session
appears via `restore()`. Callers treat both the same: call `restore()` at startup, `signIn()` on a
button.

The PKCE maths lives in `pkce.dart` and is unit-tested against the **RFC 7636 Appendix B test
vector**, so the hand-rolled half is verified rather than hoped at.

## Phase 1 walkthrough

1. Merchant Portal (5010), sign in as `merchant` → **New product** → save.
2. **Add photo** → the browser PUTs the bytes *straight to MinIO*, never through the backend.
3. **Publish** — refused with a clear message until the product has an image.
4. Backoffice (5011) as `backoffice` → **Catalog** shows it; **Categories** lets you add one.
5. Mobile app as `customer` → the product appears in browse. As `rider` → the rider surface instead.

## Tests

```bash
cd clients/packages/delivery_core && flutter test
```

`delivery_core` covers role/`sub` claim parsing and PKCE; `delivery_design_system` locks every
Appendix A hex value; `merchant_portal` renders its list screen against canned API responses whose
shapes were copied from real `smoke-test.sh` output.

## Still open

- **State management.** Section 9 says Riverpod or Bloc, "pick one and enforce it via lint rules."
  **Neither is picked** — the screens use plain `StatefulWidget` so the choice is not made by
  accident. Decide before Phase 2, when ordering state gets genuinely complex.
- **Status badge colours.** Appendix A names them semantically; the hexes in `tokens.dart` were
  chosen here and need confirming at Phase 2 sign-off. The status→colour *mapping* is fixed.
- **Inter font files** are not bundled; the clients use the system fallback Appendix A permits.
- **iOS** is not scaffolded. `flutter create --platforms=ios` when there is a Mac to build on.

# The platform on k3s: dev and qa on one box

Two full environments — `delivery-dev` and `delivery-qa` namespaces — on a single-node k3s
cluster (8 cores / 24 GB / Contabo). Each namespace runs its own complete stack: Postgres,
Redis, RabbitMQ, MinIO, Keycloak, Vault (dev mode), mailpit, the Config Server and the thirteen
Spring services, all at **replicas: 1**. k3s's bundled Traefik is the one shared edge; the
per-environment hostnames are what keep the two apart on it.

| | dev | qa |
| --- | --- | --- |
| API | api-dev.youdrop.shop | api-qa.youdrop.shop |
| Keycloak | iam-dev.youdrop.shop | iam-qa.youdrop.shop |
| Portal | portal-dev.youdrop.shop | portal-qa.youdrop.shop |
| Ops tools | monitoring-dev.youdrop.shop | monitoring-qa.youdrop.shop |

All records point at the box's IP; TLS is ACME through the bundled Traefik
(`cluster/traefik-config.yaml`).

## Layout

```
cluster/traefik-config.yaml   # HelmChartConfig: ACME resolver, 80->443 redirect, acme.json PVC
base/                         # everything both environments share
  assets/                     # postgres init, keycloak realm+theme, minio/vault bootstrap
  configmap-common.yaml       # platform-common: the environment identical in dev and qa
  data-layer.yaml             # postgres, redis, rabbitmq, minio(+init Job), mailpit
  identity.yaml               # keycloak, vault(+init Job), config-server
  services.yaml               # the 13 Spring services (generated, replicas: 1)
  portal.yaml                 # nginx over /opt/delivery/sites/<env>/portal (hostPath)
overlays/dev, overlays/qa     # namespace, platform-env ConfigMap, ingress with the env's hosts
overlays/ingress.template.yaml  # single source for both ingress files
scripts/render-overlays.sh    # regenerates both ingress.yaml files from the template
scripts/gen-secrets.sh        # creates a new namespace's Secrets (run on the box)
scripts/rotate-secrets.sh     # replaces credentials in a running namespace, and proves it (on the box)
```

## Deploying (on the box)

```bash
rsync -a deploy/k3s/ root@<box>:/opt/delivery/k3s/
kubectl apply -f /opt/delivery/k3s/cluster/traefik-config.yaml
sh /opt/delivery/k3s/scripts/gen-secrets.sh delivery-dev
kubectl apply -k /opt/delivery/k3s/overlays/dev
# and the same pair with delivery-qa / overlays/qa
```

`gen-secrets.sh` mints fresh credentials per environment and refuses to overwrite existing ones —
regenerating passwords under stateful volumes would strand the data. See *Secrets, and rotating
them* below for what it creates and who reads each one.

## What to know

- **Vault is dev-mode and in-memory, but reboot-safe**: the `vault-reseed` sidecar in the vault pod
  re-seeds AppRole + policies + KV from `platform-secrets` on every pod start (and re-heals a vault
  container restart), and its readiness probe gates the vault Service until the seed reaches its
  completion marker. Nothing to do on reboot. All Vault state derives from `platform-secrets` (the
  datastore) — add new secret material there, never by hand in Vault (the reseed would overwrite it).
- **Mail goes to mailpit** (monitoring-<env>/mailpit, behind the ops basic-auth). Real SMTP means
  putting relay credentials in `platform-secrets` and pointing `SMTP_*` in `platform-common` at
  the relay — a deliberate act, since test data then reaches real inboxes.
- **Merchant Blitz reads shelf photos with sample data** until two deliberate acts, both per
  environment. (1) Give product-service the Claude API key in its own Secret, `anthropic-api` —
  never `platform-secrets`: every service imports that one whole, so a key there would sit in every
  pod on the platform. Only product-service references `anthropic-api` (an optional `secretKeyRef`
  in `base/services.yaml`), and `gen-secrets.sh` deliberately does not create it. Type the key in on
  the box rather than putting it in a manifest, a commit, a chat or your shell history:

  ```sh
  read -rs ANTHROPIC_API_KEY   # paste the key, press Enter; nothing is echoed
  printf %s "$ANTHROPIC_API_KEY" | kubectl -n delivery-dev create secret generic anthropic-api \
    --from-file=ANTHROPIC_API_KEY=/dev/stdin
  unset ANTHROPIC_API_KEY
  kubectl -n delivery-dev rollout restart deployment/product-service
  ```

  To rotate it, delete `anthropic-api` and repeat. (2) Select the provider: add
  `CATALOG_SCAN_VISION_PROVIDER=CLAUDE` to that overlay's `platform-env` literals. Either one alone
  changes nothing a merchant can see: CLAUDE without a key still answers with labelled samples, and
  a key without CLAUDE is never used. Each scan is a paid call once both are done; the per-merchant
  caps live under `delivery.catalog.scan` in product-service's `application.yml`.
- **Service-order attachments need their bucket once per environment.** The files customers attach
  to service orders live in the private `order-attachments` bucket, which `minio/bootstrap.sh`
  creates. A finished Job never runs again, whether Argo CD or `kubectl apply` applies it (the
  generated ConfigMaps keep their names). So the bootstrap Job's name carries a suffix, now
  `minio-init-3`: -2 added this bucket, and -3 moved the image to quay.io. The next sync creates the
  renamed Job, and the script runs once more in each environment. It is idempotent, so existing
  buckets and rules are left as they are. Bump the suffix whenever the script or its image changes.
  To confirm:

  ```sh
  kubectl -n delivery-dev logs job/minio-init-3 | grep order-attachments
  # and the same with delivery-qa
  ```

  The same apply routes `/order-attachments` on the API hostname (presigned requests only; MinIO
  refuses unsigned ones) behind `order-attachment-upload-limit`, which answers 413 to a body over
  10 MiB before MinIO stores a byte — keep it in step with order-manager's
  `delivery.attachments.max-size-bytes` — and hands order-manager its MinIO credentials from
  `platform-secrets`, as onboarding-service gets them; the Vault seed carries them too from the next
  vault pod start. order-manager's image must be built against platform-storage 0.1.3, published to
  GitHub Packages.
- **Applicant documents reach storage the same way.** `/merchant-kyc` is routed on the API hostname
  like `/order-attachments` — prefix kept, presigned requests only, MinIO refusing unsigned ones —
  behind `merchant-kyc-upload-limit`, a 413 over 10 MiB (keep it in step with onboarding-service's
  `delivery.storage.minio.max-upload-size-bytes`). Until it was, every rider's and merchant's id,
  licence and registration upload met Traefik's own 404 and never reached MinIO. The bucket has
  existed since the first bootstrap, so the next sync of each overlay is the whole deployment. To
  confirm, an unsigned request must now get MinIO's XML `AccessDenied`, not `404 page not found`:

  ```sh
  curl -s -X PUT https://api-dev.youdrop.shop/merchant-kyc/probe   # and api-qa
  ```

  The storage routes, then: `product-images` and `apk` (public), `user-avatars`,
  `order-attachments` and `merchant-kyc` (private, presigned). `delivery-proof` and `receipts` stay
  unrouted because no service signs a URL into either yet; `scripts/verify.sh` checks both halves.
- **The demo logins** (customer/rider/merchant/backoffice/carrier) come from the realm import, and
  their passwords from the `demo-logins` Secret — see below.
- **The realm import runs only against a fresh database**, so a change to the realm file reaches an
  environment that already has one only by hand. The user profile now declares
  `onboardingApplicationId`, admin-only to view and to edit: onboarding-service stamps it on every
  account it makes for an applicant's passcode, and finishes an interrupted sign-up only on an
  account stamped for that application. Keycloak silently drops an undeclared attribute, so until
  dev and qa declare it an interrupted sign-up is refused with `account-exists` (safe, but it cannot
  be finished). Declare it with `scripts/rotate-secrets.sh <namespace> user-profile-stamp` (done on
  dev on 2026-09-19; qa gets it with its own rotation), or by hand in the admin console: Realm
  settings → User profile → Create attribute, name `onboardingApplicationId`, display name `Onboarding application`, not required,
  and only admins may view or edit it. (Do not run `infra/keycloak/apply-realm-updates.sh` here: it
  re-asserts the compose stack's dev client secrets.)
- **The identity settings the realm file now carries**, and how a running environment gets them.
  All of it is in the file for a fresh import; a live realm takes it from two idempotent steps,
  run in this order and not together:

  ```sh
  bash scripts/rotate-secrets.sh delivery-dev edge-identity      # safe for every installed build
  bash scripts/rotate-secrets.sh delivery-dev refresh-rotation   # LAST, and only once (see below)
  ```

  | | before | after |
  | --- | --- | --- |
  | `delivery-portal` password grant | on | off — the portal uses Authorization Code + PKCE, and a public client with direct access grants turns a phished password into a session |
  | `delivery-portal` `offline_access` | granted (realm default) | removed — it is what let the back office hold a token that never expires |
  | `delivery-portal` client session | the realm's 30 d idle / 90 d max | 8 h idle, 24 h max, which is also its refresh token's ceiling |
  | `delivery-portal` loopback redirect URIs | on both environments | dev only |
  | realm `sslRequired` | `none` | `external` |
  | realm refresh tokens | 30 days, reusable | rotated on every use, no reuse |
  | `mobile-app` web origins | `+` | `+` and `https://www.youdrop.shop`, which the site's receipt panel needs |

  **`refresh-rotation` is the one that can sign somebody out**, which is why it is separate and
  goes last. Under it a client that runs two refresh grants at once presents a token the server
  has already replaced, and Keycloak ends the session rather than refusing the one request. The
  client-side fix is in `delivery_core`'s `AuthService` (one grant at a time; see
  `auth_refresh_rotation_test.dart`), so run this only once the portal build being served and the
  APK people have installed both contain it. Realm-wide SSO stays 30 d / 90 d because it is the
  phones' session too — which is also why a portal user reaching the 8 h idle limit gets a silent
  PKCE round trip rather than a password prompt.
- **The Keycloak admin console is not public.** The edge refuses `/admin` on `iam-dev` and
  `iam-qa` (`overlays/ingress.template.yaml`, the `deny-public` middleware), which covers the
  console and the admin REST API; `/realms` is untouched, so authorize, token, JWKS, logout and
  the account console all still answer. `rotate-secrets.sh` reaches the admin API by
  port-forwarding to `svc/keycloak`, so it keeps working; every other script in the repository
  already used the in-cluster address. To use the console yourself:

  ```sh
  kubectl -n delivery-dev port-forward svc/keycloak 8080:8080   # then http://127.0.0.1:8080/admin
  ```
- **order-manager's image** is the one Docker Hub pull (its own repo/pipeline); everything else
  pulls public GHCR packages.
- **Every image is pinned, and `scripts/verify.sh` fails if one comes unpinned.** Two shapes are
  allowed: a digest (`repo:tag@sha256:…`) for infrastructure, and our own CI's immutable
  `sha-<40 hex>` tag for a service. Nothing may pull `:main`, `:latest`, `:qa`, `:develop` or a
  minor-version stream like `:3-management` — a pod restarting for an unrelated reason would come
  back on a build nobody chose, at an hour nobody picked, with no diff anywhere saying so. That is
  exactly how `minio:latest` turned into an outage when Docker Hub stopped serving the repository.
  Upgrading an infrastructure image is a deliberate edit of its digest; take a backup first if it
  has state behind it (Postgres, RabbitMQ and Keycloak all migrate their own data on start).
  **`overlays/qa` pins by digest, and those digests are a freeze, not a promotion** — they are what
  `:main` and `:qa` resolved to on 2026-09-20, so applying them does not change which build qa
  runs. Choosing the launch build means replacing them with the dev `sha-` tags, in a PR of its own.
- **The portal** serves whatever is under `/opt/delivery/sites/<env>/portal` on the node — sync a
  Flutter Web build there. `infra/deploy-portal.sh` has the shape of that build; the part that is
  not optional is:

  ```sh
  cd clients/apps/delivery_portal
  flutter build web --release --no-web-resources-cdn \
    --dart-define=KEYCLOAK_ISSUER="https://iam-<env>.youdrop.shop/realms/delivery-platform" \
    --dart-define=API_BASE_URL="https://api-<env>.youdrop.shop" \
    --dart-define=OIDC_REDIRECT_URL="https://portal-<env>.youdrop.shop/"
  ```

  `--no-web-resources-cdn` keeps CanvasKit on our own origin (`web/flutter_bootstrap.js` already
  points the loader at the local copy; this stops the build offering the gstatic one at all), and
  Rubik is bundled as an asset. Both matter now: the portal's CSP is `script-src 'self'
  'wasm-unsafe-eval'`, and a renderer fetched from an origin the policy does not allow leaves a
  blank page, not a degraded one. A build that overrides `MAP_TILE_URL` must also change the tile
  host in `overlays/ingress.template.yaml`; `scripts/verify.sh` fails if the two disagree.
- **The public website** (youdrop.shop apex) is not deployed here yet: its static build was never
  in the repository. Routes for it can join the template when the content exists.
- **probes are TCP**, matching what the compose stack verified; actuator-based HTTP probes are a
  cheap later upgrade if /actuator/health is permitted unauthenticated.

## Secrets, and rotating them

Until 2026-09 the public repository carried working credentials for dev and qa: the realm file's
service-account client secrets and demo passwords, the WhatsApp webhook secret and verify token
in `platform-common`, and the ops basic-auth hash in `gen-secrets.sh`. None of that is in git now;
`scripts/verify.sh` fails if it comes back. Each value lives in one Secret, on the box only:

| Secret | keys | read by |
| --- | --- | --- |
| `platform-secrets` | infrastructure passwords (Postgres, Redis, RabbitMQ, MinIO, Keycloak admin, Config Server, Vault), `SMTP_PASSWORD` | every Spring service (whole, via envFrom), the data layer, Vault, Keycloak |
| `keycloak-clients` | `ONBOARDING_CLIENT_SECRET`, `ACCOUNTING_CLIENT_SECRET`, `NOTIFICATIONS_CLIENT_SECRET` | Keycloak's first-boot import; each of those three services, its own key |
| `demo-logins` | `customer`, `rider`, `merchant`, `backoffice`, `carrier` | Keycloak's first-boot import; `scripts/e2e-smoke.sh` |
| `whatsapp-webhook` | `WHATSAPP_APP_SECRET`, `WHATSAPP_VERIFY_TOKEN` | whatsapp-service |
| `sms-dlr` | `SMS_DEV_DLR_SECRET` | sms-connector |
| `ops-auth-users` | `users` (an apr1 hash) | Traefik, for monitoring-<env> |
| `anthropic-api` | `ANTHROPIC_API_KEY` (optional, by hand) | product-service |

- **The realm file holds `${NAME}` placeholders**, which Keycloak fills from its own environment
  while it imports a realm at startup — and only then, only for a realm that does not exist yet.
  A placeholder it cannot resolve is imported as its own text, which is why every one is a
  non-optional `secretKeyRef` on the keycloak container. (The Google identity provider's
  `$(env:GOOGLE_CLIENT_ID)` is keycloak-config-cli syntax, not Keycloak's: the import keeps it
  literally, harmless while that provider is disabled.)
- **The demo logins' passwords**: six-digit passcodes for the four that sign in on the phone (the
  app accepts nothing else), a long password for backoffice, which signs in only through the
  portal's Keycloak page. Read one on the box, onto your own terminal:

  ```sh
  kubectl -n delivery-dev get secret demo-logins -o jsonpath='{.data.customer}' | base64 -d; echo
  ```

  `e2e-smoke.sh` reads the Secret itself (run it on the box). The Flutter live tests take
  `--dart-define=DEMO_<USER>_PASSWORD=...` (or `--dart-define-from-file`), never a value in git.
- **The ops password** is written by `gen-secrets.sh` (and `rotate-secrets.sh ops-auth`) to
  `/root/ops-auth-password-<env>.txt`, mode 600, user `ops`. Only its hash is in the Secret.
- **Never `kubectl apply` a Secret.** Apply copies every value into a
  `last-applied-configuration` annotation, which `kubectl describe` prints. Create, replace, patch.
- **Rotating** a value in a running environment is `scripts/rotate-secrets.sh <ns> <step>`, one
  step at a time: each checks its preconditions, changes one thing, restarts what reads it, and
  proves the new value works and the old one is refused. `gen-secrets.sh` never rotates anything.
- **Still in the repository, deliberately:** the per-service database roles' passwords, derived
  from the role name in `postgres-init/02-service-roles.sql` and repeated in `vault/bootstrap.sh`
  and two services' `application.yml`. Postgres answers only inside the cluster, and every Spring
  pod already holds the superuser password through `platform-secrets`, so they add little; replacing
  them means changing the roles, the Vault seed and two Deployments together — the production
  secrets refactor. The roles nothing logs in as cannot log in at all.

## Backups

Until now there were none: no CronJob, no WAL archive, and the k3s datastore that holds every
Secret was never copied off the box either. Three CronJobs (`base/backup.yaml`) change that. They
ship **suspended** and `overlays/qa` — the environment becoming production — is what runs them;
dev's data is demo data and dev's memory quota has no room for another pod.

| | when | what |
| --- | --- | --- |
| `postgres-backup` | hourly, :17 | `pg_dumpall --globals-only` + `pg_dump -Fc` of `delivery` and `keycloak`, encrypted with `age` in the pod, uploaded with rclone, **read back and size-checked**, then a dead-man ping |
| `minio-backup` | nightly, 02:40 | `rclone sync` of every bucket, skipping `product-images/scans/` |
| `restore-test` | Sunday 04:00 | restores into a throwaway Postgres **in its own pod** and checks Flyway versions and row counts against live |

All times UTC. Archive names are UTC timestamps, so sorting them by name sorts them by age.

### What the owner must provide

Nothing here is in git, nothing is invented by a script, and **until all of it exists every run
says what is missing and exits 0** — it does not crash-loop, and it does not ping the dead-man, so
`BackupNotConfigured` is what reports the state. On the box, per environment:

```sh
# 1. An age key pair. The PRIVATE half never comes near this cluster: it is the reason a stolen
#    backup is not a stolen database. Keep two copies, offline, in different places — lose it and
#    every backup ever taken is lost with it.
age-keygen -o /root/youdrop-backup.key      # then move it OFF this box
grep 'public key' /root/youdrop-backup.key  # age1...

read -rs AGE_RECIPIENT   # paste the age1... public key; nothing is echoed
printf %s "$AGE_RECIPIENT" | kubectl -n delivery-qa create secret generic backup-age \
  --from-file=recipient=/dev/stdin
unset AGE_RECIPIENT

# 2. The destination. Write rclone.conf with a remote called `dest`; `rclone config` is the easy
#    way, on any machine, then copy the file over. B2 is the plan's recommendation (S3 API, object
#    lock, cheap); R2 and a Hetzner Storage Box also work.
kubectl -n delivery-qa create secret generic backup-rclone \
  --from-file=rclone.conf=/root/rclone.conf \
  --from-literal=dest='dest:youdrop-backups'
shred -u /root/rclone.conf

# 3. OPTIONAL, and strongly recommended: the dead-man switch. Create a check at healthchecks.io
#    with a 2-hour period and a 30-minute grace, and put its ping URL here. NOT in a ConfigMap and
#    NOT in git: this repository is public, and anyone who can ping that URL can keep the switch
#    alive while the backups are dead.
read -rs HC_URL
printf %s "$HC_URL" | kubectl -n delivery-qa create secret generic backup-deadman \
  --from-file=url=/dev/stdin
unset HC_URL

kubectl -n delivery-qa create job --from=cronjob/postgres-backup backup-first-run
kubectl -n delivery-qa logs job/backup-first-run
```

**At the destination, set the bucket's lifecycle rules** — retention is enforced there, not by any
script, which is why the job writes to three prefixes:

| prefix | written | expire after |
| --- | --- | --- |
| `<ns>/postgres/hourly/` | every hour | **72 hours** |
| `<ns>/postgres/daily/` | at 03:17 UTC | **35 days** |
| `<ns>/postgres/monthly/` | at 03:17 on the 1st | **12 months** |
| `<ns>/minio/` | nightly (a mirror) | keep; rely on **object versioning** |

Two settings the scripts cannot check for you and that decide whether these are real backups:
**object versioning** (the MinIO job is a `sync`, so a deletion at the source propagates within a
day — versioning is the only thing that keeps the previous copy) and **object lock**, so a
compromise of these credentials cannot delete the history.

`merchant-kyc` holds applicants' identity documents and today is synced as-is. If the destination
is not one you would put those in, point `dest` at an **rclone `crypt` remote** wrapping it: the
jobs only ever use the remote name, so nothing here changes.

### Restoring

`scripts/restore.sh <namespace> <step>`, on the box, one step at a time. The order matters and
`dry-run` is not optional:

```sh
bash scripts/restore.sh delivery-qa list                  # what is there, and how old
bash scripts/restore.sh delivery-qa fetch latest          # download one archive; no decryption
bash scripts/restore.sh delivery-qa open  /root/restore-… # asks for the path to your age key
bash scripts/restore.sh delivery-qa dry-run /root/restore-…   # into a scratch DB, beside live
bash scripts/restore.sh delivery-qa into-live /root/restore-… # the irreversible one
bash scripts/restore.sh delivery-qa minio product-images  # objects, by bucket or `all`
```

- `open` never takes the key on a command line; it asks for the **path** to the key file.
- `dry-run` restores into `delivery_restore_<time>` in the running Postgres, compares Flyway
  versions and row counts against live, and drops it again. **Read the Flyway line.** Restoring an
  older schema under the current service images starts services that then fail their migration
  check, and Flyway does not migrate backwards.
- `into-live` refuses while anything is running (`kubectl -n <ns> scale deploy --all --replicas=0`
  first), asks you to type the namespace back, and **renames** the databases it replaces to
  `delivery_before_restore` / `keycloak_before_restore` rather than dropping them. Everything
  written since the backup was taken is gone; if the data is not actually corrupt, fix forward.
- `minio` uses `copy`, never `sync`: it adds and overwrites, and never deletes what is live.

**Run one full drill before go-live**, with the real offline key, and time it. RPO is one hour
(the schedule) and RTO is about two (fetch, decrypt, restore, restart). The weekly `restore-test`
proves the path automatically but runs in its **dump-only** mode unless a second age identity is
put in `backup-age/restore-test.key` — the private key being offline is exactly why it cannot
decrypt a real archive on its own. It says which mode it ran in its log.

### What is not backed up, deliberately

Redis (a cache), RabbitMQ (transient; the outbox republishes), `product-images/scans/` (Merchant
Blitz input — once a scan has produced products the photograph can be taken again), and **the k3s
datastore**, which holds every Secret. That last one is a real gap: `gen-secrets.sh` can mint a new
environment's credentials, but a restore into a *fresh* namespace needs the Keycloak client secrets
and the database passwords that the old one held, or nothing signs in. Copy `/var/lib/rancher/k3s/
server/db/` off the box on the same schedule, or keep `rotate-secrets.sh <ns> backup`'s output
(`/root/secret-backup-<ns>-<time>/`) somewhere off it.

## One node, two environments: what happens under memory pressure

The box is 8 vCPU / **23 GiB with no swap**, and it runs dev and the environment that becomes
production side by side. Before this section existed, the two namespaces' memory *limits* added up
to 106% of the node with nothing to separate them.

Three things now decide who survives, and they act in this order:

1. **Admission.** `overlays/dev/resource-safety.yaml` caps delivery-dev at **9 GiB of limits and 6
   GiB of requests**. A pod that would take dev past either is refused when it is created, with the
   arithmetic in its event — `kubectl -n delivery-dev describe replicaset <name>` is where that
   shows up, not in the Deployment. There is no quota on the production namespace: a pod refused at
   admission during an incident is worse than a node under pressure.
2. **Scheduling.** `cluster/priority-classes.yaml` gives the production namespace `prod-critical`
   (1000000) and dev `dev-standard` (100, `preemptionPolicy: Never`). A production pod that cannot
   be placed will evict dev pods to make room; a dev pod that cannot be placed **waits**, visibly
   Pending, and takes nothing from production.
3. **Eviction.** When the kubelet crosses its memory threshold it ranks pods by QoS class, then by
   how far each is over its *request*, then by priority. Production's Postgres now requests exactly
   what it may use (1536Mi = 1536Mi), so it scores as a process inside its budget rather than one
   800 MiB over it, and dev's lower priority breaks every remaining tie against dev.

**dev is at 8.875 of its 9 GiB.** That is about 128 MiB of headroom — room for nothing. To fit,
dev's fourteen Spring services run at a 416Mi limit rather than 512Mi, with `MaxRAMPercentage=60`
instead of 70 so the space *outside* the heap grows (~166Mi, against ~154Mi today) while the heap
ceiling falls (250Mi, from 358Mi). They idle at 160-350 MiB of RSS, so the trade is more frequent
collection for more native headroom — the native side being what actually OOMKills a container.

> **This is the one change on this branch that has not been measured against a running service.**
> Apply it to dev, then watch for a day:
>
> ```sh
> kubectl -n delivery-dev get pods --sort-by=.status.containerStatuses[0].restartCount
> kubectl -n delivery-dev get events --field-selector reason=OOMKilling
> ```
>
> If anything restarts with `OOMKilled`, the way back is three numbers, all in
> `overlays/dev/`: `416Mi` → `512Mi` and `MaxRAMPercentage=60` → `70` in `kustomization.yaml`, and
> `limits.memory: 9Gi` → `11Gi` in `resource-safety.yaml`. dev is then exactly as it was.

When dev next needs *anything* the quota will refuse it, and that is the quota working. The answer
is the plan's own (item 7): **dev moves to its own VPS**. Raising the 9 GiB instead takes the room
back out of production.

`base/network-policies.yaml` is the other half: a default-deny on **ingress** in both namespaces,
with exceptions for the namespace itself, kube-system (Traefik, or every hostname answers with a
gateway error) and monitoring (the scrapes). Egress is deliberately untouched — a default-deny
there would also deny DNS, the M365 relay and every outbound connector call, and would look like an
application bug. The property bought is that **delivery-dev cannot open a connection into
delivery-qa**, which matters because every pod in both namespaces holds its own Postgres superuser
password and the two differ only by hostname. If k3s was started with `--disable-network-policy`
these objects are accepted and enforce nothing, silently; `scripts/rotate-secrets.sh <ns>
netpol-proof` opens the connections they forbid and reports what actually happened.

## The connection budget

Postgres allows 200 connections, three of them reserved for superusers, so **197 are usable per
environment** (dev and qa each run their own instance). Eleven services hold independently-sized
Hikari pools with nothing between them and the database:

| | max | idle floor |
| --- | --- | --- |
| order-tracking | 15 | 3 |
| onboarding-service | 12 | 3 |
| accounting, app-notification, notifications-manager, order-manager, product, whatsapp | 10 each | 2 each |
| transfer-service | 5 | 1 |
| connector-settings | 4 | 1 |
| config-server | 2 | 1 |
| **total** | **98** | **21** |

**Every pool names `minimum-idle`, and that is not decoration.** Hikari defaults the idle floor to
the MAXIMUM, so a pool that does not name one never shrinks and its ceiling becomes its permanent
footprint. Three services were in that state and held 10, 5 and 2 connections around the clock
between them for work measured in milliseconds.

The ceiling is what decides whether this platform can run **two replicas of everything**: 98 x 2 =
196 against 197 usable, which fits and leaves nothing. A third replica, or a new service, needs
either a raised `max_connections` (each backend costs roughly 10 MB of the box's memory) or a
connection pooler in front. There is no pooler today. Failure is not graceful — a service that
cannot get a connection blocks for Hikari's 30-second timeout, and the losers are whichever
services start last rather than whichever matter least.

## Monitoring

`scripts/setup-monitoring.sh` installs `cluster/monitoring.yaml` — one Prometheus and one Grafana
in the `monitoring` namespace, watching both environments. **Run it again after `gen-secrets.sh`
creates or rotates an environment's `platform-secrets`**: it copies that environment's Config
Server basic-auth login into the `config-server-scrape` Secret, and the scrape job cannot
authenticate without a current copy.

Grafana's datasources are provisioned from that file and provisioning is the only place they may
be added. A datasource created by hand in the UI is invisible to every review and survives every
redeploy; the only way to remove one is to name it under `deleteDatasources`, which the file now
does for the `jaeger` datasource somebody added against a tracing backend this platform does not
run.

## Alerting

Until now nothing paged. Prometheus evaluated its rules, marked them firing, and told nobody —
there was no Alertmanager to tell. `cluster/alerting.yaml` adds the three pieces that were missing
and `scripts/setup-monitoring.sh` installs them alongside Prometheus and Grafana:

| | what it adds |
| --- | --- |
| **Alertmanager** | groups, de-duplicates and **emails** what Prometheus fires, through the M365 relay |
| **node-exporter** | the box itself: disk, memory, load — the numbers no container can see |
| **kube-state-metrics** | the API server's view: crash loops, failed Jobs, CronJob outcomes |

Traefik's own metrics are switched on too (`cluster/traefik-config.yaml`), which is where the 5xx
rate, the 429 rate and **certificate expiry** come from, and each environment gets a
`postgres-exporter` for the connection count.

Alerts go to **one email address**, set in `cluster/alerting.yaml` under `receivers`. Changing it
is a one-line edit plus `setup-monitoring.sh`, and it is worth checking twice: an address nobody
reads is the same as no alerting at all. The relay password is **not** in that file — it is copied
out of an environment's `platform-secrets` into `alertmanager-smtp` by `setup-monitoring.sh` and
read at send time from a mounted file.

`page` means money in the wrong place or an environment that is down; it repeats hourly. Everything
else repeats every four hours, and anything from `delivery-dev` once a day.

**Telegram is off by being absent, not by a switch.** Alertmanager validates its whole
configuration at startup and refuses to start on a half-filled receiver — a placeholder `chat_id`
would take monitoring down. The receiver is written out, commented, with the three steps to enable
it, at the end of `cluster/alerting.yaml`.

### The rules

| alert | fires when |
| --- | --- |
| `NodeMemoryCritical` / `NodeMemoryLow` | under 10% / 20% of the node's memory available |
| `NodeDiskFilling` / `NodeDiskCritical` | a filesystem over 80% / 92% |
| `PodCrashLooping`, `ContainerOOMKilled`, `JobFailed`, `DeploymentNotReady` | the workload is not running |
| `BackupNotConfigured`, `BackupDidNotReport`, `MinioBackupDidNotReport` | nothing is being backed up |
| `RestoreTestFailing`, `RestoreTestStale` | the backups cannot be turned back into a database |
| `CertificateExpiringSoon` / `Critical` | under 14 / 5 days of certificate left |
| `HighServerErrorRate` | over 2% of requests answering 5xx for ten minutes |
| `RateLimitRejectionsHigh` | over 1 req/s being 429'd — likely real users behind CGNAT |
| `PostgresConnectionsHigh` / `Climbing` | over 170 / 140 of the 197 usable connections |
| `SmsRateHigh` | over 200 SMS in an hour — the warning before the provider's spend cap |
| `SettlementFailuresRecorded` | any unresolved settlement failure (RECON-04) |

The backup alerts read **node-exporter's textfile collector**: a CronJob is gone by the time
anything could scrape it, so each job writes a `.prom` file into
`/var/lib/node-exporter/textfile` and node-exporter serves it until it is replaced.
`youdrop_restore_test_ok` is the single most important number here — it is the difference between
having backups and believing you have them.

**Two rules are written and waiting on a metric that does not exist yet**: `SmsRateHigh` needs
`delivery.sms.sent` in sms-connector, and `SettlementFailuresRecorded` needs
`delivery.settlement.failures` in accounting-service (the `settlement_failure` rows are recorded,
but nothing gauges them). `scripts/verify.sh` lists them as PENDING so the gap cannot be forgotten;
when each metric lands, deleting its name from `PENDING_METRICS` in that script is the whole edit.

### Proving an alert really arrives

Do this once, after `setup-monitoring.sh`, and again after changing the address. Every step below
is reversible and nothing production depends on it.

```sh
# 1. Prometheus knows where to send. Expect one alertmanager with health "up".
kubectl -n monitoring exec deploy/prometheus -- \
  wget -qO- http://localhost:9090/api/v1/alertmanagers

# 2. Alertmanager can reach the relay. Fire a synthetic alert straight at it — this skips
#    Prometheus and tests only the delivery path, which is the part that is usually broken.
kubectl -n monitoring exec deploy/alertmanager -- sh -c 'wget -qO- --post-data="[{
  \"labels\": {\"alertname\":\"AlertingPathTest\",\"severity\":\"page\",\"namespace\":\"delivery-qa\"},
  \"annotations\": {\"summary\":\"If you are reading this, alerting works.\"}
}]" --header="Content-Type: application/json" http://localhost:9093/api/v2/alerts'

# 3. The email should arrive within a minute (severity page has group_wait 0s). If it does not:
kubectl -n monitoring logs deploy/alertmanager --tail=50 | grep -i 'smtp\|notify'
#    "authentication failed" -> alertmanager-smtp is stale; re-run setup-monitoring.sh
#    "no such host"          -> the pod cannot reach smtp.office365.com; check egress
#    nothing at all          -> the alert never reached Alertmanager; go back to step 1

# 4. Clear it. Synthetic alerts expire on their own after 5 minutes, or:
kubectl -n monitoring exec deploy/alertmanager -- \
  amtool --alertmanager.url=http://localhost:9093 silence add alertname=AlertingPathTest -d 10m -c "path test"
```

To test the whole chain including Prometheus, stop a scrape target and wait fifteen minutes for
`ScrapeTargetDown` — `kubectl -n delivery-dev scale deploy/mailpit --replicas=0`, then scale it
back. Use **dev** for that, never the environment that is becoming production.

**What none of this covers:** an alert about this box, sent from this box, does not arrive when the
box is what failed. The backup job's dead-man switch and an **external uptime monitor** on
api/iam/portal/www are the only things that notice that, and neither lives in this repository.

Alert rules live in the `prometheus-rules` ConfigMap, in three files: `settlement.yaml`,
`platform.yaml` and `infrastructure.yaml`.

## Draining a dead-letter queue

A notification that exhausts its retries is *parked*, not dropped: `DeadLetterPublisher` publishes
the whole command plus the reason it failed onto `notification.dlq` through the default exchange.
That queue is bound to nothing and has no consumer **on purpose** — it is a parking lot, and the
bodies in it are the only record of what was never sent. `NotificationDeadLettersParked` fires
while it is non-empty.

Read it without consuming it (`reject_requeue_true` puts every message back):

```bash
NS=delivery-dev
U=$(kubectl -n $NS get secret platform-secrets -o jsonpath='{.data.RABBITMQ_USER}' | base64 -d)
P=$(kubectl -n $NS get secret platform-secrets -o jsonpath='{.data.RABBITMQ_PASSWORD}' | base64 -d)
# Through env, not argv: the broker password would otherwise stand in the pod's process list.
kubectl -n $NS exec rabbitmq-0 -- env RU="$U" RP="$P" sh -c \
  'rabbitmqadmin -u "$RU" -p "$RP" -f raw_json \
     get queue=notification.dlq count=100 ackmode=reject_requeue_true'
```

`count` is a ceiling, not a page: each result carries `message_count`, the number still behind the
last one returned, so raise it until that reaches zero.

Each message is `{"command": …, "reason": …}`. The same reason is on an `x-dead-letter-reason`
header, alongside `x-dead-lettered-at` and `channel`; `message_id` is the idempotency key and
`correlation_id` is the correlation id of the request that caused it, so a body can be traced back
to a log line. All of that is kept out of the body precisely so the command can be replayed
unchanged.

The reason says which of three things happened, and they want different responses:

- a preparer's rejection (`recipient is not a valid E.164 number: …`, `empty email body`,
  `payload exceeds the FCM 4KB limit`) — the command is malformed and replaying it changes nothing;
- `connector unreachable: …` or a provider error — retries were exhausted against something that
  was down, and a replay after it is back is the whole point of keeping the body;
- `worker error: …` — a bug in the worker itself, so the message is evidence for a fix rather than
  something to resend.

To retry one once the cause is fixed, publish its `command` object back onto the dispatch queue
for its channel (`notification.dispatch.email` / `.sms` / `.push` / `.in_app`); the idempotency
key travels with it, so a message that did in fact go out will not go out twice.

**Do not purge until the messages have been read and their reasons recorded.** A purge is the one
irreversible operation here, and it destroys the evidence of an outage rather than the outage.


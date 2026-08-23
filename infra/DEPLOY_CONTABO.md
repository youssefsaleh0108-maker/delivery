# Deploying the dev environment to Contabo

One environment, named `delivery-dev`, for testing. Docker Compose, no Kubernetes.

Everything below runs on the box. `docker-compose.dev.yml` is the file; `docker-compose.yml`
remains the laptop stack and is not used here.

---

## Read this first: it does not fit in RAM

The ceilings in `docker-compose.dev.yml` sum to **5.72 GiB** across 22 services. With the Docker
daemon and the OS that is about **6.1 GiB**. The box reports:

```
Mem:  5.8Gi total,  5.3Gi available
Swap: 0B
```

**Roughly 800 MiB short, and no swap to absorb it.** Started as-is on a box in that state, the
kernel begins OOM-killing containers partway through the first `up`, and which ones die is decided
by whatever it reaches first rather than by what matters.

The ceilings were cut a tier each to get here — they were 6.72 GiB. They are now close enough to
what these services actually use that trimming further trades swap slowness for OOM kills, which is
the worse of the two: a slow service is diagnosable and a killed one looks like a crash.

There are 93 GB free on `/`, so swap covers the rest cheaply:

```bash
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo "/swapfile none swap sw 0 0" >> /etc/fstab
```

Be clear about what that buys. Swap stops the OOM killer; it does not make the platform fast. JVM
heap paged to disk means GC pauses measured in seconds. For a test environment where you exercise
one flow at a time and most services idle, that is a reasonable trade — the idle ones get paged out
and stay there. Under concurrent load across many services it will thrash.

Two honest alternatives:

- **Resize the box.** 16 GB runs this with headroom and no swap. Everything below is unchanged.
- **Run less of it.** The ordering path — data layer, Config Server, Traefik, product, orders,
  tracking — sums to **3.00 GiB** and fits the box as it stands, no swap needed:

  ```bash
  docker compose -f docker-compose.dev.yml --env-file .env up -d \
    postgres redis rabbitmq keycloak minio minio-init vault vault-init \
    config-server traefik product-service order-manager order-tracking
  ```

  Compose starts the `depends_on` graph for whatever you name, so this is a complete, working
  subset rather than a broken partial. Add the notification or accounting services when you want to
  test those, and watch `free -m` as you go — each is 256–384 MiB.

---

## 1. Docker

```bash
curl -fsSL https://get.docker.com | sh
```

Log in to Docker Hub — the images are private, and without this every pull fails with a message
that reads like the tag does not exist:

```bash
docker login -u youssefsaleh0108
```

## 2. Firewall

Three ports face the internet by design. Nothing else should.

```bash
ufw default deny incoming
ufw allow 22/tcp
ufw allow 8100/tcp    # Traefik — the API
ufw allow 8180/tcp    # Keycloak — clients authenticate directly against it
ufw allow 9010/tcp    # MinIO — presigned image URLs are fetched by the browser
ufw enable
```

Keycloak and MinIO are public because clients reach them **directly**, not through Traefik. Routing
Keycloak through 8100 breaks the `iss` claim; routing MinIO through it breaks the presigned
signature.

**ufw alone does not close Docker's published ports.** Docker writes its own iptables rules into the
`DOCKER` chain, which is traversed before ufw's `INPUT`, so a `ufw deny` on a published port does
nothing. This is the single most likely way this box ends up exposed.

Two things close it properly. First, this compose file publishes only 8100, 8180 and 9010 to
`0.0.0.0` — everything else is either internal to the network or bound to `127.0.0.1`, which Docker
honours. Second, a belt-and-braces rule in `DOCKER-USER`, the chain Docker leaves for exactly this
and never rewrites:

```bash
# Allow the three public ports and anything already established; drop the rest before it reaches
# a container. Replace eth0 if your public interface is named differently — check `ip route`.
iptables -I DOCKER-USER -i eth0 -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -I DOCKER-USER -i eth0 -p tcp -m multiport --dports 8100,8180,9010 -j RETURN
iptables -A DOCKER-USER -i eth0 -j DROP
```

Order matters: `-I` inserts at the top, `-A` appends, so the two RETURNs are evaluated before the
DROP. Persist with `iptables-persistent`.

Then confirm from somewhere else — do not assume either of the above worked:

```bash
nmap -p 5433,6380,8101-8117,8888,15673,8200 <box-ip>
```

Every one should be filtered or closed. Anything open on 8110–8112 is a connector, and
`/api/connector/send` takes no user token: an open port there is "send an arbitrary SMS" for anyone
who finds the IP.

## 3. The repository and the environment file

```bash
git clone https://github.com/youssefsaleh0108-maker/delivery.git
cd delivery/infra
cp .env.dev.example .env
nano .env
```

Fill in every blank. `openssl rand -base64 24` for each password.

The three that decide whether clients work at all:

| | |
| --- | --- |
| `PUBLIC_HOST` | the box's IP |
| `KEYCLOAK_PUBLIC_URL` | `http://<ip>:8180` — becomes the `iss` claim of every token |
| `MINIO_PUBLIC_ENDPOINT` | `http://<ip>:9010` — what presigned image URLs are signed for |

Leave either URL as `localhost` and the API works from the box while every browser and phone fails:
login redirects nowhere, images 403. This is the single most common way this deployment goes wrong.

## 4. Start it

```bash
docker compose -f docker-compose.dev.yml --env-file .env pull
docker compose -f docker-compose.dev.yml --env-file .env up -d
```

The first `pull` moves about 4 GB. Start order is handled by `depends_on` with health conditions —
Postgres, then Config Server, then everything else. Nothing starts before the Config Server is
healthy, because nothing can resolve its configuration without it.

Watch it settle:

```bash
watch docker compose -f docker-compose.dev.yml ps
```

On a swapped box expect several minutes. A service restarting once or twice while its neighbours
are still booting is normal; one in a restart loop after ten minutes is not.

## 5. Verify

```bash
# Config Server resolves properties from Postgres, not Git. Empty propertySources means the
# database backend is not matching — check the label and the seed.
curl -u config:<CONFIG_SERVER_PASSWORD> http://localhost:8888/product-service/docker

# Traefik is routing
curl -i http://localhost:8100/api/products

# The full suite, from inside the network. The network is named `delivery`, not the
# `delivery-dev_delivery` compose would derive — the file pins it explicitly.
docker run --rm --network delivery -v "$PWD/smoke-test.sh:/smoke.sh:ro" \
  alpine:latest sh -c "apk add --no-cache curl jq >/dev/null && sh /smoke.sh"
```

The smoke suites now target `http://traefik:8100`, so this is the first real test of the Traefik
routing — it was the Spring gateway that answered before. Expect it to surface anything
`traefik/dynamic/routes.yml` gets wrong.

## 6. Updating

```bash
docker compose -f docker-compose.dev.yml --env-file .env pull
docker compose -f docker-compose.dev.yml --env-file .env up -d
```

`IMAGE_TAG` defaults to `main`, so a pull takes whatever CI last pushed. Pin it to a `sha-` tag in
`.env` to hold a known-good build across restarts.

---

## What this environment is not

- **Vault is `-dev`** — in-memory, fixed root token, every secret lost on restart.
- **No TLS.** Everything above is plain HTTP, including the login flow, on a public IP.
- **No backups.**
- **It sends real email.** Mailpit is not deployed; the relay in `.env` is a real one, so a bad
  recipient in test data reaches an actual mailbox. The SMS dev-passthrough provider mails every
  simulated message there too.
- **There is no bank.** The Core Banking connector and simulator are both gone. Settlement runs in
  `LEDGER_ONLY` mode: the ledger records who is owed what and every leg is terminal as it is
  written. Merchants and riders are paid in points they redeem, and a redemption is a request an
  operator approves and pays by hand — nothing in the platform moves money.
- **Cash on delivery only.** Checkout refuses CARD with a 400 — it parks at AUTHORIZATION_PENDING
  with no provider to authorise it and would never settle. `delivery.ordering.payment-methods` is
  the switch; add CARD back once a provider exists.
- **The points screens do not exist.** The API is live at `/api/points`; no client calls it, so
  balances and redemptions are reachable only with `curl`.

Do not put real customer data in it.

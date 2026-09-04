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
scripts/gen-secrets.sh        # creates platform-secrets in a namespace (run on the box)
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
regenerating passwords under stateful volumes would strand the data. The one value it does not
invent is the onboarding client secret, which must match what the realm import creates.

## What to know

- **Vault is dev-mode and in-memory**: after a vault pod restart, re-run its seeding —
  `kubectl -n <ns> delete job vault-init && kubectl apply -k overlays/<env>`.
- **Mail goes to mailpit** (monitoring-<env>/mailpit, behind the ops basic-auth). Real SMTP means
  putting relay credentials in `platform-secrets` and pointing `SMTP_*` in `platform-common` at
  the relay — a deliberate act, since test data then reaches real inboxes.
- **The demo logins** come from the realm import: customer/rider/merchant/backoffice/carrier.
- **order-manager's image** is the one Docker Hub pull (its own repo/pipeline); everything else
  pulls public GHCR packages.
- **The portal** serves whatever is under `/opt/delivery/sites/<env>/portal` on the node — sync a
  Flutter Web build there (see infra/deploy-portal.sh for the shape of that build).
- **The public website** (youdrop.shop apex) is not deployed here yet: its static build was never
  in the repository. Routes for it can join the template when the content exists.
- **probes are TCP**, matching what the compose stack verified; actuator-based HTTP probes are a
  cheap later upgrade if /actuator/health is permitted unauthenticated.

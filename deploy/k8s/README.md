# Kubernetes manifests

**These have never been applied to a cluster.** Section 12's open decision #2 leaves the staging
Kubernetes target and its credentials unassigned, so there is nothing here to deploy against. They
are written from the compose stack that *is* verified, and they will need a real `kubectl apply`
before anyone trusts them — treat them as a reviewed starting point, not as tested infrastructure.

What that means concretely: the YAML is syntactically valid and the values in it match the running
system, but image pull, secret injection, probe timing under a cold cluster and PVC provisioning are
all unexercised.

## The one thing not to copy from compose

`infra/docker-compose.yml` publishes every service port to the host, 8101–8115. That is a dev
affordance and it is the most dangerous thing to carry into a cluster: it would expose
`/api/connector/send` — "send an arbitrary SMS", no token required — and the Core Banking
Simulator's `/test/faults` to anything that can reach a node.

So: **every Service here is `ClusterIP`**, and exactly one component is meant to be reachable from
outside. The security review (`docs/SECURITY_REVIEW.md`, finding 3) records why.

That component used to be the Spring API Gateway. It has been removed — Traefik took port 8100 in
compose and routes straight to the backing services, leaving the gateway outside the request path
(`infra/traefik/dynamic/routes.yml`). **Traefik has no manifest here yet**, so as things stand this
directory describes a namespace with no ingress at all. Writing that manifest is the next piece of
work, and `namespace.yaml`'s `allow-traefik-ingress` policy already selects `app: traefik` for it.

The Core Banking Simulator has no manifest at all. It is dev-only by design (Section 7), and the
absence is deliberate rather than an omission — in staging and production the same connector points
at the real bank through the Backoffice toggle.

## Layout

```
deploy/k8s/
├── namespace.yaml                # namespace + the three NetworkPolicies
├── base/
│   └── configmap-common.yaml     # the non-secret environment every service shares
├── domain-services.yaml          # product, order-manager, order-tracking
└── notification-services.yaml    # manager, 3 workers, 3 connectors, app-notification,
                                  # connector-settings, accounting-service, corebanking-connector
```

Three earlier entries in this list did not describe the directory and have been corrected rather
than left to mislead: `gateway.yaml` is gone with the service it deployed, `base/secrets.example.yaml`
was documented below but never written, and `accounting-services.yaml` never existed — accounting
and the Core Banking connector live in `notification-services.yaml`.

**Still missing a Deployment entirely:** `config-server`, which every other service reaches through
`CONFIG_IMPORT` and without which none of them boot; `whatsapp-service` and `onboarding-service`,
both added after this pass; Traefik, as above; and the whole data layer — Postgres, Redis, RabbitMQ,
Keycloak, MinIO and Vault are all named in `base/configmap-common.yaml` and none of them are
objects here.

## Secrets

Section 6 routes every service's secrets through the Config Server's Vault composite, so in a
cluster the only credential a service needs is the Config Server's, and the Config Server's own
AppRole is injected by the platform (the Vault Agent injector or CSI driver, depending on what the
cluster runs).

A `base/secrets.example.yaml` documenting which keys each service expects — shape only, no values —
was described here but never written. Note that `domain-services.yaml` and `notification-services.yaml`
already read a Secret named `config-server-client`, and nothing in this directory creates it.

## Resource limits and autoscaling

Section 10 asks for per-Deployment resource limits and an HPA "where relevant", naming Order
Tracking and the notification workers. Those are the three with an HPA here, and the reasoning is in
the load test rather than guessed:

- **Order Tracking** takes a write per active rider every few seconds and measured ~322 pings/s per
  instance before saturating (`docs/LOAD_TEST.md`, run B). It scales on CPU.
- **The notification workers** are stateless competing consumers on per-channel queues, which is the
  shape that scales cleanly. Queue depth would be the better signal than CPU, but that needs KEDA
  or a custom metrics adapter; CPU is the honest placeholder until one is available.

**App Notification deliberately has no HPA and is pinned to one replica.** It holds STOMP
connections in an in-memory broker, so a second instance would serve some users notifications and
others silence depending on which pod they landed on. Scaling it needs a shared relay first — this
is recorded in the README's deviations and the replica count enforces it rather than leaving it to
be discovered.

Requests and limits are starting points sized from what the containers actually used on the laptop,
not from a formula. They should be revisited against a real cluster's metrics.

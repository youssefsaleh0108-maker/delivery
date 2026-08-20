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

So: **every Service here is `ClusterIP` except the API Gateway**, which is the only intended
ingress. The security review (`docs/SECURITY_REVIEW.md`, finding 3) records why.

The Core Banking Simulator has no manifest at all. It is dev-only by design (Section 7), and the
absence is deliberate rather than an omission — in staging and production the same connector points
at the real bank through the Backoffice toggle.

## Layout

```
deploy/k8s/
├── namespace.yaml
├── base/
│   ├── configmap-common.yaml     # the non-secret environment every service shares
│   └── secrets.example.yaml      # SHAPE ONLY - real values come from Vault, see below
├── gateway.yaml                  # the only externally reachable Service
├── domain-services.yaml          # product, order-manager, order-tracking
├── notification-services.yaml    # manager, 3 workers, 3 connectors, app-notification
└── accounting-services.yaml      # accounting-service, corebanking-connector
```

## Secrets

`secrets.example.yaml` contains no real values and is not applied. Section 6 routes every service's
secrets through the Config Server's Vault composite, so in a cluster the only credential a service
needs is the Config Server's, and the Config Server's own AppRole is injected by the platform (the
Vault Agent injector or CSI driver, depending on what the cluster runs). The example file exists to
document which keys each service expects, not to hold them.

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

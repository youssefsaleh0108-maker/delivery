# Local infrastructure

Everything in this directory is **local development only**. Section 10 requires the Keycloak realm,
Postgres schemas, MinIO bucket policies, message-bus topology and the Config Server's Vault AppRole
binding to be defined in Terraform for real environments. This compose stack is the model that
Terraform gets written from — it is not a substitute for it, and nothing here should be pointed at
a shared environment.

## Bring it up

```bash
cp .env.example .env && docker compose up -d --build
```

Requires `mvn install` at the repo root first — the service Dockerfiles copy a prebuilt jar rather
than running Maven inside the image build. With 16 services eventually in this repo, rebuilding the
whole reactor per image is minutes of waste per service.

## Port map

| Service | Host port | Why not the default |
| --- | --- | --- |
| Postgres | 5433 | 5432 taken by the `lending` stack |
| Redis | 6380 | namespaced to survive a future lending Redis |
| RabbitMQ | 5673 / 15673 | namespaced |
| MinIO | 9010 / 9011 | 9000–9001 taken by lending |
| Keycloak | 8180 | 8090 taken by lending |
| Vault | 8200 | free |
| Config Server | 8888 | free |
| Traefik (API front door) | 8100 | 8080–8095 taken by lending |
| Jaeger | 16686 / 4318 | free |

Ports 8101–8115 are reserved for services arriving in later phases; the full allocation is in the
header comment of `docker-compose.yml`.

## Gotchas worth knowing before you debug them

**The Keycloak realm JSON must not contain comments.** Keycloak deserialises it with unknown-field
rejection on, so even a `_comment` key fails the import and the container exits. Commentary lives in
`keycloak/README.md`.

**One issuer, two addresses.** Clients reach Keycloak at `localhost:8180`, services reach it at
`keycloak:8080`. A token carries one `iss`, so `KC_HOSTNAME` pins the localhost form and services
override `jwk-set-uri` to fetch signing keys internally. Change one without the other and every
token is rejected inside the network.

**`config-repo` is mounted read-write.** Cloning from a `file://` URI makes JGit take a lock inside
the source repo's `.git`, which fails on a read-only mount. Real environments clone from a remote
and this mount does not exist.

**The Config Server needs `spring.profiles.active=composite`.** Without it the composite backend is
ignored entirely and startup fails with "You need to configure a uri for the git repository".

**Vault auth config goes at `spring.cloud.config.server.vault.*`, not in the composite entry.** The
`SpringVaultClientConfiguration` bean that chooses the auth method is built from the global
properties. Put `authentication: APPROLE` only in the composite entry and it is silently ignored —
the server falls back to TOKEN auth and every request fails with
`Missing required header in HttpServletRequest: X-Config-Token`.

**Config changes need a commit.** The Git backend serves committed content, not the working tree.
Editing `config-repo/*.yml` without committing changes nothing.

**Postgres init scripts only run on an empty data directory.** After editing anything in
`postgres/init/`, `docker compose down -v` — otherwise the changes are silently not applied.

## What is deliberately missing

- **mTLS between services and the Config Server.** Section 6 requires it; it belongs at the
  mesh/ingress layer and does not exist locally. The Config Server is protected by HTTP Basic here.
- **A real Vault.** This runs `-dev`: in-memory, auto-unsealed, fixed root token, and a pinned
  AppRole role-id/secret-id so compose can hand the Config Server its credentials without an
  orchestration dance. Where Vault is hosted and who administers it is Section 12 open decision #8.
- **Kubernetes.** Compose is the local target; staging/prod are Kubernetes per Section 10, and
  nobody owns standing that up yet (open decision #2).
- **The Core Banking Simulator** (Phase 4) and every domain service (Phases 1–3).

## Reset

```bash
docker compose down -v
```

Destroys all volumes — Postgres data, the Keycloak realm, MinIO objects and every Vault secret.
Re-running `up` rebuilds all of it from the files here.

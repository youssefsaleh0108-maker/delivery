# Splitting the platform into separate repositories

Every service and every shared library now builds, versions and releases on its own. There is **no
parent pom** anywhere: nothing inherits from anything, so a directory can become a repository
without a single change to its `pom.xml`.

## The model

| What | Where it lives | What it publishes |
|---|---|---|
| `platform-security`, `-observability`, `-outbox`, `-notifications`, `-storage` | one repo, `delivery.platform` | jars → **GitHub Packages** |
| the 19 services | one repo each, `delivery.<service>` | images → **Docker Hub** (`youssefsaleh0108/delivery-<service>`) |
| `config-repo` | already its own repo | cloned by Config Server at runtime |
| `infra`, `deploy/k8s`, `docs`, `clients` | not yet split | — |

The five libraries share one repository but **not one pom** — each is standalone, with its own
version and its own publish job. Moving any of them into its own repository later is a one-line URL
change in `<distributionManagement>` and in each consumer's `<repositories>`, and nothing else.

## What each service pom now carries itself

Everything the old root pom supplied is declared per module:

- `spring-boot-dependencies` 3.4.5 imported as a BOM (replacing the `spring-boot-starter-parent`)
- `spring-cloud-dependencies` 2024.0.1 imported as a BOM (all 19 services use Spring Cloud)
- the `com.delivery:platform-*` versions it actually uses, via `${delivery.platform.version}`
- `spring-boot-starter-test`, which the root applied to every module
- `maven-compiler-plugin` pinned to 3.13.0 with `<release>17</release>`
- `spring-boot-maven-plugin` with an **explicit version and an explicit `repackage` execution** —
  both came from `spring-boot-starter-parent`, and without the execution the jar the Dockerfile
  copies is a plain, unbootable one

## Authenticating to GitHub Packages

**GitHub Packages requires a token even for public packages.** There is no anonymous read. Put this
in `~/.m2/settings.xml`:

```xml
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>YOUR_GITHUB_USERNAME</username>
      <!-- Classic personal access token with the read:packages scope. -->
      <password>ghp_xxxxxxxxxxxxxxxxxxxx</password>
    </server>
  </servers>
</settings>
```

The `<id>` must be exactly `github`, matching the `<repository><id>` in every pom. If it does not
match, Maven sends no credentials at all and you get `401 Unauthorized` on `platform-security` —
which reads like a missing artifact rather than a missing password.

### The cross-repository gotcha

In CI, the built-in `GITHUB_TOKEN` is scoped to **the repository it is running in**. A service repo's
`GITHUB_TOKEN` therefore cannot read packages published by `delivery.platform`, because that is a
different repository. This is the single most likely reason the first build of a freshly split
service fails.

Each service repo needs a `GH_PACKAGES_TOKEN` secret — a classic PAT with `read:packages`. The
generated `.github/workflows/ci.yml` already expects it, alongside `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN`.

## Order of operations

1. **Publish the platform first.** Nothing else can build until the jars exist.
   ```bash
   gh repo create youssefsaleh0108-maker/delivery.platform --private --source=platform --push
   ```
   The `publish.yml` workflow then deploys all five libraries.

2. **Then each service**, from its own directory:
   ```bash
   gh repo create youssefsaleh0108-maker/delivery.order-manager --private --source=. --push
   ```
   Add the three secrets before the first push, or the first run fails on the 401 above.

3. **Verify a service resolves the published jars** rather than your local `~/.m2`. Delete the
   cached copies first, otherwise a stale local install masks a broken dependency exactly the way
   it did before this split:
   ```bash
   rm -rf ~/.m2/repository/com/delivery && mvn -B verify
   ```

## Local development is unchanged

The tree on disk stays exactly as it is; each directory simply gains its own `.git`. The root
`pom.xml` is now a **pure aggregator** — not a parent, and not published — so one command still
builds everything, which is the quickest way to get the platform jars into `~/.m2` without touching
the registry:

```bash
mvn -f pom.xml install -DskipTests
```

`infra/docker-compose.yml` still builds each service from `../services/<name>`, so nothing about
running the stack locally changes. Deleting the aggregator breaks only that convenience.

## Two things to watch

**Migrations inside libraries.** `platform-outbox` and `platform-storage` ship Flyway migrations
under `src/main/resources/db/migration`, and those run inside the database of whichever service
pulls them in. Two services pinned to two versions of the same library now means two different
migration sets against schemas that are meant to agree — the 08-17 `V3`-vs-`V21`/`V18` collision,
with a version number attached. Before changing a migration in a library, check every consumer's
pinned `delivery.platform.version`.

**Nothing rebuilds a service when the platform changes.** That is the point of the split, and the
cost: a security fix in `platform-security` reaches production only when somebody bumps
`delivery.platform.version` in each of the 17 services that use it. In the monorepo, `paths:
['platform/**']` did that automatically.

## Still in the monorepo

The 20 workflows under the root `.github/workflows/` are the old monorepo pipelines. They still work
against the aggregator, and they are now redundant with the per-service `ci.yml` files. Delete them
once every service has moved, not before — during the transition they are the only thing still
building the services that have not been split yet.

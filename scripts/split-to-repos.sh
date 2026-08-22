#!/usr/bin/env bash
# Split the monorepo into the polyrepo layout described in docs/POLYREPO.md.
#
#   delivery.platform        the five shared libraries   -> jars to GitHub Packages
#   delivery.<service>       one repo per service        -> images to Docker Hub
#
# Each directory already carries everything it needs to stand alone: its own pom with no parent,
# its own .gitignore, and its own .github/workflows/ci.yml. This script only adds a .git, makes the
# first commit and creates the remote — it changes no file contents.
#
# PREREQUISITES
#   gh auth login          run it yourself; this script never handles a token
#   The three secrets on each service repo BEFORE its first push, or CI fails on a 401:
#     GH_PACKAGES_TOKEN, DOCKERHUB_USERNAME, DOCKERHUB_TOKEN   (docs/POLYREPO.md)
#
# USAGE
#   scripts/split-to-repos.sh --dry-run       print what would happen, touch nothing
#   scripts/split-to-repos.sh --platform      just delivery.platform (do this FIRST)
#   scripts/split-to-repos.sh --services      the services, after the platform jars exist
#
# ORDER MATTERS. A service build resolves com.delivery:platform-* from GitHub Packages, so nothing
# builds until delivery.platform has published. Run --platform, wait for its workflow to go green,
# then --services.
set -euo pipefail

OWNER="youssefsaleh0108-maker"
VISIBILITY="--private"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DRY_RUN=0
DO_PLATFORM=0
DO_SERVICES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)  DRY_RUN=1 ;;
    --platform) DO_PLATFORM=1 ;;
    --services) DO_SERVICES=1 ;;
    --public)   VISIBILITY="--public" ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ "$DO_PLATFORM" = 0 ] && [ "$DO_SERVICES" = 0 ]; then
  echo "Nothing selected. Pass --platform and/or --services (see the header)." >&2
  exit 2
fi

run() {
  if [ "$DRY_RUN" = 1 ]; then
    echo "    would run: $*"
  else
    "$@"
  fi
}

# Turns one directory into a repository and pushes it. Idempotent enough to re-run: an existing
# .git is left alone and an existing remote is not recreated.
publish_dir() {
  local dir="$1" repo="$2"

  if [ ! -d "$dir" ]; then
    echo "!!  $repo — $dir does not exist, skipping"
    return
  fi
  # An empty directory is not a repository worth creating. services/order-manager is exactly this:
  # the module is absent from this checkout, so there is nothing to publish.
  if [ -z "$(find "$dir" -type f -not -path '*/.git/*' -print -quit)" ]; then
    echo "!!  $repo — $dir contains no files, skipping"
    return
  fi

  echo "==> $repo  ($dir)"

  if [ ! -d "$dir/.git" ]; then
    run git -C "$dir" init -q -b main
    run git -C "$dir" add -A
    run git -C "$dir" commit -q -m "Import $repo from the delivery monorepo

Standalone from the first commit: no parent pom, its own .gitignore and its own
.github/workflows/ci.yml. See docs/POLYREPO.md in the monorepo for the split."
  else
    echo "    .git already present, leaving history alone"
  fi

  if [ "$DRY_RUN" = 1 ]; then
    echo "    would run: gh repo create $OWNER/$repo $VISIBILITY --source=$dir --remote=origin --push"
    return
  fi

  if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    echo "    origin already set, pushing"
    git -C "$dir" push -u origin main
  else
    gh repo create "$OWNER/$repo" $VISIBILITY --source="$dir" --remote=origin --push
  fi
}

if [ "$DRY_RUN" = 0 ]; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "Not logged in to GitHub. Run 'gh auth login' first — this script will not ask you for a token." >&2
    exit 1
  fi
fi

if [ "$DO_PLATFORM" = 1 ]; then
  echo "--- platform libraries ---"
  publish_dir "$ROOT/platform" "delivery.platform"
  echo
  echo "Wait for the 'publish platform libraries' workflow to finish before running --services."
  echo "Nothing else can build until those jars exist in GitHub Packages."
fi

if [ "$DO_SERVICES" = 1 ]; then
  echo "--- services ---"
  for dir in "$ROOT"/services/*/; do
    name="$(basename "$dir")"
    publish_dir "${dir%/}" "delivery.$name"
  done
fi

echo
echo "Done."

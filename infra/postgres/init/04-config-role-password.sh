#!/bin/bash
# Sets the Config Server's database password from the environment.
#
# WHY THIS IS A SHELL SCRIPT AND NOT SQL. 03-config-properties.sql creates the config_server role
# with a hardcoded local-dev password, because plain SQL in docker-entrypoint-initdb.d cannot read
# the environment. On any box with a real generated CONFIG_DB_PASSWORD in .env, that leaves the
# role's password and the one the Config Server presents permanently out of step.
#
# The failure is worth describing, because it does not look like a password problem. The Config
# Server starts and reports healthy — it only opens a database connection when a service asks it
# for configuration. Every OTHER service then dies at boot on a 500 from
# /{service}/{profile}, with `ConfigClientFailFastException: Could not locate PropertySource`.
# The cause is four layers down in the Config Server's own log:
# `FATAL: password authentication failed for user "config_server"`.
#
# Scripts in docker-entrypoint-initdb.d ending in .sh are executed with the container's environment
# available, which is what makes this possible at all. It runs after the numbered SQL files, so the
# role already exists.
#
# Runs only on an empty data directory, like everything else here. Changing CONFIG_DB_PASSWORD on a
# running stack still needs the ALTER by hand — see infra/DEPLOY_CONTABO.md.
set -e

if [ -z "$CONFIG_DB_PASSWORD" ]; then
    echo "04-config-role-password: CONFIG_DB_PASSWORD is not set; leaving the dev password in place."
    echo "  This is fine on a laptop and wrong anywhere else — the config layer resolves every"
    echo "  service's configuration, so its password is worth as much as all of them."
    exit 0
fi

# Dollar-quoted so a password containing quotes or backslashes cannot terminate the string early
# or be re-interpreted. The tag is unlikely enough to appear in a generated secret.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname delivery <<-EOSQL
    ALTER ROLE config_server PASSWORD \$kcpw\$${CONFIG_DB_PASSWORD}\$kcpw\$;
EOSQL

echo "04-config-role-password: config_server password set from the environment."

// Section 10: "Give the Core Banking Connector's secret path its own Vault policy, separate from
// every other service's, since it's the most sensitive integration in the system."
//
// Not yet bound to a role - the Core Banking Connector arrives in Phase 4. The policy is written
// now so the separation is a fact of the platform rather than something remembered later, and so
// the Config Server's blanket `secret/data/*` read above can be narrowed to exclude this path when
// the connector starts reading its own secrets directly.

path "secret/data/corebanking-connector" {
  capabilities = ["read"]
}

path "secret/data/corebanking-connector/*" {
  capabilities = ["read"]
}

path "secret/metadata/corebanking-connector" {
  capabilities = ["read", "list"]
}

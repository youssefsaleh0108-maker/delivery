// The ONLY Vault policy the Config Server gets.
//
// Section 6: the role is scoped read-only to exactly the paths it serves, and the Config Server is
// never given broad Vault access. Client services never authenticate to Vault at all - they call
// the Config Server, which is what keeps Vault credentials confined to one place in the system.

// KV v2 stores data under <mount>/data/<path>. Read-only: the Config Server serves secrets, it
// never rotates them.
path "secret/data/*" {
  capabilities = ["read"]
}

// Needed to resolve which paths exist when composing a response for {application}/{profile}.
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

// Lets the AppRole token renew itself rather than forcing a Config Server restart when it expires.
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

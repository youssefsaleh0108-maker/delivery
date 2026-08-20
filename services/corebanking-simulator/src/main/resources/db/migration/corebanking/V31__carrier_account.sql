-- An account for a delivery company.
--
-- Delivery providers are paid separately from the merchant and the platform, so a carrier needs
-- somewhere for that money to land. Opening one here is the simulator's stand-in for onboarding:
-- in production a company gets an account when it signs up, and a payout account the bank has never
-- heard of is a rejected posting on every single delivery.
--
-- That failure mode is worth stating because it is invisible until the first order is delivered:
-- the registration succeeds, the split is computed correctly, and only the bank leg fails. Verifying
-- the account at registration is the real fix and is not built.
INSERT INTO bank_accounts (account_ref, holder_name, balance_minor, currency, status)
VALUES ('ACC-CARRIER', 'Test Delivery Company', 0, 'USD', 'ACTIVE')
ON CONFLICT (account_ref) DO NOTHING;

-- The SMS dev test inbox is owned by the environment, not by this table.
--
-- V10 seeded the SMS row with {"testInbox": "..."}, and the Backoffice renders every config key it
-- is given. DevPassthroughSmsClient, however, takes the address from delivery.sms.dev-passthrough.
-- test-inbox, which every environment sets from SMS_TEST_INBOX - so the value on the settings
-- screen was one nobody obeyed, and an operator changing it saw a saved, audited change that moved
-- no message. Dropping the key stops the screen making a claim the connector does not honour;
-- ConnectorSetting refuses to store it again.
--
-- V10 itself is left alone: it has already run everywhere and Flyway validates its checksum. On a
-- fresh database the seed inserts the key and this migration removes it a moment later.
--
-- Safe against rows already live: the jsonb minus operator returns the object unchanged when the
-- key is absent, so this is a no-op on any environment that has been cleaned up by hand.
UPDATE connector_settings
   SET config_json = config_json - 'testInbox'
 WHERE connector_type = 'SMS';

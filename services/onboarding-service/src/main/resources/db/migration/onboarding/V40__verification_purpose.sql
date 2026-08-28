-- What a one-time code is FOR, so a code issued for one act cannot be answered to perform another.
--
-- Until now every code meant one thing: "prove this address is yours so a sign-up or an
-- application can name it". Password reset introduces a second meaning — "prove you still hold
-- this address so its passcode can be replaced" — and the two must not be interchangeable. A
-- reset code answered on the sign-up form would verify an address for an application; a sign-up
-- code answered on the reset form would replace a passcode. Both crossings are wrong, and both
-- are prevented by looking the challenge up by purpose as well as by destination.
--
-- The DEFAULT backfills every existing row as SIGNUP, which is what every existing row genuinely
-- was: no other purpose existed when it was written.
ALTER TABLE onboarding_verifications
    ADD COLUMN purpose varchar(32) NOT NULL DEFAULT 'SIGNUP';

ALTER TABLE onboarding_verifications
    ADD CONSTRAINT chk_verification_purpose CHECK (purpose IN ('SIGNUP', 'PASSWORD_RESET'));

-- The confirm step's lookup: the newest live challenge for this destination FOR THIS PURPOSE.
-- The older idx_verification_destination stays: the resend cooldown deliberately counts across
-- purposes, because the cost of a message lands on the inbox regardless of why it was sent.
CREATE INDEX idx_verification_destination_purpose
    ON onboarding_verifications (channel, destination, purpose, created_at DESC);

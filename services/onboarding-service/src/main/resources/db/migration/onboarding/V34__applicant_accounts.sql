-- An applicant gets an account when they apply, not when they are approved.
--
-- Until now an application ended at a reference number: no account, no way in, and nothing to do
-- but wait for an email. The applicant chooses a passcode at the end of the form instead, signs in
-- immediately, and sees their own application's status in the app until somebody decides on it.
--
-- The account this creates holds the APPLICANT realm role and nothing else. That role grants no
-- endpoint anywhere — it exists so a token can say "this person applied" without saying "this
-- person is a merchant". The real role is granted on approval, to this same account.
--
-- Its own column rather than reusing provisioned_user_ref. That one means "approved and set up",
-- and is what the provisioning step checks to avoid creating a second account; folding a pending
-- applicant into it would make an application look provisioned before anybody had decided.

ALTER TABLE onboarding_applications
    ADD COLUMN applicant_user_ref varchar(64);

-- One account per application. Retrying the account step after a network failure must not leave a
-- second Keycloak user behind for the same applicant.
CREATE UNIQUE INDEX idx_application_applicant_user
    ON onboarding_applications (applicant_user_ref)
    WHERE applicant_user_ref IS NOT NULL;

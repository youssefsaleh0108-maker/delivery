-- What a reviewer overrode when they approved an application whose documents were not all clean.
--
-- An application's decision and its documents are separate on purpose. A reviewer who has the
-- commercial registration in front of them on paper, or who knows the rejected photo was rejected
-- for glare, must be able to approve — refusing outright would mean the honest way through is to
-- approve the document they have not actually verified, which is a worse record than an approval
-- that says what was outstanding.
--
-- But it must not be silent. The service refuses the approval unless the caller explicitly
-- acknowledges the outstanding documents, and when they do, what was outstanding at that moment is
-- written here: 'NATIONAL_ID=REJECTED, DRIVING_LICENCE=PENDING'. Machine-generated from enum names,
-- so nothing applicant-supplied reaches this column.
--
-- Null means either "every document was approved" or "there were no documents to have an opinion
-- about", and the documents table distinguishes those.
ALTER TABLE onboarding_applications
    ADD COLUMN document_issue_override varchar(500);

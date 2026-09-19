-- One-time codes out of the delivery log, and the one narrow place a smoke test may still read one.
--
-- notification_log kept every verification and passcode-reset code in full, in the subject and in the
-- body, and back office reads the log through the API (GET /api/notification-log/recipients/anonymous
-- lists every message sent to somebody with no account). So anybody with that role could ask for a
-- code to any address, read it back there, and set that account's passcode or prove its address.
-- The service now masks a code before it writes the row (NotificationDispatchService.CODE_PURPOSES);
-- this masks the ones already written, by the same rule: every run of four or more digits in a
-- message whose purpose carries a code. Those codes died ten minutes after they were sent, but a log
-- that is meant to hold no codes should hold none.
UPDATE notification.notification_log
   SET subject = regexp_replace(subject, '[0-9]{4,}', '******', 'g'),
       body    = regexp_replace(body, '[0-9]{4,}', '******', 'g')
 WHERE lower(trim(event_type)) IN ('onboarding.verification', 'onboarding.password-reset');

-- The sink. The suites that sign somebody up have to answer a code, and they read it from the log;
-- now they read it here. Only for addresses on youdrop.test, a domain under the .test TLD that RFC
-- 2606 reserves, so nobody can own a mailbox there, and only in an environment that switched the
-- sink on (delivery.notifications.test-code-sink.enabled: off by default, on in dev and qa, never in
-- production). Nothing in the API reads this table. Only the code is kept, and only for a day. See
-- TestCodeSink.
CREATE TABLE notification.test_code_sink (
    id          uuid         PRIMARY KEY,
    recipient   varchar(255) NOT NULL,
    purpose     varchar(64)  NOT NULL,
    code        varchar(64)  NOT NULL,
    created_at  timestamptz  NOT NULL DEFAULT now(),
    -- The rule TestCodeSink applies, again here, so that a row for any other address cannot exist
    -- whatever writes it.
    CONSTRAINT chk_test_code_sink_reserved_domain
        CHECK (recipient ~ '^[a-z0-9][a-z0-9._%+-]{0,63}@youdrop\.test$'),
    CONSTRAINT chk_test_code_sink_code CHECK (code ~ '^[0-9]{4,64}$')
);

-- A test reads the newest code for its address.
CREATE INDEX idx_test_code_sink_recipient
    ON notification.test_code_sink (recipient, created_at DESC);

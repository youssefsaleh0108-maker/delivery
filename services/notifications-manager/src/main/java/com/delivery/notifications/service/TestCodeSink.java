package com.delivery.notifications.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.notifications.domain.TestCode;
import com.delivery.notifications.domain.TestCodeRepository;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.OneTimeCodes;

/**
 * Where a smoke test reads a one-time code, now that the delivery log keeps none.
 *
 * <p>The suites that sign somebody up have to answer a code, and they used to read it out of
 * notification_log, which held every code the platform sent. So did anybody with back-office access:
 * ask for a code to any address, read it back from the log, set that account's passcode. The log now
 * masks codes (see {@link NotificationDispatchService}), and this is the narrow way back in for tests.
 *
 * <p><strong>Three locks, each enough on its own to keep a real person's code out:</strong>
 * <ul>
 *   <li><strong>The reserved test domain only</strong> ({@value #RESERVED_DOMAIN}, email only).
 *       {@code .test} is reserved by RFC 2606 and RFC 6761 and can never be registered, so nobody
 *       holds a mailbox there, and an address on it could only have been proved through this sink.
 *       A code kept here therefore opens only an account a test made. The domain is fixed in code,
 *       not configured, so no setting can point the sink at a real one; and the address must match
 *       exactly (one {@code @}, nothing after the domain), so a look-alike cannot slip through.</li>
 *   <li><strong>Off unless an environment turns it on</strong>, with
 *       {@code delivery.notifications.test-code-sink.enabled}. Only the dev and qa overlays and the
 *       dev compose stack do; a production overlay must not, and the service says loudly at start-up
 *       when it is on.</li>
 *   <li><strong>No endpoint.</strong> The sink is a table, {@code notification.test_code_sink}, and a
 *       smoke test reads it with the database access it already had for everything else. Nothing in
 *       the API can reach it, so back office cannot, whatever it is granted.</li>
 * </ul>
 *
 * <p>Only the code is kept, not the message, and only for a day.
 */
@Component
public class TestCodeSink {

    private static final Logger log = LoggerFactory.getLogger(TestCodeSink.class);

    /** The one domain whose codes may be kept. Reserved, so it cannot belong to anybody. */
    public static final String RESERVED_DOMAIN = "youdrop.test";

    /**
     * A plain local part, then exactly the reserved domain, and nothing after it. V20 repeats it as
     * the table's CHECK, so a row for any other address cannot exist whatever writes it.
     */
    static final String ADDRESS_RULE = "^[a-z0-9][a-z0-9._%+-]{0,63}@youdrop\\.test$";

    private static final Pattern TEST_ADDRESS = Pattern.compile(ADDRESS_RULE);

    /** A code longer than this is not one of ours, and would not fit the column. */
    private static final int LONGEST_CODE = 64;

    static final Duration KEPT_FOR = Duration.ofDays(1);

    private final TestCodeRepository codes;
    private final boolean enabled;

    public TestCodeSink(TestCodeRepository codes,
                        @Value("${delivery.notifications.test-code-sink.enabled:false}")
                        boolean enabled) {
        this.codes = codes;
        this.enabled = enabled;
        if (enabled) {
            log.warn("The test code sink is ON: one-time codes sent to @{} addresses are kept in "
                    + "notification.test_code_sink. It must never be on in production.",
                    RESERVED_DOMAIN);
        }
    }

    public boolean isEnabled() {
        return enabled;
    }

    /** Whether a code sent on this channel to this address would be kept. */
    public boolean accepts(String channel, String recipient) {
        return enabled
                && NotificationCommand.CHANNEL_EMAIL.equals(channel)
                && recipient != null
                && TEST_ADDRESS.matcher(recipient.trim().toLowerCase(Locale.ROOT)).matches();
    }

    /**
     * Keeps the code a message carries, when the sink is on and the address is a test one.
     *
     * <p>Called in the same transaction as the log row, before the command goes out, so a sink that
     * could not write stops the send rather than leaving a test waiting for a code it can never read.
     *
     * @param subject the text as delivered, code included
     * @param body    the text as delivered, code included
     * @return whether a code was kept
     */
    public boolean capture(String channel, String recipient, String purpose, String subject,
                           String body) {
        if (!accepts(channel, recipient)) {
            return false;
        }
        Optional<String> code = OneTimeCodes.find(body).or(() -> OneTimeCodes.find(subject));
        if (code.isEmpty() || code.get().length() > LONGEST_CODE) {
            return false;
        }
        codes.deleteOlderThan(Instant.now().minus(KEPT_FOR));
        codes.save(new TestCode(recipient.trim().toLowerCase(Locale.ROOT), purpose, code.get()));
        // Neither the code nor the address goes in this line: the table is where a test reads them.
        log.info("Kept a {} code for a test address in the test code sink", purpose);
        return true;
    }
}

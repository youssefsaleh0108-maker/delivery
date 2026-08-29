package com.delivery.accounting.service;

import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.StatementDispatch;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * Emails a statement, and records that it happened.
 *
 * <p>Three refusals, and each of them is a mistake that costs somebody real time.
 *
 * <p><strong>No address.</strong> Refused rather than guessed. A carrier's reference is an Order
 * Manager provider id and not a Keycloak account, so there is genuinely nothing on file for one; a
 * merchant may have no email recorded. Sending a shop's figures to a best-guess address is a
 * disclosure, not a delivery, and the operator can always supply the address themselves.
 *
 * <p><strong>The same period twice.</strong> A merchant who receives August a second time reads it
 * as a second amount owed. Refused unless the caller says explicitly that they mean it — the
 * override exists because a genuine re-send is a real thing (the first one bounced, the figures were
 * restated) and a rule with no way through would be worked around rather than obeyed.
 *
 * <p><strong>A send that failed.</strong> The dispatch row is written only after Notifications
 * Manager has accepted the message. A row written first would tell the counterparties listing that a
 * shop had been told when it had not, and the operator would stop chasing it — which is a worse
 * outcome than no record at all.
 */
@Service
public class StatementDispatchService {

    private static final Logger log = LoggerFactory.getLogger(StatementDispatchService.class);

    /** The event type the message is logged under in Notifications Manager. */
    private static final String PURPOSE = "ACCOUNTING_STATEMENT";

    private static final String CHANNEL = "EMAIL";

    private final StatementService statements;
    private final StatementDispatchRepository dispatches;
    private final CounterpartyDirectory directory;
    private final StatementRenderer renderer;
    private final NotificationsClient notifications;

    public StatementDispatchService(StatementService statements,
                                    StatementDispatchRepository dispatches,
                                    CounterpartyDirectory directory,
                                    StatementRenderer renderer,
                                    NotificationsClient notifications) {
        this.statements = statements;
        this.dispatches = dispatches;
        this.directory = directory;
        this.renderer = renderer;
        this.notifications = notifications;
    }

    /** No address could be resolved and none was supplied. A 409 at the edge. */
    public static class NoRecipientException extends RuntimeException {
        public NoRecipientException(String message) {
            super(message);
        }
    }

    /** This exact period has already gone to this party. A 409 at the edge, with the previous row. */
    public static class AlreadySentException extends RuntimeException {
        private final transient StatementDispatch previous;

        public AlreadySentException(StatementDispatch previous) {
            super("That period was already sent to this counterparty on " + previous.getSentAt());
            this.previous = previous;
        }

        public StatementDispatch previous() {
            return previous;
        }
    }

    /**
     * Renders the statement and sends it.
     *
     * @param override an address the operator supplied, or null to use the one on file
     * @param resend   true when the operator means to send a period that has already gone
     * @param sentBy   the Keycloak subject of the person doing it. Never a service account — nothing
     *                 schedules this, so there is always a person to name
     * @throws NoRecipientException nothing on file and nothing supplied
     * @throws AlreadySentException this period has gone before and {@code resend} was not set
     */
    @Transactional
    public StatementDispatch send(CounterpartyKind kind, String ref, StatementRange range,
                                  String override, boolean resend, String sentBy) {

        String recipient = override == null || override.isBlank()
                ? directory.recipientOf(kind, ref)
                : override.trim();

        if (recipient == null || recipient.isBlank()) {
            throw new NoRecipientException(
                    "No email address is on file for this " + kind.name().toLowerCase()
                            + ", and none was supplied. Send it again with a `to` address.");
        }

        if (!resend) {
            Optional<StatementDispatch> already = dispatches
                    .findFirstByCounterpartyKindAndCounterpartyRefAndPeriodFromAndPeriodToOrderBySentAtDesc(
                            kind, ref, range.from(), range.to());
            if (already.isPresent()) {
                throw new AlreadySentException(already.get());
            }
        }

        // Built here rather than taken from the caller. A statement passed in could have been
        // computed against a different range from the one being recorded, and the row would then
        // claim a period the figures never covered.
        Statement statement = statements.build(kind, ref, range);

        String notificationRef = notifications.sendDirect(CHANNEL, recipient,
                renderer.subject(statement), renderer.body(statement), PURPOSE);

        StatementDispatch dispatch = dispatches.save(new StatementDispatch(
                kind, ref, range.from(), range.to(), CHANNEL, recipient,
                statement.net().amount(), statement.net().direction().name(),
                statement.currency(), notificationRef, sentBy));

        log.info("{} sent the {} statement for {} covering {} to {}",
                sentBy, kind, ref, range.from() + ".." + range.to(), dispatch.getId());
        return dispatch;
    }
}

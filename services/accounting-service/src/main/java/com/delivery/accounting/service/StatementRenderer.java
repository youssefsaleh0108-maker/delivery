package com.delivery.accounting.service;

import java.time.format.DateTimeFormatter;

import org.springframework.stereotype.Component;

import com.delivery.accounting.domain.CounterpartyKind;

/**
 * Turns a statement into the words that get emailed.
 *
 * <p>Plain text, and deliberately. Notifications Manager owns the templates, the provider
 * credentials and the delivery log; what it accepts on the direct path is a subject and a body, and
 * a second templating engine in this service would be a second place for a merchant's figures to be
 * formatted differently.
 *
 * <p><strong>The body is bounded.</strong> Notifications Manager caps it at 2,000 characters and
 * rejects anything longer, so a statement with hundreds of orders would fail to send — after the
 * figures were computed, at the last step, having promised nothing. The itemisation is therefore
 * budgeted here and the totals always survive: what a counterparty needs is what they are owed and
 * why, and the per-order detail is available through the API for anybody who wants to reconcile.
 */
@Component
public class StatementRenderer {

    /** Notifications Manager's own limit on a direct message body. */
    static final int MAX_BODY = 2000;

    /** Its limit on a subject. */
    static final int MAX_SUBJECT = 200;

    private static final DateTimeFormatter DATE = DateTimeFormatter.ISO_LOCAL_DATE;

    public String subject(Statement statement) {
        return trim("Statement for " + statement.name() + ", "
                + statement.from().format(DATE) + " to " + statement.to().format(DATE),
                MAX_SUBJECT);
    }

    public String body(Statement statement) {
        StringBuilder text = new StringBuilder();
        text.append(statement.name()).append('\n');
        text.append("Statement for ").append(statement.from().format(DATE))
                .append(" to ").append(statement.to().format(DATE))
                .append(" (").append(statement.currency()).append(")\n\n");

        for (Statement.Line line : statement.lines()) {
            text.append(line.direction() == Statement.Sign.DEBIT ? "-" : "+")
                    .append(line.amount().toPlainString())
                    .append("  ").append(line.label());
            if (line.note() != null) {
                text.append(" (").append(line.note()).append(')');
            }
            text.append('\n');
        }

        text.append('\n').append(summaryLine(statement)).append('\n');

        if (statement.note() != null) {
            text.append('\n').append(statement.note()).append('\n');
        }

        // The itemisation only if it fits whole. A list that stops mid-way through August reads as
        // if the platform lost the rest of the month, which is worse than not itemising at all.
        String detail = detail(statement);
        if (!detail.isEmpty() && text.length() + detail.length() <= MAX_BODY) {
            text.append(detail);
        } else if (!statement.entries().isEmpty()) {
            text.append("\n").append(statement.entries().size())
                    .append(" orders are itemised in the platform's statements API.\n");
        }

        return trim(text.toString(), MAX_BODY);
    }

    /**
     * The bottom line, said in words rather than in a sign.
     *
     * <p>"WE_OWE" is the platform's vocabulary and means the opposite thing depending on who is
     * reading it. A merchant reads "the platform owes you"; the platform's own finance mailbox reads
     * something else again, which is why the platform's statement gets its own phrasing rather than
     * a sentence that would have it owing itself money.
     */
    private String summaryLine(Statement statement) {
        String amount = statement.net().amount().toPlainString() + " " + statement.currency();
        if (statement.net().direction() == Statement.Direction.SETTLED) {
            return "Nothing is outstanding either way.";
        }
        boolean weOwe = statement.net().direction() == Statement.Direction.WE_OWE;
        if (statement.kind() == CounterpartyKind.PLATFORM) {
            return weOwe
                    ? "The platform is out of pocket by " + amount + " over this period."
                    : "The platform is owed " + amount + " over this period.";
        }
        return weOwe
                ? "The platform owes you " + amount + "."
                : "You owe the platform " + amount + ".";
    }

    private String detail(Statement statement) {
        if (statement.entries().isEmpty()) {
            return "";
        }
        StringBuilder rows = new StringBuilder("\nOrders\n");
        for (Statement.Entry entry : statement.entries()) {
            rows.append(entry.orderId()).append("  ")
                    .append(entry.net().toPlainString());
            if (entry.commission().signum() != 0) {
                rows.append("  (gross ").append(entry.gross().toPlainString())
                        .append(", commission ").append(entry.commission().toPlainString())
                        .append(')');
            }
            if (entry.paymentMethod() != null) {
                rows.append("  ").append(entry.paymentMethod());
            }
            rows.append('\n');
        }
        return rows.toString();
    }

    private static String trim(String value, int limit) {
        return value.length() <= limit ? value : value.substring(0, limit);
    }
}

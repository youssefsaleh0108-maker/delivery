package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

import com.delivery.accounting.domain.CounterpartyKind;

/**
 * What one party is owed, or owes, over one period.
 *
 * <p><strong>The net is never supplied; it is always derived.</strong> {@link #of} adds the lines up
 * and that sum IS the net — there is no constructor that accepts both, so a statement whose lines do
 * not explain its bottom line cannot be built, let alone served. That was the alternative worth
 * ruling out: a net computed straight from the ledger beside lines computed for display drifts the
 * first time somebody adds a line and forgets the total, and the drift is invisible until a merchant
 * adds the column up by hand and finds it does not agree.
 *
 * <p>The second half of the same guarantee is the {@code control} argument. Deriving the net from
 * the lines makes the statement internally consistent; it does not make it TRUE. The control figure
 * is the same number computed independently from the ledger rows, and a mismatch throws rather than
 * returning a plausible-looking document. Internal consistency and agreement with the books are two
 * different properties and this class refuses to be shipped without both.
 *
 * <h2>Sign convention</h2>
 * <p>{@code CREDIT} increases what the platform owes the counterparty; {@code DEBIT} decreases it.
 * The net is {@code credits - debits}, so a positive net is {@link Direction#WE_OWE} and a negative
 * one is {@link Direction#THEY_OWE}, always from the platform's point of view. One rule for all four
 * kinds, and no per-kind flag: the differences between them live in which lines get authored, never
 * in how the arithmetic is read.
 */
public record Statement(
        CounterpartyKind kind,
        String ref,
        String name,
        LocalDate from,
        LocalDate to,
        String currency,
        Instant generatedAt,
        List<Line> lines,
        Net net,
        List<Entry> entries,
        /*
         * How many distinct orders the figures were built from.
         *
         * <p>Not on the wire in the statement payload — the API renders that by hand and the
         * contract does not carry it there — but the counterparties listing does show it, and it has
         * to be THIS number rather than one the listing computes for itself. A summary row and the
         * statement behind it disagreeing about how many orders there were is the kind of small
         * discrepancy that costs an afternoon and destroys confidence in both screens.
         */
        int orders,
        String note) {

    /** Which way a single line moves the balance. See the sign convention above. */
    public enum Sign { CREDIT, DEBIT }

    /** Which way the bottom line points, always from the platform's point of view. */
    public enum Direction { WE_OWE, THEY_OWE, SETTLED }

    /**
     * One figure on the statement, with a label a human can check.
     *
     * @param note free text for what the amount cannot say — an order count, a caveat — or null
     */
    public record Line(String label, BigDecimal amount, Sign direction, String note) {

        public static Line credit(String label, BigDecimal amount, String note) {
            return new Line(label, money(amount), Sign.CREDIT, note);
        }

        public static Line debit(String label, BigDecimal amount, String note) {
            return new Line(label, money(amount), Sign.DEBIT, note);
        }

        /** The line's contribution to the net: positive for a credit, negative for a debit. */
        BigDecimal signed() {
            return direction == Sign.CREDIT ? amount : amount.negate();
        }
    }

    /**
     * The bottom line.
     *
     * <p>{@code amount} is always non-negative — the direction carries the sign. A negative amount
     * beside a direction that also means "the other way" is how a report ends up saying the opposite
     * of what it means to whoever renders it without reading both fields.
     */
    public record Net(BigDecimal amount, Direction direction) {
    }

    /**
     * One order's contribution, for the party to check line by line.
     *
     * @param gross      what the order was worth to this party before the platform's cut
     * @param commission the platform's cut, where it can be attributed to this party's order alone
     * @param net        what the platform actually owes for this order. Always exact
     */
    public record Entry(UUID orderId, Instant at, BigDecimal gross, BigDecimal commission,
                        BigDecimal net, String paymentMethod) {
    }

    /**
     * Builds a statement, deriving the net from the lines and refusing to disagree with the ledger.
     *
     * @param control what the source rows say the net is, computed independently of the lines
     * @throws IllegalStateException the lines do not sum to the control figure. Deliberately not a
     *                               logged warning and a best-effort document: a statement that is
     *                               wrong in a way nobody notices is worse than an error somebody
     *                               has to fix, because it is the one that gets emailed to a shop
     */
    public static Statement of(CounterpartyKind kind, String ref, String name,
                               StatementRange range, String currency,
                               List<Line> lines, BigDecimal control,
                               List<Entry> entries, int orders, String note) {

        BigDecimal summed = lines.stream()
                .map(Line::signed)
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .setScale(2, RoundingMode.HALF_UP);

        BigDecimal expected = money(control);
        if (summed.compareTo(expected) != 0) {
            throw new IllegalStateException(
                    "The %s statement for %s does not balance: its lines sum to %s but the ledger "
                            .formatted(kind, ref, summed)
                            + "says " + expected + ". One of the two is wrong and neither may be "
                            + "sent.");
        }

        return new Statement(kind, ref, name, range.from(), range.to(), currency, Instant.now(),
                List.copyOf(lines), netOf(summed), List.copyOf(entries), orders, note);
    }

    private static Net netOf(BigDecimal signed) {
        if (signed.signum() == 0) {
            return new Net(money(BigDecimal.ZERO), Direction.SETTLED);
        }
        return signed.signum() > 0
                ? new Net(signed, Direction.WE_OWE)
                : new Net(signed.negate(), Direction.THEY_OWE);
    }

    /**
     * Two decimals, HALF_UP, everywhere.
     *
     * <p>Public because the API layer renders with it too. Every amount that reaches the wire goes
     * through this one method, so "2 decimals" is a property of the codebase rather than a rule each
     * serialiser is trusted to remember.
     */
    public static BigDecimal money(BigDecimal amount) {
        return (amount == null ? BigDecimal.ZERO : amount).setScale(2, RoundingMode.HALF_UP);
    }
}

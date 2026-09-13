package com.delivery.accounting.domain;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * What V51 must say, pinned by its text.
 *
 * <p>No build machine here runs a migration, so — as {@link CarrierCustodyMigrationTest} does for V50
 * — the clauses whose loss would leave payroll plausible and wrong are pinned where they are written:
 * the arithmetic a payslip is refused without, the keys that stop a day being paid twice, the rule
 * that netted cash is all of a rider's bag or none of it, and the line payroll must never cross into
 * the platform's own books.
 */
@DisplayName("the carrier payroll migration")
class CarrierPayrollMigrationTest {

    private static List<String> statements;

    @BeforeAll
    static void read() throws IOException {
        try (InputStream in = CarrierPayrollMigrationTest.class
                .getResourceAsStream("/db/migration/accounting/V51__carrier_rider_payroll.sql")) {
            assertThat(in).as("V51 on the classpath").isNotNull();
            String sql = new String(in.readAllBytes(), StandardCharsets.UTF_8);
            // Comments out and whitespace collapsed, one entry per statement: the assertions read what
            // Postgres will run, not what a comment says it runs.
            statements = Arrays.stream(sql.replaceAll("--[^\\n]*", " ").split(";"))
                    .map(statement -> statement.replaceAll("\\s+", " ").trim())
                    .filter(statement -> !statement.isEmpty())
                    .toList();
        }
    }

    private static String the(String name) {
        return statements.stream()
                .filter(statement -> statement.contains(name))
                .reduce((a, b) -> a + " ; " + b)
                .orElseThrow(() -> new AssertionError(name + " is not in V51"));
    }

    @Test
    @DisplayName("adds the payroll hand-over method and keeps every method a counter records")
    void theFloatMethod() {
        assertThat(the("ADD CONSTRAINT chk_float_method"))
                .contains("'CASH', 'BANK_DEPOSIT', 'WALLET', 'PAYROLL_DEDUCTION'");
        // A payroll deduction is custody kept against pay — never cash reaching the platform.
        assertThat(the("chk_float_payroll_method"))
                .contains("method <> 'PAYROLL_DEDUCTION' OR entry_kind = 'TRANSFERRED'");
    }

    @Test
    @DisplayName("refuses a payslip whose parts do not make its totals")
    void payslipArithmetic() {
        String payslip = the("CREATE TABLE carrier_payslip");
        assertThat(payslip)
                .contains("CHECK (gross = base_pay + delivery_pay + bonuses)")
                .contains("CHECK (net = gross - deductions)")
                // All of a rider's bag or none of it: a hand-over cannot clear part of one.
                .contains("(cash_netted = 0 OR cash_netted = cash_held) AND deductions >= cash_netted")
                // Past the draft, netted cash names the hand-over that took it.
                .contains("status = 'DRAFT' OR cash_netted = 0 OR handover_id IS NOT NULL")
                .contains("UNIQUE (run_id, rider_ref)");
    }

    @Test
    @DisplayName("cannot pay one company's day twice, even across a change of calendar")
    void onePeriodOnce() {
        String run = the("CREATE TABLE carrier_pay_run");
        assertThat(run)
                .contains("CONSTRAINT uq_pay_run_from UNIQUE (carrier_ref, period_from)")
                .contains("CONSTRAINT uq_pay_run_to UNIQUE (carrier_ref, period_to)");
    }

    /**
     * Attendance keeps changing after a period ends, so a run keeps the hours it was computed with
     * and says when they were read.
     */
    @Test
    @DisplayName("keeps a copy of the hours each run used, and when they were read")
    void hoursAreASnapshot() {
        assertThat(the("CREATE TABLE carrier_pay_attendance"))
                .contains("run_id uuid NOT NULL REFERENCES carrier_pay_run (id)")
                .contains("UNIQUE (run_id, rider_ref)");
        assertThat(the("CREATE TABLE carrier_pay_run"))
                .contains("attendance_at timestamptz")
                .contains("attendance <> 'INCLUDED' OR attendance_at IS NOT NULL");
    }

    /**
     * A delivery is an order, whatever it earned, so a run keeps the count Order Manager gave it — and
     * says when the ledger's paid jobs stood in, which a free delivery is missing from.
     */
    @Test
    @DisplayName("keeps a copy of the deliveries each run counted, and says when the ledger stood in")
    void deliveriesAreASnapshot() {
        assertThat(the("CREATE TABLE carrier_pay_delivered"))
                .contains("run_id uuid NOT NULL REFERENCES carrier_pay_run (id)")
                .contains("UNIQUE (run_id, rider_ref)")
                .contains("CHECK (delivered >= 0)");
        assertThat(the("CREATE TABLE carrier_pay_run"))
                .contains("deliveries varchar(16) NOT NULL")
                .contains("deliveries IN ('ORDERS', 'LEDGER')")
                .contains("deliveries <> 'ORDERS' OR deliveries_at IS NOT NULL");
    }

    @Test
    @DisplayName("a correction is paid in a later run, never in the run it corrects")
    void correctionsGoForward() {
        assertThat(the("CREATE TABLE carrier_pay_adjustment"))
                .contains("applied_run_id IS NULL OR applied_run_id <> corrects_run_id")
                .contains("CHECK (amount > 0)");
    }

    /**
     * The platform does not pay a delivery company's riders. The only platform table payroll may
     * change is the float, and only its method check — no leg, no rider balance.
     */
    @Test
    @DisplayName("touches no platform ledger table")
    void staysOffThePlatformsBooks() {
        assertThat(statements).noneSatisfy(statement -> {
            String lower = statement.toLowerCase(Locale.ROOT);
            assertThat(lower).containsAnyOf("transactions", "rider_ledger", "rider_cash_out",
                    "points_ledger");
        });
        assertThat(statements)
                .filteredOn(statement -> statement.startsWith("ALTER TABLE"))
                .allSatisfy(statement -> assertThat(statement).startsWith("ALTER TABLE cash_float"));
    }
}

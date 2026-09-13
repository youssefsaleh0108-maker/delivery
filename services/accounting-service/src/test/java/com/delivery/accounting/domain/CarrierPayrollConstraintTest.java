package com.delivery.accounting.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceException;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfSystemProperty;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.test.context.TestPropertySource;

/**
 * The rules carrier payroll's money rests on, run against a real Postgres.
 *
 * <p>The mocked tests prove the service computes and moves correctly; none of them can prove V51's
 * checks exist and hold. These do: a payslip whose parts do not make its total is refused, one
 * company's day cannot be paid by two runs, a payroll deduction is only ever a hand-over of custody,
 * and a run keeps one copy of each rider's hours.
 *
 * <p><strong>Skipped unless a database is there</strong>, exactly like {@link RiderLedgerConstraintTest}:
 *
 * <pre>
 * docker run --rm -d --name acct -p 55433:5432 -e POSTGRES_PASSWORD=test -e POSTGRES_DB=accounting postgres:17
 * # apply the platform migrations and accounting V40-V51, then:
 * mvn -f services/accounting-service/pom.xml test -Ddelivery.test.postgres=true
 * </pre>
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:postgresql://localhost:55433/accounting",
        "spring.datasource.username=postgres",
        "spring.datasource.password=test",
        "spring.flyway.enabled=false",
        "spring.jpa.hibernate.ddl-auto=none"
})
@EnabledIfSystemProperty(named = "delivery.test.postgres", matches = "true")
@DisplayName("the rules carrier payroll's money rests on")
class CarrierPayrollConstraintTest {

    @Autowired
    private CarrierPayPolicyRepository policies;

    @Autowired
    private CarrierPayRunRepository runs;

    @Autowired
    private CarrierPayslipRepository payslips;

    @Autowired
    private CarrierPayAttendanceRepository snapshots;

    @Autowired
    private CarrierPayDeliveredRepository deliveredCopies;

    @Autowired
    private EntityManager em;

    private CarrierPayRun run(String company, String from, String to) {
        CarrierPayPolicy policy = policies.saveAndFlush(CarrierPayPolicy.version(company,
                LocalDate.parse("2026-09-01"),
                new CarrierPayPolicy.Terms(CarrierPayPolicy.PayCycle.SEMI_MONTHLY,
                        new BigDecimal("2.00"), null, true, new BigDecimal("1.00"),
                        new BigDecimal("0.00"), new BigDecimal("0.00")),
                "USD", "staff", Instant.now()));
        CarrierPayRun run = CarrierPayRun.draft(company, LocalDate.parse(from), LocalDate.parse(to),
                policy.getId(), "USD", "staff", Instant.now());
        run.recomputed(policy.getId(), CarrierPayRun.Attendance.NOT_NEEDED, null, null,
                CarrierPayRun.Deliveries.ORDERS, null, Instant.now(), Instant.now());
        return runs.saveAndFlush(run);
    }

    private static CarrierPayslip.Figures figures(String gross, String deductions, String net) {
        return new CarrierPayslip.Figures(5, null, null, null, null, null,
                new BigDecimal("0.00"), new BigDecimal(gross), new BigDecimal("0.00"),
                new BigDecimal(deductions), new BigDecimal(gross), new BigDecimal(net),
                new BigDecimal("0.00"), new BigDecimal("0.00"), new BigDecimal("0.00"));
    }

    @Test
    void a_payslip_whose_parts_do_not_make_its_net_is_refused() {
        CarrierPayRun run = run("company-" + UUID.randomUUID(), "2026-10-01", "2026-10-15");

        assertThatCode(() -> payslips.saveAndFlush(
                CarrierPayslip.draft(run.getId(), "rider-a", figures("10.00", "0.00", "10.00"))))
                .doesNotThrowAnyException();
        // A net of 9.00 from 10.00 gross and nothing deducted is a payslip that pays the wrong amount.
        assertThatThrownBy(() -> payslips.saveAndFlush(
                CarrierPayslip.draft(run.getId(), "rider-b", figures("10.00", "0.00", "9.00"))))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void one_company_cannot_pay_the_same_day_in_two_runs() {
        String company = "company-" + UUID.randomUUID();
        run(company, "2026-10-01", "2026-10-15");

        // A monthly run over a half already run shares its first day; a second half-month run of
        // the month's end shares its last. Either way the day would be paid twice.
        assertThatThrownBy(() -> run(company, "2026-10-01", "2026-10-31"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void a_payroll_deduction_is_only_ever_a_hand_over() {
        assertThatCode(() -> em.createNativeQuery("""
                        INSERT INTO cash_float (id, holder_ref, holder_kind, amount, currency,
                                                entry_kind, carrier_ref, method)
                        VALUES (gen_random_uuid(), 'rider-a', 'RIDER', 10.00, 'USD',
                                'TRANSFERRED', 'company-a', 'PAYROLL_DEDUCTION')
                        """).executeUpdate())
                .doesNotThrowAnyException();
        // Booked as a remittance it would claim the platform received cash that stayed in a pocket.
        assertThatThrownBy(() -> em.createNativeQuery("""
                        INSERT INTO cash_float (id, holder_ref, holder_kind, amount, currency,
                                                entry_kind, method)
                        VALUES (gen_random_uuid(), 'rider-a', 'RIDER', 10.00, 'USD',
                                'REMITTED', 'PAYROLL_DEDUCTION')
                        """).executeUpdate())
                .isInstanceOf(PersistenceException.class);
    }

    @Test
    void a_run_keeps_one_copy_of_each_riders_hours() {
        CarrierPayRun run = run("company-" + UUID.randomUUID(), "2026-10-01", "2026-10-15");
        snapshots.saveAndFlush(CarrierPayAttendance.of(run.getId(), "rider-a", 3600, 0, 0, 0, 0));

        assertThatThrownBy(() -> snapshots.saveAndFlush(
                CarrierPayAttendance.of(run.getId(), "rider-a", 7200, 0, 0, 0, 0)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void a_run_keeps_one_count_of_each_riders_deliveries() {
        CarrierPayRun run = run("company-" + UUID.randomUUID(), "2026-10-01", "2026-10-15");
        deliveredCopies.saveAndFlush(CarrierPayDelivered.of(run.getId(), "rider-a", 17));

        assertThatThrownBy(() -> deliveredCopies.saveAndFlush(
                CarrierPayDelivered.of(run.getId(), "rider-a", 18)))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}

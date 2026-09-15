package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.accounting.domain.CarrierPayAdjustment;
import com.delivery.accounting.domain.CarrierPayLine;
import com.delivery.accounting.domain.CarrierPayLine.Kind;
import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayPolicy.PayCycle;
import com.delivery.accounting.domain.CarrierPayRun.Attendance;
import com.delivery.accounting.domain.CarrierPayslip;
import com.delivery.accounting.service.PayslipCalculator.Inputs;
import com.delivery.accounting.service.PayslipCalculator.Payslip;
import com.delivery.accounting.service.PayslipCalculator.RiderHours;

/**
 * Payslip maths. Each test is a rule a rider could be under- or over-paid by: the rate, the hour, the
 * round-off, the penalty, the tip that is not the company's, and the cash that is either all netted
 * or not netted at all.
 */
@DisplayName("payslip maths")
class PayslipCalculatorTest {

    private static final String YOUSSEF = "rider-youssef";
    private static final String RANIA = "rider-rania";
    private static final UUID RUN = UUID.randomUUID();

    private static BigDecimal m(String amount) {
        return new BigDecimal(amount);
    }

    private static CarrierPayPolicy.Terms perDelivery(String rate) {
        return new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, m(rate), null, true, m("1.00"),
                m("0.00"), m("0.00"));
    }

    private static CarrierPayPolicy.Terms hourly(String perDelivery, String hourly,
                                                 boolean payManual, String multiplier) {
        return new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, m(perDelivery), m(hourly),
                payManual, m(multiplier), m("0.00"), m("0.00"));
    }

    private static Inputs inputs(CarrierPayPolicy.Terms terms, Attendance attendance,
                                 Map<String, Integer> deliveries, Map<String, RiderHours> hours,
                                 Map<String, BigDecimal> cash) {
        return new Inputs(terms, attendance, deliveries, Map.of(), hours, cash, List.of(), List.of());
    }

    private static Payslip only(List<Payslip> slips) {
        assertThat(slips).hasSize(1);
        return slips.get(0);
    }

    /** Gross, deductions and net must be exactly the lines, whatever else a test checks. */
    private static void addsUp(Payslip slip, List<CarrierPayLine> named) {
        BigDecimal earned = m("0.00");
        BigDecimal taken = m("0.00");
        for (PayslipCalculator.Line line : slip.lines()) {
            if (line.kind().isDeduction()) {
                taken = taken.add(line.amount());
            } else {
                earned = earned.add(line.amount());
            }
        }
        for (CarrierPayLine line : named) {
            if (line.getKind().isDeduction()) {
                taken = taken.add(line.getAmount());
            } else {
                earned = earned.add(line.getAmount());
            }
        }
        CarrierPayslip.Figures f = slip.figures();
        assertThat(f.gross()).isEqualByComparingTo(earned);
        assertThat(f.deductions()).isEqualByComparingTo(taken);
        assertThat(f.net()).isEqualByComparingTo(earned.subtract(taken));
        assertThat(f.gross()).isEqualByComparingTo(f.basePay().add(f.deliveryPay()).add(f.bonuses()));
    }

    @Test
    @DisplayName("pays each delivery at the rate, to the cent")
    void deliveries() {
        Payslip slip = only(PayslipCalculator.compute(inputs(perDelivery("2.35"),
                Attendance.NOT_NEEDED, Map.of(YOUSSEF, 17), Map.of(), Map.of())));

        assertThat(slip.figures().deliveries()).isEqualTo(17);
        assertThat(slip.figures().deliveryPay()).isEqualByComparingTo("39.95");
        assertThat(slip.figures().net()).isEqualByComparingTo("39.95");
        assertThat(slip.lines()).singleElement().satisfies(line -> {
            assertThat(line.kind()).isEqualTo(Kind.DELIVERIES);
            assertThat(line.quantity()).isEqualByComparingTo("17");
            assertThat(line.rate()).isEqualByComparingTo("2.35");
        });
        // No hours were asked for, so none are claimed: unknown, not zero.
        assertThat(slip.figures().workedSeconds()).isNull();
        addsUp(slip, List.of());
    }

    @Test
    @DisplayName("nobody who did nothing gets a payslip, and an empty period is no payslips at all")
    void noDeliveries() {
        assertThat(PayslipCalculator.compute(inputs(perDelivery("2.00"), Attendance.NOT_NEEDED,
                Map.of(), Map.of(), Map.of()))).isEmpty();
        assertThat(PayslipCalculator.compute(inputs(perDelivery("2.00"), Attendance.NOT_NEEDED,
                Map.of(YOUSSEF, 0), Map.of(), Map.of(YOUSSEF, m("45.00"))))).isEmpty();
    }

    @Test
    @DisplayName("hours: ordinary, overtime at the multiplier, and typed hours on their own line")
    void hoursOvertimeAndTypedHours() {
        // 10h recorded of which 2h overtime, and 1h30 typed by the office.
        RiderHours h = new RiderHours(36_000, 5_400, 7_200, 0, 0);
        Payslip slip = only(PayslipCalculator.compute(inputs(hourly("0.00", "4.00", true, "1.50"),
                Attendance.INCLUDED, Map.of(), Map.of(YOUSSEF, h), Map.of())));

        assertThat(slip.lines()).extracting(PayslipCalculator.Line::kind)
                .containsExactly(Kind.HOURS, Kind.OVERTIME, Kind.MANUAL_HOURS);
        assertThat(slip.lines().get(0).amount()).isEqualByComparingTo("32.00");
        assertThat(slip.lines().get(0).quantity()).isEqualByComparingTo("8");
        assertThat(slip.lines().get(1).rate()).isEqualByComparingTo("6.00");
        assertThat(slip.lines().get(1).amount()).isEqualByComparingTo("12.00");
        assertThat(slip.lines().get(2).amount()).isEqualByComparingTo("6.00");
        assertThat(slip.figures().basePay()).isEqualByComparingTo("50.00");
        assertThat(slip.figures().manualSeconds()).isEqualTo(5_400L);
        addsUp(slip, List.of());
    }

    @Test
    @DisplayName("an overtime multiplier of 1.00 pays overtime as an ordinary hour")
    void defaultMultiplier() {
        RiderHours h = new RiderHours(36_000, 0, 7_200, 0, 0);
        Payslip slip = only(PayslipCalculator.compute(inputs(hourly("0.00", "4.00", true, "1.00"),
                Attendance.INCLUDED, Map.of(), Map.of(YOUSSEF, h), Map.of())));

        assertThat(slip.figures().basePay()).isEqualByComparingTo("40.00");
    }

    @Test
    @DisplayName("typed hours the policy does not pay are still shown, at nothing")
    void typedHoursUnpaid() {
        RiderHours h = new RiderHours(3_600, 7_200, 0, 0, 0);
        Payslip slip = only(PayslipCalculator.compute(inputs(hourly("0.00", "5.00", false, "1.00"),
                Attendance.INCLUDED, Map.of(), Map.of(YOUSSEF, h), Map.of())));

        PayslipCalculator.Line typed = slip.lines().get(1);
        assertThat(typed.kind()).isEqualTo(Kind.MANUAL_HOURS);
        assertThat(typed.quantity()).isEqualByComparingTo("2");
        assertThat(typed.rate()).isNull();
        assertThat(typed.amount()).isEqualByComparingTo("0.00");
        assertThat(slip.figures().basePay()).isEqualByComparingTo("5.00");
    }

    @Test
    @DisplayName("each line is rounded once, half up, and the payslip is exactly its lines")
    void rounding() {
        // 3.33 an hour for 1234 seconds is 1.14145; one cent an hour for half an hour is 0.005.
        Payslip slip = only(PayslipCalculator.compute(inputs(hourly("0.00", "3.33", true, "1.00"),
                Attendance.INCLUDED, Map.of(), Map.of(YOUSSEF, new RiderHours(1_234, 0, 0, 0, 0)),
                Map.of())));
        assertThat(slip.figures().basePay()).isEqualByComparingTo("1.14");

        Payslip halfCent = only(PayslipCalculator.compute(inputs(hourly("0.00", "0.01", true, "1.00"),
                Attendance.INCLUDED, Map.of(), Map.of(RANIA, new RiderHours(1_800, 0, 0, 0, 0)),
                Map.of())));
        assertThat(halfCent.figures().basePay()).isEqualByComparingTo("0.01");
        addsUp(slip, List.of());
    }

    @Test
    @DisplayName("lateness and absence are taken per unexcused day, at the company's rates")
    void penalties() {
        CarrierPayPolicy.Terms terms = new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, m("2.00"),
                null, true, m("1.00"), m("2.00"), m("10.00"));
        Payslip slip = only(PayslipCalculator.compute(inputs(terms, Attendance.INCLUDED,
                Map.of(YOUSSEF, 30), Map.of(YOUSSEF, new RiderHours(0, 0, 0, 3, 1)), Map.of())));

        assertThat(slip.lines()).extracting(PayslipCalculator.Line::kind)
                .containsExactly(Kind.DELIVERIES, Kind.LATE_DEDUCTION, Kind.ABSENCE_DEDUCTION);
        assertThat(slip.figures().deductions()).isEqualByComparingTo("16.00");
        assertThat(slip.figures().net()).isEqualByComparingTo("44.00");
        addsUp(slip, List.of());
    }

    @Test
    @DisplayName("a net below zero is shown as it is, never raised to zero")
    void negativeNet() {
        CarrierPayPolicy.Terms terms = new CarrierPayPolicy.Terms(PayCycle.SEMI_MONTHLY, m("2.00"),
                null, true, m("1.00"), m("0.00"), m("10.00"));
        Payslip slip = only(PayslipCalculator.compute(inputs(terms, Attendance.INCLUDED,
                Map.of(YOUSSEF, 2), Map.of(YOUSSEF, new RiderHours(0, 0, 0, 0, 1)), Map.of())));

        assertThat(slip.figures().net()).isEqualByComparingTo("-6.00");
        addsUp(slip, List.of());
    }

    @Test
    @DisplayName("a tip is the rider's own money: shown, and in neither gross nor net")
    void tipsAreNotPay() {
        Inputs in = new Inputs(perDelivery("2.00"), Attendance.NOT_NEEDED,
                Map.of(YOUSSEF, 5), Map.of(YOUSSEF, m("15.00"), RANIA, m("7.00")), Map.of(),
                Map.of(), List.of(), List.of());
        Payslip slip = only(PayslipCalculator.compute(in));

        assertThat(slip.riderRef()).isEqualTo(YOUSSEF);
        assertThat(slip.figures().tips()).isEqualByComparingTo("15.00");
        assertThat(slip.figures().gross()).isEqualByComparingTo("10.00");
        assertThat(slip.figures().net()).isEqualByComparingTo("10.00");
    }

    @Test
    @DisplayName("cash the pay covers is netted whole, as its own deduction")
    void cashNetted() {
        Payslip slip = only(PayslipCalculator.compute(inputs(perDelivery("2.00"),
                Attendance.NOT_NEEDED, Map.of(YOUSSEF, 50), Map.of(), Map.of(YOUSSEF, m("60.00")))));

        assertThat(slip.figures().cashHeld()).isEqualByComparingTo("60.00");
        assertThat(slip.figures().cashNetted()).isEqualByComparingTo("60.00");
        assertThat(slip.figures().net()).isEqualByComparingTo("40.00");
        assertThat(slip.lines()).extracting(PayslipCalculator.Line::kind).contains(Kind.CASH_HELD);
        addsUp(slip, List.of());

        Payslip exact = only(PayslipCalculator.compute(inputs(perDelivery("2.00"),
                Attendance.NOT_NEEDED, Map.of(YOUSSEF, 25), Map.of(), Map.of(YOUSSEF, m("50.00")))));
        assertThat(exact.figures().cashNetted()).isEqualByComparingTo("50.00");
        assertThat(exact.figures().net()).isEqualByComparingTo("0.00");
    }

    @Test
    @DisplayName("cash the pay cannot cover is not netted at all — never part of a bag")
    void cashNotNetted() {
        Payslip slip = only(PayslipCalculator.compute(inputs(perDelivery("2.00"),
                Attendance.NOT_NEEDED, Map.of(YOUSSEF, 25), Map.of(), Map.of(YOUSSEF, m("80.00")))));

        assertThat(slip.figures().cashHeld()).isEqualByComparingTo("80.00");
        assertThat(slip.figures().cashNetted()).isEqualByComparingTo("0.00");
        assertThat(slip.figures().net()).isEqualByComparingTo("50.00");
        assertThat(slip.lines()).extracting(PayslipCalculator.Line::kind)
                .doesNotContain(Kind.CASH_HELD);
    }

    @Test
    @DisplayName("cash is netted against what is left after the other deductions")
    void cashAfterOtherDeductions() {
        CarrierPayLine uniform = CarrierPayLine.manual(RUN, YOUSSEF, Kind.DEDUCTION, "Uniform",
                m("30.00"), "staff", Instant.now());
        Inputs in = new Inputs(perDelivery("2.00"), Attendance.NOT_NEEDED, Map.of(YOUSSEF, 50),
                Map.of(), Map.of(), Map.of(YOUSSEF, m("80.00")), List.of(uniform), List.of());
        Payslip slip = only(PayslipCalculator.compute(in));

        // 100 earned, 30 taken for the uniform: 70 left does not cover an 80 bag.
        assertThat(slip.figures().cashNetted()).isEqualByComparingTo("0.00");
        assertThat(slip.figures().net()).isEqualByComparingTo("70.00");
        addsUp(slip, List.of(uniform));
    }

    @Test
    @DisplayName("named lines and corrections from earlier runs are counted; a removed line is not")
    void namedLinesAndCorrections() {
        CarrierPayLine eid = CarrierPayLine.manual(RUN, YOUSSEF, Kind.BONUS, "Eid bonus", m("25.00"),
                "staff", Instant.now());
        CarrierPayLine removed = CarrierPayLine.manual(RUN, YOUSSEF, Kind.BONUS, "Typo", m("999.00"),
                "staff", Instant.now());
        removed.remove("staff", Instant.now());
        CarrierPayAdjustment overpaid = CarrierPayAdjustment.of("provider-77", UUID.randomUUID(),
                YOUSSEF, Kind.DEDUCTION, m("4.50"), "Double-counted job on the 3rd", "staff",
                Instant.now());
        // A correction alone is enough for a payslip: the rider is owed or owes it.
        CarrierPayAdjustment missed = CarrierPayAdjustment.of("provider-77", UUID.randomUUID(),
                RANIA, Kind.BONUS, m("6.00"), "Two jobs missed", "staff", Instant.now());

        Inputs in = new Inputs(perDelivery("2.00"), Attendance.NOT_NEEDED, Map.of(YOUSSEF, 10),
                Map.of(), Map.of(), Map.of(), List.of(eid, removed), List.of(overpaid, missed));
        List<Payslip> slips = PayslipCalculator.compute(in);

        assertThat(slips).extracting(Payslip::riderRef).containsExactly(RANIA, YOUSSEF);
        Payslip youssef = slips.get(1);
        assertThat(youssef.figures().bonuses()).isEqualByComparingTo("25.00");
        assertThat(youssef.figures().deductions()).isEqualByComparingTo("4.50");
        assertThat(youssef.figures().net()).isEqualByComparingTo("40.50");
        assertThat(youssef.lines()).filteredOn(line -> line.adjustment() != null)
                .singleElement()
                .satisfies(line -> assertThat(line.adjustment()).isSameAs(overpaid));
        addsUp(youssef, List.of(eid));

        assertThat(slips.get(0).figures().net()).isEqualByComparingTo("6.00");
    }

    @Test
    @DisplayName("hours that could not be read are left out, and deliveries are still paid")
    void attendanceUnavailable() {
        Payslip slip = only(PayslipCalculator.compute(inputs(hourly("2.00", "4.00", true, "1.00"),
                Attendance.UNAVAILABLE, Map.of(YOUSSEF, 3),
                Map.of(YOUSSEF, new RiderHours(36_000, 0, 0, 0, 0)), Map.of())));

        assertThat(slip.figures().workedSeconds()).isNull();
        assertThat(slip.figures().basePay()).isEqualByComparingTo("0.00");
        assertThat(slip.figures().net()).isEqualByComparingTo("6.00");
    }

    @Test
    @DisplayName("a rider the attendance read does not list has unknown hours, not zero")
    void riderMissingFromAttendance() {
        List<Payslip> slips = PayslipCalculator.compute(inputs(hourly("2.00", "4.00", true, "1.00"),
                Attendance.INCLUDED, Map.of(YOUSSEF, 3, RANIA, 1),
                Map.of(RANIA, new RiderHours(7_200, 0, 0, 0, 0)), Map.of()));

        assertThat(slips.get(1).riderRef()).isEqualTo(YOUSSEF);
        assertThat(slips.get(1).figures().workedSeconds()).isNull();
        assertThat(slips.get(0).figures().workedSeconds()).isEqualTo(7_200L);
        assertThat(slips.get(0).figures().basePay()).isEqualByComparingTo("8.00");
    }

    @Test
    @DisplayName("the same facts give the same payslips, to the cent")
    void reproducible() {
        Inputs in = new Inputs(hourly("2.35", "3.33", true, "1.25"), Attendance.INCLUDED,
                Map.of(YOUSSEF, 13, RANIA, 4), Map.of(YOUSSEF, m("3.00")),
                Map.of(YOUSSEF, new RiderHours(50_001, 1_799, 4_321, 1, 0)),
                Map.of(RANIA, m("5.40")), List.of(), List.of());

        List<Payslip> first = PayslipCalculator.compute(in);
        List<Payslip> again = PayslipCalculator.compute(in);
        assertThat(first).hasSameSizeAs(again);
        for (int i = 0; i < first.size(); i++) {
            assertThat(first.get(i).figures().sameAs(again.get(i).figures())).isTrue();
        }
    }
}

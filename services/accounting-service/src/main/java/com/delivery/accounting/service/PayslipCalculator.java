package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import com.delivery.accounting.domain.CarrierPayAdjustment;
import com.delivery.accounting.domain.CarrierPayLine;
import com.delivery.accounting.domain.CarrierPayLine.Kind;
import com.delivery.accounting.domain.CarrierPayPolicy;
import com.delivery.accounting.domain.CarrierPayRun;
import com.delivery.accounting.domain.CarrierPayslip;

/**
 * A delivery company's pay rules and one period's facts, turned into payslips.
 *
 * <p><strong>Pure</strong>: no clock, no database, no network. The same inputs give the same payslips
 * to the cent, which is what lets an approval recompute a draft and refuse when anything moved, and
 * what lets every rule below be proved without a running service.
 *
 * <p><strong>The rules, in the order they apply.</strong>
 * <ol>
 *   <li>Deliveries times the per-delivery rate. A delivery is one JOB_EARNING row for the company.</li>
 *   <li>With an hourly rate: ordinary recorded hours, overtime hours at the multiplier, and hours the
 *       office typed — paid or not by the policy, on their own line either way, because a typed hour
 *       is a claim and a recorded one is evidence, and the payslip must not blur the two.</li>
 *   <li>Lateness and absence deductions, per unexcused day as order-tracking judged it. A rider
 *       with no schedule is never late or absent there, so they never lose pay here.</li>
 *   <li>The company's named bonuses and deductions, and corrections carried in from earlier runs.</li>
 *   <li>Cash the rider holds for the company, kept out of their pay — <strong>all of it or none
 *       of it</strong>. A hand-over clears a rider's whole bag or nothing, so cash is only netted
 *       when what is left of the pay covers it. Otherwise it stays in their bag, where the company's
 *       cash page keeps chasing it, rather than being deducted here while the float still shows the
 *       rider holding part of it.</li>
 * </ol>
 *
 * <p><strong>Rounding.</strong> Each line is rounded to the cent once, half up, from exact inputs
 * (whole seconds, two-decimal rates); the totals are sums of those lines, so a payslip always adds
 * up to exactly what its lines say.
 *
 * <p><strong>Tips</strong> are carried for information and added to nothing: they are the rider's own
 * money, never the company's to pay.
 *
 * <p><strong>Net may be negative</strong> — deductions a company set can exceed the pay — and is never
 * clamped: a figure silently raised to zero is a debt nobody can see.
 */
public final class PayslipCalculator {

    private static final BigDecimal SECONDS_PER_HOUR = BigDecimal.valueOf(3600);
    private static final BigDecimal ZERO = money(BigDecimal.ZERO);

    private PayslipCalculator() {
    }

    /**
     * One rider's attendance totals for the period, as order-tracking judged them. Seconds are exact;
     * order-tracking's hours are display only and never read.
     */
    public record RiderHours(long workedSeconds, long manualSeconds, long overtimeSeconds,
                             int lates, int absences) {
    }

    /**
     * Everything a period's payslips are computed from.
     *
     * @param attendance whether {@code hours} was read; when it was not, no rider has hours at all
     * @param deliveries rider to delivered jobs for the company in the period
     * @param tips       rider to tips in the period, informational
     * @param hours      rider to attendance totals; a rider absent from it has unknown hours
     * @param cashHeld   rider to what they hold for the company right now
     * @param namedLines the company's live named bonuses and deductions on this draft
     * @param adjustments corrections to earlier runs not yet paid
     */
    public record Inputs(CarrierPayPolicy.Terms terms, CarrierPayRun.Attendance attendance,
                         Map<String, Integer> deliveries, Map<String, BigDecimal> tips,
                         Map<String, RiderHours> hours, Map<String, BigDecimal> cashHeld,
                         List<CarrierPayLine> namedLines, List<CarrierPayAdjustment> adjustments) {
    }

    /**
     * A line this computation produced: from the rules, or a correction carried in. The company's own
     * named lines already exist and are counted, not repeated.
     *
     * @param adjustment the correction a carried line pays, or null for a computed line
     */
    public record Line(Kind kind, BigDecimal quantity, BigDecimal rate, BigDecimal amount,
                       CarrierPayAdjustment adjustment) {
    }

    public record Payslip(String riderRef, CarrierPayslip.Figures figures, List<Line> lines) {
    }

    /** One payslip per rider with anything to pay or account for, in rider order. */
    public static List<Payslip> compute(Inputs in) {
        CarrierPayPolicy.Terms terms = in.terms();
        boolean withHours = in.attendance() == CarrierPayRun.Attendance.INCLUDED;

        // Who gets a payslip: anyone who delivered, anyone with paid hours, anyone the company named
        // a line for, and anyone owed or owing a correction. Nobody gets one for penalties alone or
        // for holding cash alone: with no pay there is nothing to take them from.
        Set<String> riders = new TreeSet<>();
        in.deliveries().forEach((rider, count) -> {
            if (count != null && count > 0) {
                riders.add(rider);
            }
        });
        if (withHours && terms.hourlyRate() != null && terms.hourlyRate().signum() > 0) {
            in.hours().forEach((rider, h) -> {
                long paid = Math.max(0, h.workedSeconds())
                        + (terms.payManualHours() ? Math.max(0, h.manualSeconds()) : 0);
                if (paid > 0) {
                    riders.add(rider);
                }
            });
        }
        in.namedLines().forEach(line -> riders.add(line.getRiderRef()));
        in.adjustments().forEach(adjustment -> riders.add(adjustment.getRiderRef()));

        List<Payslip> out = new ArrayList<>(riders.size());
        for (String rider : riders) {
            out.add(payslip(rider, in, withHours ? in.hours().get(rider) : null));
        }
        return List.copyOf(out);
    }

    private static Payslip payslip(String rider, Inputs in, RiderHours h) {
        CarrierPayPolicy.Terms terms = in.terms();
        List<Line> lines = new ArrayList<>();

        int count = Math.max(0, in.deliveries().getOrDefault(rider, 0));
        BigDecimal deliveryPay = money(terms.perDeliveryRate().multiply(BigDecimal.valueOf(count)));
        if (count > 0) {
            lines.add(new Line(Kind.DELIVERIES, BigDecimal.valueOf(count), terms.perDeliveryRate(),
                    deliveryPay, null));
        }

        BigDecimal basePay = ZERO;
        BigDecimal penalties = ZERO;
        if (h != null) {
            BigDecimal hourly = terms.hourlyRate();
            if (hourly != null) {
                long worked = Math.max(0, h.workedSeconds());
                long overtime = Math.min(Math.max(0, h.overtimeSeconds()), worked);
                long ordinary = worked - overtime;
                if (ordinary > 0) {
                    BigDecimal amount = perHour(hourly, ordinary);
                    lines.add(new Line(Kind.HOURS, hours(ordinary), hourly, amount, null));
                    basePay = basePay.add(amount);
                }
                if (overtime > 0) {
                    BigDecimal rate = hourly.multiply(terms.overtimeMultiplier());
                    BigDecimal amount = perHour(rate, overtime);
                    lines.add(new Line(Kind.OVERTIME, hours(overtime), rate, amount, null));
                    basePay = basePay.add(amount);
                }
                long manual = Math.max(0, h.manualSeconds());
                if (manual > 0) {
                    if (terms.payManualHours()) {
                        BigDecimal amount = perHour(hourly, manual);
                        lines.add(new Line(Kind.MANUAL_HOURS, hours(manual), hourly, amount, null));
                        basePay = basePay.add(amount);
                    } else {
                        // Shown at nothing, so the payslip still says the office logged them.
                        lines.add(new Line(Kind.MANUAL_HOURS, hours(manual), null, ZERO, null));
                    }
                }
            }
            if (terms.lateDeduction().signum() > 0 && h.lates() > 0) {
                BigDecimal amount = money(terms.lateDeduction().multiply(BigDecimal.valueOf(h.lates())));
                lines.add(new Line(Kind.LATE_DEDUCTION, BigDecimal.valueOf(h.lates()),
                        terms.lateDeduction(), amount, null));
                penalties = penalties.add(amount);
            }
            if (terms.absenceDeduction().signum() > 0 && h.absences() > 0) {
                BigDecimal amount = money(
                        terms.absenceDeduction().multiply(BigDecimal.valueOf(h.absences())));
                lines.add(new Line(Kind.ABSENCE_DEDUCTION, BigDecimal.valueOf(h.absences()),
                        terms.absenceDeduction(), amount, null));
                penalties = penalties.add(amount);
            }
        }

        BigDecimal bonuses = ZERO;
        BigDecimal named = ZERO;
        for (CarrierPayLine line : in.namedLines()) {
            if (rider.equals(line.getRiderRef()) && !line.isRemoved()) {
                if (line.getKind().isDeduction()) {
                    named = named.add(money(line.getAmount()));
                } else {
                    bonuses = bonuses.add(money(line.getAmount()));
                }
            }
        }
        for (CarrierPayAdjustment adjustment : in.adjustments()) {
            if (rider.equals(adjustment.getRiderRef())) {
                BigDecimal amount = money(adjustment.getAmount());
                lines.add(new Line(adjustment.getKind(), null, null, amount, adjustment));
                if (adjustment.getKind().isDeduction()) {
                    named = named.add(amount);
                } else {
                    bonuses = bonuses.add(amount);
                }
            }
        }

        BigDecimal gross = basePay.add(deliveryPay).add(bonuses);
        BigDecimal otherDeductions = penalties.add(named);

        BigDecimal held = money(in.cashHeld().getOrDefault(rider, BigDecimal.ZERO));
        BigDecimal left = gross.subtract(otherDeductions);
        BigDecimal netted = held.signum() > 0 && left.compareTo(held) >= 0 ? held : ZERO;
        if (netted.signum() > 0) {
            lines.add(new Line(Kind.CASH_HELD, null, null, netted, null));
        }

        BigDecimal deductions = otherDeductions.add(netted);
        BigDecimal net = gross.subtract(deductions);

        CarrierPayslip.Figures figures = new CarrierPayslip.Figures(count,
                h == null ? null : h.workedSeconds(),
                h == null ? null : h.manualSeconds(),
                h == null ? null : h.overtimeSeconds(),
                h == null ? null : h.lates(),
                h == null ? null : h.absences(),
                basePay, deliveryPay, bonuses, deductions, gross, net,
                money(in.tips().getOrDefault(rider, BigDecimal.ZERO)), held, netted);
        return new Payslip(rider, figures, List.copyOf(lines));
    }

    /** {@code rate} per hour for {@code seconds}, rounded to the cent once. */
    private static BigDecimal perHour(BigDecimal rate, long seconds) {
        return rate.multiply(BigDecimal.valueOf(seconds))
                .divide(SECONDS_PER_HOUR, 2, RoundingMode.HALF_UP);
    }

    /** Hours for the payslip to print. Display only: the amount is computed from the seconds. */
    private static BigDecimal hours(long seconds) {
        return BigDecimal.valueOf(seconds).divide(SECONDS_PER_HOUR, 4, RoundingMode.HALF_UP);
    }

    private static BigDecimal money(BigDecimal amount) {
        return (amount == null ? BigDecimal.ZERO : amount).setScale(2, RoundingMode.HALF_UP);
    }
}

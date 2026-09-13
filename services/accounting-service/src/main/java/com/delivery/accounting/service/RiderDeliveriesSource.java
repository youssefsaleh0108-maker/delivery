package com.delivery.accounting.service;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Map;

/**
 * Where a pay run counts its riders' deliveries: the orders each of them delivered for the company in
 * the period, as Order Manager — which owns every order and its status — counts them.
 *
 * <p><strong>Why not the ledger.</strong> This service learns of a job only by settling it, and writes
 * a rider's JOB_EARNING row only when the job earned their company a fee. A free delivery, a card
 * order whose payment has not been taken, or a job whose fee the platform's cut took whole, leaves no
 * row — so a company paying per delivery would silently not pay its rider for it. A delivery is a
 * delivered order, whatever it earned, so it is counted where orders are kept.
 *
 * <p><strong>Built to be absent</strong>, like {@link RiderAttendanceSource}: this never throws. When the
 * count cannot be had the pay run counts the ledger's rows instead — each one a real delivery, so a
 * floor rather than a guess — says so on the page, and approving it has to acknowledge that
 * deliveries without a fee may be missing.
 */
public interface RiderDeliveriesSource {

    /**
     * Every rider's delivered orders for the caller's company, over a period of at most 31 days.
     *
     * @param bearerToken the signed-in carrier's own token: Order Manager scopes the count to the
     *                    caller's company itself, and there is no service role on the endpoint
     * @param carrierRef  the company the pay run is for. An answer about any other is refused
     * @param zone        the calendar the period's dates are in. An answer counted in another zone
     *                    put its deliveries on different days, and is refused
     */
    DeliveriesRead fleet(String bearerToken, String carrierRef, ZoneId zone, LocalDate from,
                         LocalDate to);

    /**
     * What came back.
     *
     * @param reason why it is unavailable, as a code the page words: {@code NOT_DEPLOYED},
     *               {@code REFUSED}, {@code PERIOD_REFUSED}, {@code UNREACHABLE}, {@code MISMATCH}
     *               or {@code UNREADABLE}; null when available
     * @param riders rider to delivered orders when available, a rider with none absent; empty
     *               otherwise
     */
    record DeliveriesRead(boolean available, String reason, Map<String, Integer> riders) {

        public static DeliveriesRead of(Map<String, Integer> riders) {
            return new DeliveriesRead(true, null, Map.copyOf(riders));
        }

        public static DeliveriesRead unavailable(String reason) {
            return new DeliveriesRead(false, reason, Map.of());
        }
    }
}

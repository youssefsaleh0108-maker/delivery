package com.delivery.accounting.payout;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * The provider that does not pay anybody: a human does, outside this system.
 *
 * <p>This is what the platform runs on today and it is not a stub. There is no payment processor
 * integrated — the same admission {@code SettlementService.SettlementMode} makes on the bank side —
 * so a cash-out is an operator taking money out of the platform's account, handing it to a rider,
 * and typing in the reference. Modelling that honestly is the whole design: {@code paid_via} says
 * {@code MANUAL}, {@code payment_ref} is whatever the operator quotes, and nobody reading the row
 * can mistake it for an automated transfer.
 *
 * <p><strong>It deliberately refuses to invent a reference.</strong> A payout with no reference
 * could be marked paid with a generated id, and that generated id would look exactly like a real
 * one in every screen that renders it — so the first time a rider disputed a payout the platform
 * would produce a number that means nothing. The operator has the real number; this makes them
 * type it.
 *
 * <p>This class is also why {@link RiderPayoutProvider} is an interface rather than a method: when
 * a processor is chosen, its implementation drops in beside this one and
 * {@code delivery.rider-payout.provider} switches to it, with nothing else changing.
 */
@Component
public class ManualPayoutProvider implements RiderPayoutProvider {

    public static final String NAME = "MANUAL";

    private static final Logger log = LoggerFactory.getLogger(ManualPayoutProvider.class);

    @Override
    public String name() {
        return NAME;
    }

    @Override
    public Payout pay(PayoutRequest request) {
        String reference = request.operatorReference();
        if (reference == null || reference.isBlank()) {
            return Payout.refused(NAME,
                    "A manual payout must quote the reference of the payment that was actually made");
        }

        // The amount and the rider are logged; the rider's payout note is NOT. Riders type wallet
        // handles and account details into it, and a payment instruction has no business in an
        // application log that ships to a central collector.
        log.info("Cash-out {} for rider {} recorded as paid by hand: {} {}",
                request.cashOutId(), request.riderRef(), request.amount(), request.currency());

        return Payout.settled(NAME, reference.strip());
    }
}

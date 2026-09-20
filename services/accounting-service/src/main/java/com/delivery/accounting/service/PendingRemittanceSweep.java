package com.delivery.accounting.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Settles, at start-up, the remittances written before a remittance could be settled without a
 * bank (RECON-06).
 *
 * <p>Under {@code LEDGER_ONLY} a new remittance is terminal as it is written. The ones recorded
 * before that were left PENDING for a Core Banking connector nobody deployed, and nothing ever
 * answered them: on dev the two banked hand-overs of the deep test kept {@code /summary}'s amount
 * at risk at 331.26 and the SettlementLegsStuck alert on for good. This hands them to the same step
 * a new remittance takes, once each time the service starts; it is idempotent, so a restart finds
 * nothing left to do.
 *
 * <p>A failure here is logged and never stops the service starting: the rows wait for the next
 * start, which is where they were anyway.
 */
@Component
public class PendingRemittanceSweep {

    private static final Logger log = LoggerFactory.getLogger(PendingRemittanceSweep.class);

    private final CashFloatService cashFloat;

    public PendingRemittanceSweep(CashFloatService cashFloat) {
        this.cashFloat = cashFloat;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        try {
            cashFloat.settlePendingRemittancesWithoutBank();
        } catch (RuntimeException e) {
            log.error("Could not settle the remittances left waiting for a bank; they are "
                    + "settled on the next start", e);
        }
    }
}

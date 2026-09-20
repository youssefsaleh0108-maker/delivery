package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.delivery.product.domain.SearchDemandDigestRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.MerchantUnmetDemand.Term;

/**
 * One message a week, to each merchant with a live shop: what their neighbours looked for and could
 * not find.
 *
 * <p><strong>One message per merchant, not per shop and not per term.</strong> The live shops are
 * walked in merchant order and folded into one message, so a merchant with four shops in Hamra hears
 * once; the ledger's unique key is the merchant and the week, so there is nowhere to put a second row
 * even if the job ran four times.
 *
 * <p><strong>Idempotent by claim, not by check</strong> ({@link DemandDigestClaim}): the ledger row
 * and the outbox event that carries the message share one commit, so a second run loses the insert
 * and raises nothing. Notifications Manager deduplicates again on the same key, so even an event the
 * relay delivers twice becomes one message.
 *
 * <p><strong>Preferences are the manager's to enforce, and that is why this goes through the
 * bus.</strong> {@code POST /api/notifications/direct} bypasses them by design; an event does not. A
 * merchant who has turned the digest off in their settings has no channel survive the check and is
 * sent nothing — while the ledger row still says the week was considered, which is what stops a
 * re-run trying again.
 *
 * <p>A merchant with nothing to tell them is not written down and not sent to. An empty digest is
 * worse than none: it teaches a merchant that the weekly message is noise.
 */
@Service
public class DemandDigestService {

    private static final Logger log = LoggerFactory.getLogger(DemandDigestService.class);

    /** How many terms one message names. Three lines is what somebody reads on a lock screen. */
    static final int TERMS_PER_MESSAGE = 3;

    private final StoreRepository stores;
    private final MerchantUnmetDemand unmet;
    private final SearchDemandDigestRepository digests;
    private final DemandDigestClaim claim;
    private final SeenKeys keys;
    private final DemandWeeks calendar;
    private final Clock clock;
    private final boolean enabled;

    public DemandDigestService(StoreRepository stores, MerchantUnmetDemand unmet,
                               SearchDemandDigestRepository digests, DemandDigestClaim claim,
                               SeenKeys keys, DemandWeeks calendar, Clock clock,
                               @Value("${delivery.demand.digest.enabled:true}") boolean enabled) {
        this.stores = stores;
        this.unmet = unmet;
        this.digests = digests;
        this.claim = claim;
        this.keys = keys;
        this.calendar = calendar;
        this.clock = clock;
        this.enabled = enabled;
    }

    /** The week a digest run reports on: the last one that finished. */
    public Instant weekToReport() {
        return calendar.lastCompleteWeek(clock.instant());
    }

    /**
     * Raises one digest for every merchant with a live shop and something to be told.
     *
     * @return how many merchants were told
     */
    public int sendFor(Instant weekStart) {
        if (!enabled) {
            log.debug("The weekly demand digest is switched off");
            return 0;
        }
        if (!keys.available()) {
            // The same fail-closed rule as the roll-up: without the secret the floor counts nobody,
            // so anything left in the week's table was computed under a floor that no longer holds.
            // Say it loudly — a digest that silently stops is a feature nobody notices is broken.
            log.warn("No weekly demand digest was sent for the week of {}: no demand-seen secret is "
                    + "set (DEMAND_SEEN_SECRET), and the floor counts distinct people", weekStart);
            return 0;
        }
        Map<String, List<Store>> byMerchant = new LinkedHashMap<>();
        for (Store shop : stores.findByStatusOrderByMerchantIdAscCreatedAtAsc(Store.Status.ACTIVE)) {
            byMerchant.computeIfAbsent(shop.getMerchantId(), id -> new ArrayList<>()).add(shop);
        }
        int sent = 0;
        for (Map.Entry<String, List<Store>> merchant : byMerchant.entrySet()) {
            // Asked before anything is computed: on a re-run this is the whole cost per merchant.
            if (digests.existsByWeekStartAndMerchantId(weekStart, merchant.getKey())) {
                continue;
            }
            List<Term> terms = unmet.topFor(merchant.getKey(), merchant.getValue(), weekStart,
                    TERMS_PER_MESSAGE);
            if (terms.isEmpty()) {
                continue;
            }
            if (claim.claimAndRaise(weekStart, merchant.getKey(), merchant.getValue().get(0), terms)) {
                sent++;
            }
        }
        log.info("Raised {} weekly demand digests for the week of {}", sent, weekStart);
        return sent;
    }
}

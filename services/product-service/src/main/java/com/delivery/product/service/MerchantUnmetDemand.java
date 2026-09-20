package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.SearchDemandWeek;
import com.delivery.product.domain.SearchDemandWeekRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;

/**
 * What a shop's own neighbourhood looked for and could not find — the Demand Radar's second read.
 *
 * <p>The radar already tells a merchant <em>where</em> people are ordering. This tells them
 * <em>what</em> people asked for and nobody nearby sold, which is the half a shop can act on: the
 * first is a map, the second is a shopping list.
 *
 * <p><strong>Only the shop's own areas.</strong> The area ids come from
 * {@link DeliveryZoneService#around(Store)} — placed areas within a fixed cap of the shop's pin — and
 * never from the request. That is the same control the density read uses, and it is what stops a
 * merchant with a coverage row in every district reading the whole city's demand.
 *
 * <p><strong>Nothing about who searched.</strong> A term, the area it was searched in, whether it
 * answered with nothing or only with something far away, and a rounded count. No time finer than a
 * week, no distance, no direction, no customer, no session, and no way to ask for one term rather
 * than the list. Every row it serves has already cleared the floor of
 * {@value UnmetDemand#MIN_SEARCHES} distinct searches, because rows under the floor were never
 * written.
 *
 * <p>Terms the merchant already sells are marked rather than dropped. "You stock this and people
 * near you still could not find it" is a different and more useful message than silence — it usually
 * means the item is out of stock, paused, or named something nobody types.
 */
@Service
public class MerchantUnmetDemand {

    private final SearchDemandWeekRepository weeks;
    private final DeliveryZoneService zones;
    private final StoreRepository stores;
    private final DemandWeeks calendar;
    private final UnmetDemand unmet;
    private final Clock clock;

    public MerchantUnmetDemand(SearchDemandWeekRepository weeks, DeliveryZoneService zones,
                               StoreRepository stores, DemandWeeks calendar, UnmetDemand unmet,
                               Clock clock) {
        this.weeks = weeks;
        this.zones = zones;
        this.stores = stores;
        this.calendar = calendar;
        this.unmet = unmet;
        this.clock = clock;
    }

    /**
     * One term an area looked for, as a merchant may see it.
     *
     * @param about       the count rounded to a band ({@link UnmetDemand#band}), never the count
     * @param alreadySold whether the merchant's own shops list something matching it
     */
    public record Term(UUID areaId, String areaName, String region, SearchDemandWeek.Kind kind,
                       String term, int about, int rank, boolean alreadySold) {
    }

    /** One week's terms, best first. */
    public record Week(Instant weekStart, List<Term> terms) {
    }

    /**
     * @param areasAround     how many areas the shop's neighbourhood has at all. Zero means the
     *                        platform does not know where the shop is yet — a different thing to say
     *                        than "nothing went unanswered"
     * @param minimumSearches the floor, so the screen can say why a quiet week is empty
     * @param farMetres       what "too far" meant this week
     */
    public record Report(UUID storeId, String region, int areasAround, int minimumSearches,
                         int farMetres, Week thisWeek, Week lastWeek) {
    }

    /**
     * This week and last, for one shop's neighbourhood.
     *
     * <p>The caller has already decided this shop may be looked at; this reads.
     */
    @Transactional(readOnly = true)
    public Report forStore(Store store) {
        DeliveryZoneService.Neighbourhood around = zones.around(store);
        Instant thisWeek = calendar.weekOf(clock.instant());
        Instant lastWeek = calendar.weekBefore(thisWeek);
        if (around.zones().isEmpty()) {
            return new Report(store.getId(), around.region(), 0, UnmetDemand.MIN_SEARCHES,
                    unmet.farMetres(), new Week(thisWeek, List.of()), new Week(lastWeek, List.of()));
        }

        Map<UUID, DeliveryZone> byId = new LinkedHashMap<>();
        around.zones().forEach(zone -> byId.put(zone.getId(), zone));
        List<SearchDemandWeek> rows = weeks
                .findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(
                        List.of(thisWeek, lastWeek), byId.keySet());
        Set<UUID> sold = soldBy(store.getMerchantId(), rows);

        List<Term> now = new ArrayList<>();
        List<Term> before = new ArrayList<>();
        for (SearchDemandWeek row : rows) {
            DeliveryZone area = byId.get(row.getAreaId());
            Term term = new Term(row.getAreaId(), area == null ? null : area.getName(),
                    area == null ? null : area.getRegion(), row.getKind(), row.getTerm(),
                    UnmetDemand.band(row.getSearches()), row.getRank(), sold.contains(row.getId()));
            (row.getWeekStart().equals(thisWeek) ? now : before).add(term);
        }
        now.sort(BEST_FIRST);
        before.sort(BEST_FIRST);
        return new Report(store.getId(), around.region(), around.zones().size(),
                UnmetDemand.MIN_SEARCHES, unmet.farMetres(),
                new Week(thisWeek, List.copyOf(now)), new Week(lastWeek, List.copyOf(before)));
    }

    /**
     * The three terms to tell a merchant about this week, across every live shop they own.
     *
     * <p>Terms they already sell are left out here, unlike on the screen: a weekly message has room
     * for three lines and they should be three things to put on the shelf, not a reminder that
     * something is out of stock. The screen, where there is room to explain, says both.
     *
     * @param liveShops the merchant's ACTIVE shops; a merchant with none has nothing to be told
     */
    @Transactional(readOnly = true)
    public List<Term> topFor(String merchantId, List<Store> liveShops, Instant weekStart, int limit) {
        Map<UUID, DeliveryZone> byId = new LinkedHashMap<>();
        for (Store shop : liveShops) {
            zones.around(shop).zones().forEach(zone -> byId.putIfAbsent(zone.getId(), zone));
        }
        if (byId.isEmpty()) {
            return List.of();
        }
        List<SearchDemandWeek> rows = weeks
                .findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(
                        List.of(weekStart), byId.keySet());
        if (rows.isEmpty()) {
            return List.of();
        }
        Set<UUID> sold = soldBy(merchantId, rows);

        // One line per term, however many of the merchant's areas asked for it: a shop does not need
        // to be told about nappies twice because two neighbouring areas both wanted them.
        Map<String, Term> best = new LinkedHashMap<>();
        for (SearchDemandWeek row : rows) {
            if (sold.contains(row.getId())) {
                continue;
            }
            DeliveryZone area = byId.get(row.getAreaId());
            Term term = new Term(row.getAreaId(), area == null ? null : area.getName(),
                    area == null ? null : area.getRegion(), row.getKind(), row.getTerm(),
                    UnmetDemand.band(row.getSearches()), row.getRank(), false);
            best.merge(row.getTerm(), term,
                    (a, b) -> BEST_FIRST.compare(a, b) <= 0 ? a : b);
        }
        List<Term> ordered = new ArrayList<>(best.values());
        ordered.sort(BEST_FIRST);
        return List.copyOf(ordered.subList(0, Math.min(limit, ordered.size())));
    }

    /**
     * Which of {@code rows} name something the merchant's shops already list.
     *
     * <p>One query over every row, matched on the folded name the search itself matched on (V37), so
     * a merchant selling "Nescafé Classic 200g" is not told their neighbours cannot find "nescafe".
     */
    private Set<UUID> soldBy(String merchantId, List<SearchDemandWeek> rows) {
        if (rows.isEmpty()) {
            return Set.of();
        }
        Set<UUID> shopIds = new LinkedHashSet<>();
        for (Store shop : stores.findByMerchantIdOrderByCreatedAtDesc(merchantId)) {
            shopIds.add(shop.getId());
        }
        if (shopIds.isEmpty()) {
            return Set.of();
        }
        return new HashSet<>(weeks.alreadySold(rows.stream().map(SearchDemandWeek::getId).toList(),
                shopIds));
    }

    /**
     * What a merchant should read first: the biggest demand, then nothing at all before merely far
     * away, then the term itself so two equal lines never swap places between refreshes.
     */
    private static final java.util.Comparator<Term> BEST_FIRST = java.util.Comparator
            .comparingInt((Term t) -> -t.about())
            .thenComparing(Term::kind)
            .thenComparingInt(Term::rank)
            .thenComparing(Term::term);
}

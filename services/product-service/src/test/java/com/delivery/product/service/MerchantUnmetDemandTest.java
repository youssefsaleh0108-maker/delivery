package com.delivery.product.service;

import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.DeliveryZone;
import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.SearchDemandWeek;
import com.delivery.product.domain.SearchDemandWeekRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.TestPin;
import com.delivery.product.service.MerchantUnmetDemand.Term;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The three lines a weekly message gets, chosen from everything the merchant's areas wanted.
 *
 * <p>The message has room for three, so what is left out matters as much as what is in. A word two
 * of the merchant's areas both wanted is one line, not two — a shop does not need to be told about
 * nappies twice because Hamra and Verdun both looked. A word they already sell is left out here,
 * unlike on the screen, because a message of three lines should be three things to put on the shelf.
 * And the most-wanted comes first, with nothing-at-all ahead of merely-far-away.
 */
@DisplayName("the three words a weekly message names")
class MerchantUnmetDemandTest {

    private static final Instant NOW = Instant.parse("2026-09-16T10:30:00Z");
    private static final String OWNER = "merchant-owner";

    private SearchDemandWeekRepository weeks;
    private DeliveryZoneService zones;
    private MerchantUnmetDemand merchant;
    private Instant week;

    private DeliveryZone hamra;
    private DeliveryZone verdun;
    private Store shop;

    @BeforeEach
    void setUp() {
        weeks = mock(SearchDemandWeekRepository.class);
        zones = mock(DeliveryZoneService.class);
        StoreRepository stores = mock(StoreRepository.class);
        UnmetDemand unmet = mock(UnmetDemand.class);
        DemandWeeks calendar = new DemandWeeks(ZoneId.of("Asia/Beirut"));
        week = calendar.weekOf(NOW);

        hamra = placed("Hamra", 33.8959d, 35.4787d);
        verdun = placed("Verdun", 33.8836d, 35.4790d);
        shop = liveShop();
        when(zones.around(shop))
                .thenReturn(new DeliveryZoneService.Neighbourhood("Beirut", 5_000,
                        List.of(hamra, verdun)));
        when(stores.findByMerchantIdOrderByCreatedAtDesc(anyString())).thenReturn(List.of(shop));
        when(weeks.alreadySold(anyCollection(), anyCollection())).thenReturn(List.of());

        merchant = new MerchantUnmetDemand(weeks, zones, stores, calendar, unmet,
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    @DisplayName("the most wanted first, nothing-at-all ahead of merely-far-away, and only three")
    void the_best_three() {
        answering(
                row(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 14, 1),
                row(hamra, "جبنة", SearchDemandWeek.Kind.FAR, 9, 1),
                row(verdun, "رز", SearchDemandWeek.Kind.NONE, 9, 1),
                row(verdun, "نسكافيه", SearchDemandWeek.Kind.NONE, 5, 2));

        List<Term> top = merchant.topFor(OWNER, List.of(shop), week, 3);

        // The band decides first, so the three at "about 5" are ordered by what they mean: two
        // nobody answered at all, then the one somebody sells two kilometres away, which is the
        // weaker reason to put something on a shelf. The fourth line does not fit and is dropped.
        assertThat(top).extracting(Term::term).containsExactly("حفاضات", "رز", "نسكافيه");
        assertThat(top).extracting(Term::about).containsExactly(10, 5, 5);
    }

    @Test
    @DisplayName("a word two of the merchant's areas both wanted is one line, not two")
    void one_line_per_word() {
        answering(
                row(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 9, 1),
                row(verdun, "حفاضات", SearchDemandWeek.Kind.NONE, 14, 1));

        List<Term> top = merchant.topFor(OWNER, List.of(shop), week, 3);

        assertThat(top).hasSize(1);
        // The area that wanted it most is the one named.
        assertThat(top.get(0).areaName()).isEqualTo("Verdun");
        assertThat(top.get(0).about()).isEqualTo(10);
    }

    @Test
    @DisplayName("a word the merchant already sells is not one of the three")
    void what_they_already_sell_is_left_out() {
        SearchDemandWeek sold = row(hamra, "نسكافيه", SearchDemandWeek.Kind.NONE, 14, 1);
        answering(sold, row(hamra, "حفاضات", SearchDemandWeek.Kind.NONE, 9, 2));
        when(weeks.alreadySold(anyCollection(), anyCollection())).thenReturn(List.of(sold.getId()));

        assertThat(merchant.topFor(OWNER, List.of(shop), week, 3))
                .extracting(Term::term).containsExactly("حفاضات");
    }

    @Test
    @DisplayName("a merchant whose shops have no neighbourhood is told nothing, and nothing is read")
    void no_neighbourhood_no_message() {
        when(zones.around(shop))
                .thenReturn(new DeliveryZoneService.Neighbourhood(null, null, List.of()));

        assertThat(merchant.topFor(OWNER, List.of(shop), week, 3)).isEmpty();
        org.mockito.Mockito.verify(weeks, org.mockito.Mockito.never())
                .findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(anyCollection(),
                        anyCollection());
    }

    // ------------------------------------------------------------------------------------ helpers

    private void answering(SearchDemandWeek... rows) {
        when(weeks.findByWeekStartInAndAreaIdInOrderByAreaIdAscKindAscRankAsc(anyCollection(),
                anyCollection())).thenReturn(List.of(rows));
    }

    private SearchDemandWeek row(DeliveryZone area, String term, SearchDemandWeek.Kind kind,
                                 int searches, int rank) {
        return new SearchDemandWeek(week, area.getId(), term, kind, searches, rank, NOW);
    }

    private static DeliveryZone placed(String name, double lat, double lng) {
        DeliveryZone zone = new DeliveryZone(name, "Beirut", 10);
        zone.placeAt(GeoPoint.of(lat, lng));
        return zone;
    }

    private static Store liveShop() {
        Store shop = new Store(OWNER, "Corner Grocer", Store.Vertical.GROCERY);
        shop.pinAt(GeoPoint.of(33.8977d, 35.4829d));
        shop.replaceHours(new ArrayList<>(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList()));
        TestPin.pinned(shop);
        shop.publish(Instant.parse("2026-01-01T00:00:00Z"));
        return shop;
    }

}

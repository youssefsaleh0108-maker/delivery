package com.delivery.product.service;

import java.sql.SQLException;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import com.delivery.product.domain.GeoPoint;
import com.delivery.product.domain.SearchDemandDigestRepository;
import com.delivery.product.domain.SearchDemandWeek;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreHours;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.domain.TestPin;
import com.delivery.product.service.MerchantUnmetDemand.Term;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The weekly message: who gets one, how many they get, and what a second run does.
 *
 * <p>The three promises, each as a test. <strong>One a week per merchant</strong>, however many
 * shops they own and however many terms their neighbourhood wanted — a merchant with four shops in
 * Hamra hears once. <strong>Only merchants with a live shop</strong>, because a draft shop has no
 * neighbourhood the platform will serve. <strong>A re-run sends nothing</strong>: the ledger row is
 * taken before the message is raised, and the second attempt finds it.
 *
 * <p>The ledger's unique key is proved against a real database in {@code SearchDemandDatabaseTest};
 * what is proved here is that the claim reads that refusal correctly and carries on with the rest of
 * the run rather than taking it down.
 */
@DisplayName("the weekly demand digest")
class DemandDigestTest {

    private static final Instant NOW = Instant.parse("2026-09-21T09:00:00Z");
    private static final Instant WEEK = new DemandWeeks(ZoneId.of("Asia/Beirut")).weekOf(NOW);

    private StoreRepository stores;
    private MerchantUnmetDemand unmet;
    private SearchDemandDigestRepository digests;
    private DemandDigestClaim claim;
    private DemandDigestService service;

    /** Whose week has been claimed, standing in for the unique key. */
    private final Set<String> claimed = new HashSet<>();
    private final List<String> raised = new ArrayList<>();

    @BeforeEach
    void setUp() {
        stores = mock(StoreRepository.class);
        unmet = mock(MerchantUnmetDemand.class);
        digests = mock(SearchDemandDigestRepository.class);
        claim = mock(DemandDigestClaim.class);

        when(digests.existsByWeekStartAndMerchantId(any(), anyString()))
                .thenAnswer(call -> claimed.contains(call.getArgument(1, String.class)));
        when(claim.claimAndRaise(any(), anyString(), any(), anyList())).thenAnswer(call -> {
            String merchantId = call.getArgument(1);
            if (!claimed.add(merchantId)) {
                return false;
            }
            raised.add(merchantId);
            return true;
        });

        service = new DemandDigestService(stores, unmet, digests, claim,
                new DemandWeeks(ZoneId.of("Asia/Beirut")), Clock.fixed(NOW, ZoneOffset.UTC), true);
    }

    @Test
    @DisplayName("a merchant with four live shops hears once, not four times and not once per term")
    void one_message_per_merchant() {
        live("merchant-a", 4);
        wanted("merchant-a", terms("حفاضات", "رز", "نسكافيه"));

        assertThat(service.sendFor(WEEK)).isEqualTo(1);
        assertThat(raised).containsExactly("merchant-a");
        verify(claim).claimAndRaise(eq(WEEK), eq("merchant-a"), any(), anyList());
    }

    @Test
    @DisplayName("only merchants with a live shop are asked about at all")
    void only_live_shops() {
        // The repository is asked for ACTIVE shops and nothing else: a draft never reaches the loop.
        live("merchant-a", 1);
        wanted("merchant-a", terms("حفاضات"));

        service.sendFor(WEEK);

        verify(stores).findByStatusOrderByMerchantIdAscCreatedAtAsc(Store.Status.ACTIVE);
        verify(unmet, never()).topFor(eq("merchant-draft"), anyList(), any(), anyInt());
    }

    @Test
    @DisplayName("a merchant with nothing to be told is neither written down nor sent to")
    void an_empty_week_is_not_a_message() {
        live("merchant-a", 1);
        wanted("merchant-a", List.of());

        assertThat(service.sendFor(WEEK)).isZero();
        verify(claim, never()).claimAndRaise(any(), anyString(), any(), anyList());
    }

    @Test
    @DisplayName("a second run of the same week sends nothing to anybody already told")
    void a_re_run_sends_nothing() {
        live("merchant-a", 1);
        live("merchant-b", 1);
        wanted("merchant-a", terms("حفاضات"));
        wanted("merchant-b", terms("رز"));

        assertThat(service.sendFor(WEEK)).isEqualTo(2);
        assertThat(service.sendFor(WEEK)).isZero();

        assertThat(raised).containsExactly("merchant-a", "merchant-b");
        verify(claim, times(2)).claimAndRaise(any(), anyString(), any(), anyList());
    }

    @Test
    @DisplayName("a merchant whose week another replica took mid-run does not stop the rest of the run")
    void a_lost_race_does_not_stop_the_run() {
        live("merchant-a", 1);
        live("merchant-b", 1);
        wanted("merchant-a", terms("حفاضات"));
        wanted("merchant-b", terms("رز"));
        // Another replica claimed merchant-a between the check and the insert.
        claimedElsewhere("merchant-a");

        assertThat(service.sendFor(WEEK)).isEqualTo(1);
        assertThat(raised).containsExactly("merchant-b");
    }

    @Test
    @DisplayName("switched off, nothing is claimed and nothing is sent")
    void switched_off_sends_nothing() {
        DemandDigestService off = new DemandDigestService(stores, unmet, digests, claim,
                new DemandWeeks(ZoneId.of("Asia/Beirut")), Clock.fixed(NOW, ZoneOffset.UTC), false);
        live("merchant-a", 1);
        wanted("merchant-a", terms("حفاضات"));

        assertThat(off.sendFor(WEEK)).isZero();
        verify(claim, never()).claimAndRaise(any(), anyString(), any(), anyList());
    }

    @Test
    @DisplayName("the week a run reports on is the last one that finished, in the platform's zone")
    void the_week_reported_on_is_the_last_complete_one() {
        // Monday 2026-09-21 at 09:00 UTC is Monday noon in Beirut: the week that finished that
        // morning is the one before.
        assertThat(service.weekToReport())
                .isEqualTo(Instant.parse("2026-09-13T21:00:00Z"));
    }

    // -------------------------------------------------------------------------- the claim's refusal

    @Test
    @DisplayName("the claim reads the unique key's refusal, however the layers wrapped it")
    void the_claim_reads_a_lost_race() {
        assertThat(DemandDigestClaim.alreadyTaken(
                new DataIntegrityViolationException("uq_search_demand_digest"))).isTrue();
        assertThat(DemandDigestClaim.alreadyTaken(new RuntimeException("wrapped",
                new SQLException("duplicate key", "23505")))).isTrue();
        assertThat(DemandDigestClaim.alreadyTaken(
                new RuntimeException("the database is down"))).isFalse();
        assertThat(DemandDigestClaim.alreadyTaken(
                new RuntimeException("io", new SQLException("connection lost", "08006")))).isFalse();
    }

    // ------------------------------------------------------------------------------------ helpers

    private final List<Store> allLive = new ArrayList<>();

    private void live(String merchantId, int howMany) {
        for (int i = 0; i < howMany; i++) {
            Store shop = new Store(merchantId, "Shop " + i, Store.Vertical.GROCERY);
            shop.pinAt(GeoPoint.of(33.8977d + i * 0.001d, 35.4829d));
            shop.replaceHours(Arrays.stream(DayOfWeek.values())
                    .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                    .toList());
            TestPin.pinned(shop);
            shop.publish(Instant.parse("2026-01-01T00:00:00Z"));
            allLive.add(shop);
        }
        when(stores.findByStatusOrderByMerchantIdAscCreatedAtAsc(Store.Status.ACTIVE))
                .thenReturn(List.copyOf(allLive));
    }

    private void wanted(String merchantId, List<Term> terms) {
        when(unmet.topFor(eq(merchantId), anyList(), eq(WEEK), anyInt())).thenReturn(terms);
    }

    private void claimedElsewhere(String merchantId) {
        claimed.add(merchantId);
        // ... but the pre-check does not see it: the row appeared after this run looked.
        when(digests.existsByWeekStartAndMerchantId(any(), eq(merchantId))).thenReturn(false);
    }

    private static List<Term> terms(String... words) {
        List<Term> terms = new ArrayList<>();
        for (int i = 0; i < words.length; i++) {
            terms.add(new Term(java.util.UUID.randomUUID(), "Hamra", "Beirut",
                    SearchDemandWeek.Kind.NONE, words[i], 10 - i, i + 1, false));
        }
        return terms;
    }
}

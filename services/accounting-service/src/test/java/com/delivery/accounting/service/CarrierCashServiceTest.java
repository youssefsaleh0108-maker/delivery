package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Pageable;
import org.springframework.test.util.ReflectionTestUtils;

import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatEntry.HolderKind;
import com.delivery.accounting.domain.CashFloatEntry.Kind;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerEntry.Fleet;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * What a delivery company's reconciliation page says, computed from the float rows behind it.
 *
 * <p>Three properties matter. The figures are the ledger's and nothing more — collected, held,
 * handed over, and what the platform credited the company for a rider's jobs. "Overdue" is a line
 * drawn by the server's configured limit, strictly past it. And a rider who never carried cash for
 * this company is not on this company's page, and asking for them is answered as if they did not
 * exist.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("a delivery company's cash page")
class CarrierCashServiceTest {

    private static final String COMPANY = "provider-77";
    private static final String YOUSSEF = "rider-youssef";
    private static final String RANIA = "rider-rania";
    private static final String MICHEL = "rider-michel";

    /** Noon on the day being looked at. With a 48-hour limit, the line is noon two days ago. */
    private static final Instant NOW = Instant.parse("2026-10-24T12:00:00Z");
    private static final LocalDate TODAY = LocalDate.parse("2026-10-24");

    @Mock
    private CashFloatRepository floats;
    @Mock
    private RiderLedgerRepository riderLedger;
    @Mock
    private AccountDirectory accounts;

    private CarrierCashService service;

    @BeforeEach
    void setUp() {
        service = new CarrierCashService(floats, riderLedger, accounts, 48, 24, "UTC", "USD",
                Clock.fixed(NOW, ZoneOffset.UTC));
        lenient().when(accounts.profileOf(anyString())).thenAnswer(i -> {
            String who = i.getArgument(0);
            return new AccountDirectory.Profile("ACC", switch (who) {
                case YOUSSEF -> "Youssef Kanaan";
                case RANIA -> "Rania Ghandour";
                case "staff-kamal" -> "Kamal M.";
                default -> null;
            }, null);
        });
    }

    /** A float row as the database would hand it back, with the default it stamps. */
    private static CashFloatEntry at(CashFloatEntry row, String createdAt) {
        ReflectionTestUtils.setField(row, "createdAt", Instant.parse(createdAt));
        return row;
    }

    private static CashFloatEntry collected(String rider, String amount, String createdAt) {
        return at(CashFloatEntry.collected(rider, HolderKind.RIDER, UUID.randomUUID(),
                new BigDecimal(amount), "USD", COMPANY), createdAt);
    }

    private static CashFloatEntry transfer(String rider, String amount, String createdAt) {
        return at(CashFloatEntry.transferred(rider, COMPANY, new BigDecimal(amount), "USD",
                new CashFloatEntry.Recorded("staff-kamal", CashFloatEntry.Method.CASH, null,
                        null)), createdAt);
    }

    private static RiderLedgerEntry job(String rider, UUID orderId, String amount, String company) {
        return RiderLedgerEntry.jobEarning(rider, orderId, new BigDecimal(amount), "USD",
                Fleet.CARRIER, company, "customer-1", NOW);
    }

    @Nested
    @DisplayName("the overview")
    class Overview {

        private final CashFloatEntry youssefToday = collected(YOUSSEF, "100.00",
                "2026-10-24T09:00:00Z");
        private final CashFloatEntry youssefOld = collected(YOUSSEF, "50.00",
                "2026-10-21T10:00:00Z");
        private final CashFloatEntry michelYesterday = collected(MICHEL, "30.00",
                "2026-10-23T12:00:00Z");

        @BeforeEach
        void aDay() {
            when(floats.heldByRidersFor(COMPANY))
                    .thenReturn(List.of(youssefOld, michelYesterday, youssefToday));
            when(floats.forCarrierBetween(eq(COMPANY), eq(HolderKind.RIDER), eq(Kind.COLLECTED),
                    any(), any())).thenReturn(List.of(youssefToday));
            when(floats.forCarrierBetween(eq(COMPANY), eq(HolderKind.RIDER), eq(Kind.TRANSFERRED),
                    any(), any())).thenReturn(List.of(transfer(RANIA, "40.00",
                    "2026-10-24T08:00:00Z")));
            when(riderLedger.jobsForCarrierBetween(eq(COMPANY), any(), any()))
                    .thenReturn(List.of(job(YOUSSEF, youssefToday.getOrderId(), "2.25", COMPANY)));
            when(floats.lastHandoverByRider(COMPANY)).thenReturn(List.<Object[]>of(
                    new Object[] {RANIA, Instant.parse("2026-10-24T08:00:00Z")}));
            when(floats.ridersCarryingFor(COMPANY)).thenReturn(List.of(YOUSSEF, RANIA, MICHEL));
            when(floats.heldBy(COMPANY)).thenReturn(List.of(at(CashFloatEntry.custodyOf(COMPANY,
                    UUID.randomUUID(), new BigDecimal("40.00"), "USD", UUID.randomUUID()),
                    "2026-10-24T08:00:00Z")));
        }

        @Test
        @DisplayName("totals what the riders hold, what came in today, and what the company holds")
        void headlineFigures() {
            CarrierCashService.Overview page = service.overview(COMPANY, TODAY);

            CarrierCashService.Totals t = page.totals();
            assertThat(t.withRiders()).isEqualByComparingTo("180.00");
            assertThat(t.ridersHolding()).isEqualTo(2);
            assertThat(t.handedOver()).isEqualByComparingTo("40.00");
            assertThat(t.handovers()).isEqualTo(1);
            // What the company owes the platform right now: its own custody, not its riders' bags.
            assertThat(t.held()).isEqualByComparingTo("40.00");
            assertThat(t.heldOrders()).isEqualTo(1);
            assertThat(page.overdueAfterHours()).isEqualTo(48);
            assertThat(page.currency()).isEqualTo("USD");
        }

        /**
         * Counted per collection, not per rider: Youssef's 100.00 from this morning is not late just
         * because a 50.00 from three days ago is in the same bag.
         */
        @Test
        @DisplayName("counts only the collections past the limit as overdue")
        void overdueIsPerCollection() {
            CarrierCashService.Totals t = service.overview(COMPANY, TODAY).totals();

            assertThat(t.overdue()).isEqualByComparingTo("50.00");
            assertThat(t.overdueRiders()).isEqualTo(1);
        }

        @Test
        @DisplayName("lists the overdue first, then who is holding, then who is square")
        void workListOrder() {
            List<CarrierCashService.RiderRow> rows = service.overview(COMPANY, TODAY).riders();

            assertThat(rows).extracting(CarrierCashService.RiderRow::riderRef)
                    .containsExactly(YOUSSEF, MICHEL, RANIA);
            assertThat(rows).extracting(CarrierCashService.RiderRow::standing).containsExactly(
                    CarrierCashService.Standing.OVERDUE,
                    CarrierCashService.Standing.HOLDING,
                    CarrierCashService.Standing.SETTLED);
        }

        @Test
        @DisplayName("gives each rider the day's cash, the company's credit and the balance now")
        void oneRidersLine() {
            CarrierCashService.RiderRow youssef = service.overview(COMPANY, TODAY).riders().get(0);

            assertThat(youssef.name()).isEqualTo("Youssef Kanaan");
            assertThat(youssef.collected()).isEqualByComparingTo("100.00");
            assertThat(youssef.collections()).isEqualTo(1);
            assertThat(youssef.earned()).isEqualByComparingTo("2.25");
            assertThat(youssef.jobs()).isEqualTo(1);
            // The balance is not the day's: it is everything still in the bag.
            assertThat(youssef.holding()).isEqualByComparingTo("150.00");
            assertThat(youssef.orders()).isEqualTo(2);
            assertThat(youssef.oldest()).isEqualTo(Instant.parse("2026-10-21T10:00:00Z"));
            // 21 Oct 10:00 to 24 Oct 12:00.
            assertThat(youssef.overdueHours()).isEqualTo(74L);
        }

        @Test
        @DisplayName("a square rider shows nothing held and when they last handed over")
        void aSquareRider() {
            CarrierCashService.RiderRow rania = service.overview(COMPANY, TODAY).riders().get(2);

            assertThat(rania.holding()).isEqualByComparingTo("0.00");
            assertThat(rania.oldest()).isNull();
            assertThat(rania.overdueHours()).isNull();
            assertThat(rania.lastHandoverAt()).isEqualTo(Instant.parse("2026-10-24T08:00:00Z"));
        }

        @Test
        @DisplayName("a rider Keycloak has no name for gets none, never an id dressed up as one")
        void noNameIsNull() {
            CarrierCashService.RiderRow michel = service.overview(COMPANY, TODAY).riders().get(1);

            assertThat(michel.name()).isNull();
        }
    }

    @Test
    @DisplayName("reads the day in the configured calendar")
    void theDayIsLocal() {
        CarrierCashService beirut = new CarrierCashService(floats, riderLedger, accounts, 48, 24,
                "Asia/Beirut", "USD", Clock.fixed(NOW, ZoneOffset.UTC));
        lenient().when(floats.forCarrierBetween(anyString(), any(), any(), any(), any()))
                .thenReturn(List.of());

        beirut.overview(COMPANY, TODAY);

        // 24 October 2026 is the last day of Beirut's summer time: it starts at midnight UTC+3 and
        // ends at midnight UTC+2, so it is 25 hours long. Local midnights, not "start + 24h", are
        // what keep a late-evening collection on the day the hub counted it.
        verify(floats).forCarrierBetween(COMPANY, HolderKind.RIDER, Kind.COLLECTED,
                Instant.parse("2026-10-23T21:00:00Z"), Instant.parse("2026-10-24T22:00:00Z"));
    }

    @Test
    @DisplayName("draws the overdue line strictly past the limit")
    void theLineIsStrict() {
        // Exactly 48 hours is on time; one second more is not.
        assertThat(service.isOverdue(Instant.parse("2026-10-22T12:00:00Z"))).isFalse();
        assertThat(service.isOverdue(Instant.parse("2026-10-22T11:59:59Z"))).isTrue();
        assertThat(service.isOverdue(null)).isFalse();
    }

    /**
     * The Back Office's cash-on-hand list, which the owner's decision split in two: the platform's
     * own riders keep the day they were always held to, and cash in a company's custody gets the
     * carrier limit the company's own page states. With NOW at noon, the platform line is noon
     * yesterday and the carrier line noon two days ago.
     */
    @Nested
    @DisplayName("the Back Office's cash-on-hand list")
    class CashOnHand {

        /** Late by the platform's day, on time by the carrier's two. */
        private static final Instant THIRTY_HOURS = Instant.parse("2026-10-23T06:00:00Z");
        private static final Instant FIFTY_HOURS = Instant.parse("2026-10-22T10:00:00Z");
        private static final Instant TEN_HOURS = Instant.parse("2026-10-24T02:00:00Z");

        /** A row of {@code oldestHeldByRider}: a null company is the platform's own fleet. */
        private static Object[] oldest(String rider, String company, Instant at) {
            return new Object[] {rider, company, at};
        }

        private static CashFloatRepository.HolderBalance line(String ref, HolderKind kind,
                                                               Instant oldest) {
            return new Balance(ref, kind, new BigDecimal("10.00"), 1, oldest);
        }

        private static boolean lateOf(List<CarrierCashService.OnHand> list, String ref) {
            return list.stream()
                    .filter(h -> h.holderRef().equals(ref))
                    .findFirst()
                    .orElseThrow()
                    .overdue();
        }

        @Test
        @DisplayName("holds the platform's own riders to a day, as the Back Office always did")
        void platformFleetKeepsItsDay() {
            when(floats.oldestHeldByRider()).thenReturn(List.of(
                    oldest("rider-late", null, THIRTY_HOURS),
                    oldest("rider-fresh", null, TEN_HOURS)));
            when(floats.outstandingByHolder()).thenReturn(List.of(
                    line("rider-late", HolderKind.RIDER, THIRTY_HOURS),
                    line("rider-fresh", HolderKind.RIDER, TEN_HOURS)));

            List<CarrierCashService.OnHand> list = service.cashOnHand();

            assertThat(lateOf(list, "rider-late")).isTrue();
            assertThat(lateOf(list, "rider-fresh")).isFalse();
        }

        @Test
        @DisplayName("holds a company's cash to the carrier limit, with its rider or with the company")
        void carrierCustodyGetsTheCarrierLimit() {
            when(floats.oldestHeldByRider()).thenReturn(List.of(
                    oldest(YOUSSEF, COMPANY, THIRTY_HOURS),
                    oldest(MICHEL, COMPANY, FIFTY_HOURS)));
            when(floats.outstandingByHolder()).thenReturn(List.of(
                    line(YOUSSEF, HolderKind.RIDER, THIRTY_HOURS),
                    line(MICHEL, HolderKind.RIDER, FIFTY_HOURS),
                    line(COMPANY, HolderKind.PROVIDER, THIRTY_HOURS),
                    line("provider-late", HolderKind.PROVIDER, FIFTY_HOURS)));

            List<CarrierCashService.OnHand> list = service.cashOnHand();

            assertThat(lateOf(list, YOUSSEF)).isFalse();
            assertThat(lateOf(list, MICHEL)).isTrue();
            assertThat(lateOf(list, COMPANY)).isFalse();
            assertThat(lateOf(list, "provider-late")).isTrue();
        }

        @Test
        @DisplayName("a rider carrying both kinds is late when either part is, each by its own line")
        void bothKindsAreJudgedApart() {
            // Rania's platform cash is thirty hours old beside a fresh company bag: late. Michel's
            // oldest note is thirty hours old too, but it is the company's and his platform cash is
            // fresh: on time. Judging the oldest of both by one line would get one of them wrong.
            when(floats.oldestHeldByRider()).thenReturn(List.of(
                    oldest(RANIA, null, THIRTY_HOURS),
                    oldest(RANIA, COMPANY, TEN_HOURS),
                    oldest(MICHEL, null, TEN_HOURS),
                    oldest(MICHEL, COMPANY, THIRTY_HOURS)));
            when(floats.outstandingByHolder()).thenReturn(List.of(
                    line(RANIA, HolderKind.RIDER, THIRTY_HOURS),
                    line(MICHEL, HolderKind.RIDER, THIRTY_HOURS)));

            List<CarrierCashService.OnHand> list = service.cashOnHand();

            assertThat(lateOf(list, RANIA)).isTrue();
            assertThat(lateOf(list, MICHEL)).isFalse();
        }

        @Test
        @DisplayName("both lines are the configured ones, not constants")
        void bothLinesAreConfigured() {
            CarrierCashService configured = new CarrierCashService(floats, riderLedger, accounts,
                    72, 36, "UTC", "USD", Clock.fixed(NOW, ZoneOffset.UTC));
            when(floats.oldestHeldByRider()).thenReturn(List.of(
                    oldest("rider-platform", null, THIRTY_HOURS),
                    oldest(YOUSSEF, COMPANY, FIFTY_HOURS)));
            when(floats.outstandingByHolder()).thenReturn(List.of(
                    line("rider-platform", HolderKind.RIDER, THIRTY_HOURS),
                    line(YOUSSEF, HolderKind.RIDER, FIFTY_HOURS)));

            List<CarrierCashService.OnHand> list = configured.cashOnHand();

            assertThat(lateOf(list, "rider-platform")).isFalse();
            assertThat(lateOf(list, YOUSSEF)).isFalse();
        }

        /** A row of the cash-on-hand query, shaped as Spring Data projects it. */
        private record Balance(String getHolderRef, HolderKind getHolderKind, BigDecimal getAmount,
                               long getOrders, Instant getOldest)
                implements CashFloatRepository.HolderBalance {
        }
    }

    @Nested
    @DisplayName("one rider's page")
    class OneRider {

        @Test
        @DisplayName("is not there for a rider who never carried cash for this company")
        void aStrangerIsNotFound() {
            when(floats.existsByCarrierRefAndHolderRefAndHolderKind(COMPANY, "rival-rider",
                    HolderKind.RIDER)).thenReturn(false);

            assertThat(service.rider(COMPANY, "rival-rider")).isEmpty();
            // And nothing about them was even read.
            verify(floats, never()).heldForCarrier(anyString(), anyString());
        }

        /**
         * The overview lists a rider who did the company's card jobs today; their page must open
         * on "nothing held", not refuse them as a stranger.
         */
        @Test
        @DisplayName("is there, holding nothing, for a rider who only ever did card jobs for it")
        void aCardOnlyRiderIsFound() {
            when(floats.existsByCarrierRefAndHolderRefAndHolderKind(COMPANY, RANIA,
                    HolderKind.RIDER)).thenReturn(false);
            when(riderLedger.existsByRiderRefAndCarrierRefAndFleet(RANIA, COMPANY, Fleet.CARRIER))
                    .thenReturn(true);
            when(floats.heldForCarrier(RANIA, COMPANY)).thenReturn(List.of());
            when(floats.findByCarrierRefAndHolderRefAndEntryKindOrderByCreatedAtDesc(
                    eq(COMPANY), eq(RANIA), eq(Kind.TRANSFERRED), any(Pageable.class)))
                    .thenReturn(List.of());

            CarrierCashService.RiderSettlement page = service.rider(COMPANY, RANIA).orElseThrow();

            assertThat(page.holding()).isEqualByComparingTo("0.00");
            assertThat(page.standing()).isEqualTo(CarrierCashService.Standing.SETTLED);
            assertThat(page.held()).isEmpty();
        }

        @Test
        @DisplayName("is not there for a platform-fleet rider, however the ledger knows them")
        void aPlatformRiderIsNotFound() {
            when(floats.existsByCarrierRefAndHolderRefAndHolderKind(COMPANY, "platform-rider",
                    HolderKind.RIDER)).thenReturn(false);
            when(riderLedger.existsByRiderRefAndCarrierRefAndFleet("platform-rider", COMPANY,
                    Fleet.CARRIER)).thenReturn(false);

            assertThat(service.carriesFor(COMPANY, "platform-rider")).isFalse();
        }

        @Test
        @DisplayName("lists the cash in the bag with the company's credit where the ledger has one")
        void heldCollections() {
            CashFloatEntry today = collected(YOUSSEF, "145.00", "2026-10-24T09:00:00Z");
            CashFloatEntry old = collected(YOUSSEF, "120.00", "2026-10-21T09:00:00Z");
            when(floats.existsByCarrierRefAndHolderRefAndHolderKind(COMPANY, YOUSSEF,
                    HolderKind.RIDER)).thenReturn(true);
            when(floats.heldForCarrier(YOUSSEF, COMPANY)).thenReturn(List.of(old, today));
            // A job row from another company for the same order must not be credited to this one.
            when(riderLedger.findByRiderRefAndOrderIdIn(eq(YOUSSEF), anyCollection()))
                    .thenReturn(List.of(job(YOUSSEF, today.getOrderId(), "4.50", COMPANY),
                            job(YOUSSEF, old.getOrderId(), "3.00", "another-company")));
            CashFloatEntry handover = transfer(YOUSSEF, "232.00", "2026-10-23T18:00:00Z");
            when(floats.findByCarrierRefAndHolderRefAndEntryKindOrderByCreatedAtDesc(
                    eq(COMPANY), eq(YOUSSEF), eq(Kind.TRANSFERRED), any(Pageable.class)))
                    .thenReturn(List.of(handover));
            when(floats.countClearedBy(List.of(handover.getId())))
                    .thenReturn(List.<Object[]>of(new Object[] {handover.getId(), 4L}));

            CarrierCashService.RiderSettlement page =
                    service.rider(COMPANY, YOUSSEF).orElseThrow();

            assertThat(page.name()).isEqualTo("Youssef Kanaan");
            assertThat(page.holding()).isEqualByComparingTo("265.00");
            assertThat(page.standing()).isEqualTo(CarrierCashService.Standing.OVERDUE);
            assertThat(page.held()).hasSize(2);
            assertThat(page.held().get(0).overdue()).isTrue();
            // "No figure" is not "zero": the other company's row gave this one nothing to show.
            assertThat(page.held().get(0).earned()).isNull();
            assertThat(page.held().get(1).earned()).isEqualByComparingTo("4.50");
            assertThat(page.earnedOnHeld()).isEqualByComparingTo("4.50");

            assertThat(page.handovers()).hasSize(1);
            CarrierCashService.HandoverView h = page.handovers().get(0);
            assertThat(h.amount()).isEqualByComparingTo("232.00");
            assertThat(h.collections()).isEqualTo(4);
            assertThat(h.recordedByName()).isEqualTo("Kamal M.");
            assertThat(h.method()).isEqualTo(CashFloatEntry.Method.CASH);
            assertThat(page.firstSeenAt()).isEqualTo(Instant.parse("2026-10-21T09:00:00Z"));
        }
    }

    @Test
    @DisplayName("what the company owes is its own custody; its riders' cash is beside it, not in it")
    void owed() {
        when(floats.heldBy(COMPANY)).thenReturn(List.of(
                at(CashFloatEntry.custodyOf(COMPANY, UUID.randomUUID(), new BigDecimal("300.00"),
                        "USD", UUID.randomUUID()), "2026-10-20T10:00:00Z"),
                at(CashFloatEntry.custodyOf(COMPANY, UUID.randomUUID(), new BigDecimal("185.00"),
                        "USD", UUID.randomUUID()), "2026-10-24T10:00:00Z")));
        when(floats.heldByRidersFor(COMPANY)).thenReturn(List.of(
                collected(YOUSSEF, "50.00", "2026-10-24T09:00:00Z"),
                collected(YOUSSEF, "20.00", "2026-10-24T10:00:00Z"),
                collected(MICHEL, "30.00", "2026-10-24T11:00:00Z")));
        CashFloatEntry payment = at(CashFloatEntry.remitted(COMPANY, HolderKind.PROVIDER,
                new BigDecimal("900.00"), "USD", new CashFloatEntry.Recorded("op-1",
                        CashFloatEntry.Method.BANK_DEPOSIT, null, null)), "2026-10-19T10:00:00Z");
        when(floats.findByHolderRefAndHolderKindAndEntryKindOrderByCreatedAtDesc(
                eq(COMPANY), eq(HolderKind.PROVIDER), eq(Kind.REMITTED), any(Pageable.class)))
                .thenReturn(List.of(payment));
        when(floats.countClearedBy(List.of(payment.getId())))
                .thenReturn(List.<Object[]>of(new Object[] {payment.getId(), 12L}));

        CarrierCashService.Owed owed = service.owed(COMPANY);

        assertThat(owed.held()).isEqualByComparingTo("485.00");
        assertThat(owed.orders()).isEqualTo(2);
        assertThat(owed.overdue()).isTrue();
        assertThat(owed.withRiders()).isEqualByComparingTo("100.00");
        assertThat(owed.ridersHolding()).isEqualTo(2);
        assertThat(owed.payments()).singleElement().satisfies(p -> {
            assertThat(p.amount()).isEqualByComparingTo("900.00");
            assertThat(p.collections()).isEqualTo(12);
            assertThat(p.method()).isEqualTo(CashFloatEntry.Method.BANK_DEPOSIT);
        });
    }

    /**
     * The read rider payroll builds on: per rider, exactly what a hand-over would clear, so a pay
     * run can pass it straight back as the expected amount.
     */
    @Test
    @DisplayName("gives payroll each rider's held cash for this company, and nobody holding none")
    void heldByRiderForPayroll() {
        when(floats.heldByRidersFor(COMPANY)).thenReturn(List.of(
                collected(YOUSSEF, "50.00", "2026-10-21T09:00:00Z"),
                collected(MICHEL, "30.00", "2026-10-23T11:00:00Z"),
                collected(YOUSSEF, "20.05", "2026-10-24T10:00:00Z")));

        java.util.Map<String, BigDecimal> held = service.heldByRider(COMPANY);

        assertThat(held).containsOnlyKeys(YOUSSEF, MICHEL);
        assertThat(held.get(YOUSSEF)).isEqualByComparingTo("70.05");
        // Two decimals, as the hand-over's own sum is, so the figure round-trips as expectedAmount.
        assertThat(held.get(YOUSSEF).scale()).isEqualTo(2);
        assertThat(held.get(MICHEL)).isEqualByComparingTo("30.00");
        assertThat(held).doesNotContainKey(RANIA);
    }

    /** A projection row, as Spring Data would build one. */
    private record Balance(String holderRef, HolderKind holderKind, BigDecimal amount, long orders,
                           Instant oldest) implements CashFloatRepository.HolderBalance {
        @Override
        public String getHolderRef() {
            return holderRef;
        }

        @Override
        public HolderKind getHolderKind() {
            return holderKind;
        }

        @Override
        public BigDecimal getAmount() {
            return amount;
        }

        @Override
        public long getOrders() {
            return orders;
        }

        @Override
        public Instant getOldest() {
            return oldest;
        }
    }

    @Test
    @DisplayName("the Back Office sees each company's custody and its riders' cash, largest first")
    void backOfficeCarriers() {
        when(floats.outstandingByHolder()).thenReturn(List.of(
                new Balance(YOUSSEF, HolderKind.RIDER, new BigDecimal("150.00"), 2,
                        Instant.parse("2026-10-24T09:00:00Z")),
                new Balance(COMPANY, HolderKind.PROVIDER, new BigDecimal("485.00"), 3,
                        Instant.parse("2026-10-20T09:00:00Z"))));
        when(floats.withRidersByCarrier()).thenReturn(List.<Object[]>of(
                new Object[] {COMPANY, new BigDecimal("180.00"), 2L,
                        Instant.parse("2026-10-21T10:00:00Z")},
                new Object[] {"provider-quiet", new BigDecimal("12.00"), 1L,
                        Instant.parse("2026-10-24T10:00:00Z")}));
        when(floats.lastRemittedByCarrier()).thenReturn(List.<Object[]>of(
                new Object[] {COMPANY, Instant.parse("2026-10-19T10:00:00Z")}));

        List<CarrierCashService.CarrierHolding> carriers = service.carriers();

        assertThat(carriers).extracting(CarrierCashService.CarrierHolding::carrierRef)
                .containsExactly(COMPANY, "provider-quiet");
        CarrierCashService.CarrierHolding busy = carriers.get(0);
        assertThat(busy.held()).isEqualByComparingTo("485.00");
        assertThat(busy.orders()).isEqualTo(3);
        assertThat(busy.overdue()).isTrue();
        assertThat(busy.withRiders()).isEqualByComparingTo("180.00");
        assertThat(busy.ridersHolding()).isEqualTo(2);
        assertThat(busy.lastPaidAt()).isEqualTo(Instant.parse("2026-10-19T10:00:00Z"));
        // A company whose riders hold cash but which holds none itself is still listed.
        assertThat(carriers.get(1).held()).isEqualByComparingTo("0.00");
        assertThat(carriers.get(1).lastPaidAt()).isNull();
        // A rider of the platform's own fleet is not a company.
        assertThat(carriers).extracting(CarrierCashService.CarrierHolding::carrierRef)
                .doesNotContain(YOUSSEF);
    }

    @Test
    @DisplayName("history is capped and asks for the company's hand-overs only")
    void historyIsScoped() {
        when(floats.findByCarrierRefAndEntryKindOrderByCreatedAtDesc(eq(COMPANY),
                eq(Kind.TRANSFERRED), any(Pageable.class))).thenReturn(List.of());

        assertThat(service.history(COMPANY, 10_000)).isEmpty();

        org.mockito.ArgumentCaptor<Pageable> page = org.mockito.ArgumentCaptor.forClass(Pageable.class);
        verify(floats).findByCarrierRefAndEntryKindOrderByCreatedAtDesc(eq(COMPANY),
                eq(Kind.TRANSFERRED), page.capture());
        assertThat(page.getValue().getPageSize()).isEqualTo(CarrierCashService.MAX_HISTORY);
    }
}

package com.delivery.product.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import com.delivery.product.domain.MenuViewDay;
import com.delivery.product.domain.MenuViewDayRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;

/**
 * Counting menu opens without writing one down.
 *
 * <p>What is pinned here is the shape of what reaches the database, because that shape is the
 * privacy argument: a count per shop per day per part of the day per way in, and never a row per
 * reader, never a timestamp, and never an hour.
 */
class MenuViewRecorderTest {

    private Store shop;

    private final MenuViewDayRepository days = mock(MenuViewDayRepository.class);
    private final StoreRepository stores = mock(StoreRepository.class);
    private MutableClock clock;
    private MenuViewRecorder recorder;

    /** A clock a test winds on by hand, so nothing here waits on a real one. */
    private static final class MutableClock extends Clock {

        private Instant now;

        MutableClock(Instant now) {
            this.now = now;
        }

        void plus(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneId.of("UTC");
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    /**
     * A real shop, not a mock: {@code Store} assigns its own id and reads its own zone, and both
     * are what the flush depends on.
     */
    private static Store shopIn(String zone) {
        Store shop = new Store("merchant-sub", "Boulangerie Antoine", Store.Vertical.GROCERY);
        shop.updateProfile("Boulangerie Antoine", null, null, Store.Vertical.GROCERY, null, zone,
                null);
        return shop;
    }

    private MenuViewRecorder recorderAt(String iso, String zone) {
        clock = new MutableClock(Instant.parse(iso));
        shop = shopIn(zone);
        when(stores.findBySlug("antoine")).thenReturn(Optional.of(shop));
        PlatformTransactionManager transactions = mock(PlatformTransactionManager.class);
        when(transactions.getTransaction(any()))
                .thenAnswer(invocation -> (TransactionStatus) new SimpleTransactionStatus());
        return new MenuViewRecorder(days, stores, clock, transactions, null,
                Duration.ofMinutes(5), 90);
    }

    @BeforeEach
    void setUp() {
        recorder = recorderAt("2026-09-22T09:30:00Z", "UTC");
    }

    @Test
    @DisplayName("nothing reaches the database until a flush, however many people looked")
    void recording_writes_nothing() {
        for (int i = 0; i < 50; i++) {
            recorder.record("antoine", false);
        }

        verifyNoInteractions(days);
    }

    @Test
    @DisplayName("a flush writes one addition per bucket, not one row per reader")
    void a_flush_writes_one_row_per_bucket() {
        for (int i = 0; i < 50; i++) {
            recorder.record("antoine", false);
        }

        recorder.flush();

        // Fifty readers, one statement. There is no second write and no per-view row to find.
        verify(days, times(1)).add(eq(shop.getId()), eq(LocalDate.of(2026, 9, 22)), eq("MORNING"),
                eq("LINK"), eq(50));
    }

    @Test
    @DisplayName("a table card's address is counted apart from every other way in")
    void table_codes_are_their_own_bucket() {
        recorder.record("antoine", true);
        recorder.record("antoine", true);
        recorder.record("antoine", false);

        recorder.flush();

        verify(days).add(eq(shop.getId()), any(), eq("MORNING"), eq("TABLE"), eq(2));
        verify(days).add(eq(shop.getId()), any(), eq("MORNING"), eq("LINK"), eq(1));
    }

    @Test
    @DisplayName("the day and the part of it are the shop's own, not the server's")
    void the_day_is_the_shops_own() {
        // 23:30 UTC is already the next morning in Beirut (+03), and the shop's Wednesday.
        recorder = recorderAt("2026-09-22T23:30:00Z", "Asia/Beirut");
        recorder.record("antoine", false);

        recorder.flush();

        verify(days).add(eq(shop.getId()), eq(LocalDate.of(2026, 9, 23)), eq("NIGHT"), eq("LINK"), eq(1));
    }

    @Test
    @DisplayName("two hours of the same part of the same day land in one counter")
    void hours_are_given_up_at_the_flush() {
        recorder.record("antoine", false);
        clock.plus(Duration.ofHours(1));
        recorder.record("antoine", false);

        recorder.flush();

        // 09:30 and 10:30 are two hours in the buffer and one MORNING in the table. Nothing that
        // reaches the database can say which of them a reader was in.
        verify(days, times(1)).add(eq(shop.getId()), eq(LocalDate.of(2026, 9, 22)), eq("MORNING"),
                eq("LINK"), eq(2));
    }

    @Test
    @DisplayName("a flush waits for its window, and then goes")
    void flush_waits_for_the_window() {
        recorder.record("antoine", false);

        recorder.flushIfDue();
        verifyNoInteractions(days);

        clock.plus(Duration.ofMinutes(6));
        recorder.flushIfDue();

        verify(days).add(any(), any(), anyString(), anyString(), eq(1));
    }

    @Test
    @DisplayName("a shop that went away between the open and the flush is dropped, not invented")
    void a_vanished_shop_is_dropped() {
        when(stores.findBySlug("antoine")).thenReturn(Optional.empty());

        recorder.record("antoine", false);
        recorder.flush();

        verify(days, never()).add(any(), any(), anyString(), anyString(), anyInt());
    }

    @Test
    @DisplayName("a flush that cannot be written loses the count, never the page")
    void a_failed_flush_is_swallowed() {
        doThrow(new IllegalStateException("no database"))
                .when(days).add(any(), any(), anyString(), anyString(), anyInt());

        recorder.record("antoine", false);

        // The page's own thread is never in here, but a throw from a flush on the shutdown path
        // would take a clean stop down with it.
        recorder.flush();
    }

    @Test
    @DisplayName("counting cannot throw into the page's thread")
    void recording_never_throws() {
        when(stores.findBySlug(anyString())).thenThrow(new IllegalStateException("no database"));

        recorder.record("antoine", false);
        recorder.record("antoine", true);
        // The lookup above happens at flush time, so the real assertion is that neither call threw.
    }

    @Test
    @DisplayName("a retention window outside its bounds is refused at startup, never clamped")
    void retention_is_refused_rather_than_clamped() {
        PlatformTransactionManager transactions = mock(PlatformTransactionManager.class);
        assertThatThrownBy(() -> new MenuViewRecorder(days, stores, clock, transactions, null,
                Duration.ofMinutes(5), 4_000))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("retention-days");
        assertThatThrownBy(() -> new MenuViewRecorder(days, stores, clock, transactions, null,
                Duration.ofMinutes(5), 1))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("the parts of the day tile the day, and the night wraps midnight")
    void the_parts_tile_the_day() {
        assertThat(MenuViewDay.partOf(LocalTime.of(0, 1))).isEqualTo(MenuViewDay.Part.NIGHT);
        assertThat(MenuViewDay.partOf(LocalTime.of(4, 59))).isEqualTo(MenuViewDay.Part.NIGHT);
        assertThat(MenuViewDay.partOf(LocalTime.of(5, 0))).isEqualTo(MenuViewDay.Part.MORNING);
        assertThat(MenuViewDay.partOf(LocalTime.of(10, 59))).isEqualTo(MenuViewDay.Part.MORNING);
        assertThat(MenuViewDay.partOf(LocalTime.of(11, 0))).isEqualTo(MenuViewDay.Part.MIDDAY);
        assertThat(MenuViewDay.partOf(LocalTime.of(16, 59))).isEqualTo(MenuViewDay.Part.MIDDAY);
        assertThat(MenuViewDay.partOf(LocalTime.of(17, 0))).isEqualTo(MenuViewDay.Part.EVENING);
        assertThat(MenuViewDay.partOf(LocalTime.of(22, 59))).isEqualTo(MenuViewDay.Part.EVENING);
        assertThat(MenuViewDay.partOf(LocalTime.of(23, 0))).isEqualTo(MenuViewDay.Part.NIGHT);

        // Four, and declared in the order a day runs, so a chart drawn from values() reads left to
        // right. A fifth would be a finer grid than this table is allowed to publish.
        assertThat(MenuViewDay.Part.values()).hasSize(4);
    }
}

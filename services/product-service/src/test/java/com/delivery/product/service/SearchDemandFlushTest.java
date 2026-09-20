package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.SimpleTransactionStatus;

import com.delivery.product.domain.SearchDemandLog;
import com.delivery.product.domain.SearchDemandLogRepository;
import com.delivery.product.domain.SearchDemandSeenRepository;
import com.delivery.product.service.SearchDemandRecorder.Recording;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The shape of a flush — the part of the recorder that exists only for privacy.
 *
 * <p>The demand log is insert-only with a single writer, so the heap keeps the order rows were
 * written in and {@code ORDER BY ctid} reads it back. A sequence of searches from one area is one
 * shopper's basket, which says far more about a household than any single word does — so rows are
 * buffered and each flush is inserted shuffled. What has to hold:
 *
 * <ul>
 *   <li>a flush is not written in the order the searches happened in;</li>
 *   <li>a lone row is never a flush on its own, because a flush of one is the sequence;</li>
 *   <li>a quiet area's rows are written anyway once they have waited the hour their own timestamps
 *       already name — waiting longer would only lose more of them to a restart.</li>
 * </ul>
 *
 * <p>That the shuffle survives the trip to PostgreSQL, rather than being undone by the way rows are
 * inserted, is proved against a real database in {@code SearchDemandDatabaseTest}.
 */
@DisplayName("how the demand log is flushed")
class SearchDemandFlushTest {

    private static final Instant NOON = Instant.parse("2026-09-16T10:30:00Z");

    /**
     * Fifty rows recorded in a known order, and the order they are handed to the repository in is
     * not it. A permutation of fifty coming back identical has a one in 50! chance, which is not a
     * flake anybody will ever see.
     */
    @Test
    @DisplayName("a flush is written in an order that is not the order the searches happened in")
    void a_flush_is_shuffled() {
        Recorded recorded = new Recorded();
        SearchDemandRecorder recorder = recorder(recorded, new MovingClock(NOON), 50,
                Duration.ofMinutes(10));

        List<String> asSearched = new ArrayList<>();
        for (int i = 0; i < 50; i++) {
            String term = "term-" + (i < 10 ? "0" + i : i);
            asSearched.add(term);
            recorder.record(new Recording("account-" + i, term, null, 0, null, List.of(), null));
        }

        assertThat(recorded.terms()).containsExactlyInAnyOrderElementsOf(asSearched);
        assertThat(recorded.terms()).isNotEqualTo(asSearched);
        assertThat(recorder.counts().written()).isEqualTo(50);
        assertThat(recorder.counts().waiting()).isZero();
    }

    @Test
    @DisplayName("a quiet area's lone row waits for company rather than being written on its own")
    void a_lone_row_is_not_a_flush() {
        Recorded recorded = new Recorded();
        MovingClock clock = new MovingClock(NOON);
        SearchDemandRecorder recorder = recorder(recorded, clock, 50, Duration.ofMinutes(10));

        recorder.record(new Recording("a", "insulin", null, 0, null, List.of(), null));
        clock.move(Duration.ofMinutes(11));
        recorder.flushIfDue();

        // It has waited its ten minutes; one row written alone would be the sequence, not a flush.
        assertThat(recorded.terms()).isEmpty();
        assertThat(recorder.counts().waiting()).isEqualTo(1);
        assertThat(recorder.counts().written()).isZero();
    }

    @Test
    @DisplayName("rows that never find company are written after the hour their timestamps already name")
    void the_hour_is_the_longest_a_row_waits() {
        Recorded recorded = new Recorded();
        MovingClock clock = new MovingClock(NOON);
        SearchDemandRecorder recorder = recorder(recorded, clock, 50, Duration.ofMinutes(10));

        recorder.record(new Recording("a", "insulin", null, 0, null, List.of(), null));
        clock.move(Duration.ofMinutes(61));
        recorder.flushIfDue();

        assertThat(recorded.terms()).containsExactly("insulin");
        assertThat(recorder.counts().waiting()).isZero();
    }

    @Test
    @DisplayName("the floor's worth of rows goes as soon as it has waited")
    void enough_rows_go_on_the_timer() {
        Recorded recorded = new Recorded();
        MovingClock clock = new MovingClock(NOON);
        SearchDemandRecorder recorder = recorder(recorded, clock, 50, Duration.ofMinutes(10));

        for (int i = 0; i < SearchDemandRecorder.MIN_FLUSH_ROWS; i++) {
            recorder.record(new Recording("account-" + i, "rice", null, 0, null, List.of(), null));
        }
        clock.move(Duration.ofMinutes(11));
        recorder.flushIfDue();

        assertThat(recorded.terms()).hasSize(SearchDemandRecorder.MIN_FLUSH_ROWS);
    }

    @Test
    @DisplayName("a buffer that has not waited at all stays where it is")
    void nothing_goes_before_its_time() {
        Recorded recorded = new Recorded();
        MovingClock clock = new MovingClock(NOON);
        SearchDemandRecorder recorder = recorder(recorded, clock, 50, Duration.ofMinutes(10));

        for (int i = 0; i < 20; i++) {
            recorder.record(new Recording("account-" + i, "rice", null, 0, null, List.of(), null));
        }
        clock.move(Duration.ofMinutes(9));
        recorder.flushIfDue();

        assertThat(recorded.terms()).isEmpty();
        assertThat(recorder.counts().waiting()).isEqualTo(20);
    }

    // ------------------------------------------------------------------------------------ helpers

    /**
     * A recorder writing into {@code recorded}, inline, with no area register to ask.
     *
     * <p>No area means no "somebody asked" row either, which is what this test wants: the order rows
     * are written in is the whole subject here, and {@code SearchDemandDatabaseTest} is where the
     * floor's own table is exercised.
     */
    private static SearchDemandRecorder recorder(Recorded recorded, Clock clock, int flushRows,
                                                 Duration flushAfter) {
        return new SearchDemandRecorder(recorded.repository(),
                mock(SearchDemandSeenRepository.class), new SeenKeys("flush-test-secret-not-a-real-one"),
                new DemandWeeks(ZoneOffset.UTC), mock(CoarseAreas.class), clock,
                Recorded.noTransaction(), Runnable::run, Duration.ZERO, flushRows, flushAfter);
    }

    /** The terms a flush handed to the repository, in the order it handed them over. */
    private static final class Recorded {

        private final List<String> terms = new ArrayList<>();

        private SearchDemandLogRepository repository() {
            SearchDemandLogRepository repository = mock(SearchDemandLogRepository.class);
            when(repository.saveAll(org.mockito.ArgumentMatchers.<Iterable<SearchDemandLog>>any()))
                    .thenAnswer(call -> {
                        Iterable<SearchDemandLog> rows = call.getArgument(0);
                        rows.forEach(row -> terms.add(row.getTerm()));
                        return List.of();
                    });
            return repository;
        }

        private List<String> terms() {
            return terms;
        }

        /** Opens and commits nothing: what is being asserted is the order, not the transaction. */
        private static PlatformTransactionManager noTransaction() {
            return new PlatformTransactionManager() {
                @Override
                public TransactionStatus getTransaction(TransactionDefinition definition) {
                    return new SimpleTransactionStatus();
                }

                @Override
                public void commit(TransactionStatus status) {
                }

                @Override
                public void rollback(TransactionStatus status) {
                }
            };
        }
    }

    /** A clock a test moves by hand, so an hour of waiting costs no time at all. */
    private static final class MovingClock extends Clock {

        private Instant now;

        private MovingClock(Instant now) {
            this.now = now;
        }

        private void move(Duration by) {
            now = now.plus(by);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
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
}

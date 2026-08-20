package com.delivery.platform.observability;

import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The id that makes "why didn't this SMS arrive" answerable across fifteen services.
 *
 * <p>Two of these tests are about tracing working at all. The rest are about the header being
 * client-supplied: it flows into the log line and, via the outbox, into a {@code varchar(64)} column
 * inside the caller's business transaction — so an unbounded or newline-bearing value is not merely
 * untidy, it either forges the audit trail or rolls the order back.
 */
class CorrelationIdFilterTest {

    private final CorrelationIdFilter filter = new CorrelationIdFilter();

    @AfterEach
    void clearMdc() {
        MDC.clear();
    }

    /** Captures what the MDC held at the moment the request was actually being handled. */
    private static class MdcCapturingChain extends MockFilterChain {
        private String seen;

        @Override
        public void doFilter(jakarta.servlet.ServletRequest request,
                             jakarta.servlet.ServletResponse response) {
            seen = MDC.get(CorrelationIdFilter.MDC_KEY);
        }
    }

    private MdcCapturingChain runWith(String header) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (header != null) {
            request.addHeader(CorrelationIdFilter.HEADER, header);
        }
        MdcCapturingChain chain = new MdcCapturingChain();
        filter.doFilter(request, new MockHttpServletResponse(), chain);
        return chain;
    }

    private String responseHeaderFor(String header) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (header != null) {
            request.addHeader(CorrelationIdFilter.HEADER, header);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MdcCapturingChain());
        return response.getHeader(CorrelationIdFilter.HEADER);
    }

    @Nested
    @DisplayName("tracing")
    class Tracing {

        /** The Gateway mints the id; downstream services must keep it, or the trace breaks in two. */
        @Test
        void an_inbound_id_is_carried_through_the_request() throws Exception {
            assertThat(runWith("abc-123").seen).isEqualTo("abc-123");
        }

        /** A scheduled job or a curl gets its own, so nothing is ever untraced. */
        @Test
        void a_request_without_one_is_given_a_fresh_id() throws Exception {
            String generated = runWith(null).seen;

            assertThat(generated).isNotBlank();
            assertThat(UUID.fromString(generated)).isNotNull();
        }

        @Test
        void a_blank_header_counts_as_absent() throws Exception {
            assertThat(runWith("   ").seen).isNotBlank();
        }

        /** Echoed back so a user can quote it in a bug report. */
        @Test
        void the_id_is_returned_on_the_response() throws Exception {
            assertThat(responseHeaderFor("abc-123")).isEqualTo("abc-123");
            assertThat(responseHeaderFor(null)).isNotBlank();
        }

        /**
         * Servlet threads are pooled. An id left in the MDC would label the next, unrelated request
         * with the previous caller's trace — quietly, and in a way that only shows up when someone
         * is debugging an incident with it.
         */
        @Test
        void the_mdc_is_cleared_once_the_request_finishes() throws Exception {
            runWith("abc-123");

            assertThat(MDC.get(CorrelationIdFilter.MDC_KEY)).isNull();
        }

        @Test
        void the_mdc_is_cleared_even_when_the_request_blows_up() {
            MockFilterChain exploding = new MockFilterChain() {
                @Override
                public void doFilter(jakarta.servlet.ServletRequest request,
                                     jakarta.servlet.ServletResponse response) {
                    throw new IllegalStateException("handler failed");
                }
            };

            try {
                filter.doFilter(new MockHttpServletRequest(), new MockHttpServletResponse(), exploding);
            } catch (Exception expected) {
                // the point is what happens to the MDC, not the exception
            }

            assertThat(MDC.get(CorrelationIdFilter.MDC_KEY)).isNull();
        }

        /** It has to be in the MDC before the security chain can log a rejection. */
        @Test
        void it_runs_before_every_other_filter() {
            assertThat(filter.getOrder()).isEqualTo(Ordered.HIGHEST_PRECEDENCE);
        }
    }

    @Nested
    @DisplayName("a hostile header")
    class Hostile {

        /**
         * The id reaches {@code outbox_event.correlation_id}, which is {@code varchar(64)}, in the
         * same transaction as the business write. Left unbounded, a long header turns checkout into
         * a 500 and loses the order with it.
         */
        @Test
        void an_over_long_id_is_truncated_to_what_the_outbox_column_holds() throws Exception {
            String seen = runWith("x".repeat(500)).seen;

            assertThat(seen).hasSize(CorrelationIds.MAX_LENGTH);
        }

        @Test
        void an_id_exactly_at_the_limit_is_kept_whole() throws Exception {
            String exact = "y".repeat(CorrelationIds.MAX_LENGTH);

            assertThat(runWith(exact).seen).isEqualTo(exact);
        }

        /**
         * The id is written onto every log line for the request. A newline in it lets a caller
         * append entries of their own to the record used to reconstruct an incident.
         */
        @Test
        void newlines_cannot_be_used_to_forge_log_entries() throws Exception {
            String seen = runWith("real-id\n2026-08-17 ERROR fabricated entry").seen;

            assertThat(seen).doesNotContain("\n").doesNotContain("\r");
        }

        @Test
        void carriage_returns_and_tabs_are_stripped_too() throws Exception {
            String seen = runWith("a\r\nb\tc").seen;

            assertThat(seen).isEqualTo("abc");
        }

        /** An id made entirely of rejected characters still has to leave the request traceable. */
        @Test
        void an_id_with_nothing_usable_in_it_is_replaced_rather_than_emptied() throws Exception {
            String seen = runWith("\n\r\t <>").seen;

            assertThat(seen).isNotBlank();
            assertThat(UUID.fromString(seen)).isNotNull();
        }

        /** Ordinary trace ids — UUIDs, W3C traceparent-ish values — must survive untouched. */
        @Test
        void legitimate_id_formats_are_left_alone() throws Exception {
            String uuid = UUID.randomUUID().toString();
            assertThat(runWith(uuid).seen).isEqualTo(uuid);

            assertThat(runWith("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01").seen)
                    .isEqualTo("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
            assertThat(runWith("order_svc:12345.67").seen).isEqualTo("order_svc:12345.67");
        }

        /** What goes back on the response is the sanitised value, never the raw header. */
        @Test
        void the_response_echoes_the_sanitised_id() throws Exception {
            assertThat(responseHeaderFor("bad\nvalue")).isEqualTo("badvalue");
        }
    }
}

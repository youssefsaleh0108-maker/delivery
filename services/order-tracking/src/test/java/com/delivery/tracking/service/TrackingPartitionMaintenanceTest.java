package com.delivery.tracking.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

/**
 * What survives a trail's retention window.
 *
 * <p>A day of pings older than the window is summarised and its partition dropped. The summary
 * used to keep each order's first and last point — the shop or the claim, and the customer's door
 * — for good, after the trail itself was gone. These cases pin what the job now sends the
 * database: a summary with no coordinate in it, the partition dropped, and nothing already rolled
 * up touched.
 */
@DisplayName("what is kept once a trail is past its retention")
class TrackingPartitionMaintenanceTest {

    private static final DateTimeFormatter SUFFIX = DateTimeFormatter.ofPattern("yyyyMMdd");

    private final LocalDate expired = LocalDate.now().minusDays(40);
    private final LocalDate kept = LocalDate.now().minusDays(3);
    private JdbcTemplate jdbc;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        jdbc = mock(JdbcTemplate.class);
        when(jdbc.query(anyString(), any(RowMapper.class))).thenReturn(List.of(
                "tracking_events_" + expired.format(SUFFIX),
                "tracking_events_" + kept.format(SUFFIX)));
        new TrackingPartitionMaintenance(jdbc, 30, 7, 400).run();
    }

    private String rollUp() {
        ArgumentCaptor<String> sql = ArgumentCaptor.forClass(String.class);
        verify(jdbc).update(sql.capture());
        return sql.getValue();
    }

    @Test
    @DisplayName("the day past the window is summarised with no coordinate in it")
    void the_summary_keeps_no_position() {
        String sql = rollUp();

        assertThat(sql).contains("INSERT INTO tracking_event_rollup")
                .contains("FROM tracking_events_" + expired.format(SUFFIX));
        // The four coordinate columns are written as NULL, never from the points — and never as a
        // NaN, which a JSON writer would render as a number that is not one.
        assertThat(sql.split("NULL::double precision", -1)).hasSize(5);
        assertThat(sql).doesNotContainIgnoringCase("nan");
        assertThat(sql).doesNotContain("array_agg(lat").doesNotContain("array_agg(lng");
        // What a late dispute can still be told: how many points, when, how far apart.
        assertThat(sql).contains("count(*)").contains("min(recorded_at)")
                .contains("max(recorded_at)").contains("ST_Distance");
    }

    @Test
    @DisplayName("and dropped, while the days inside the window stay")
    void the_expired_day_is_dropped_and_the_rest_kept() {
        verify(jdbc).execute("DROP TABLE IF EXISTS tracking_events_" + expired.format(SUFFIX));
        verify(jdbc, never()).execute("DROP TABLE IF EXISTS tracking_events_"
                + kept.format(SUFFIX));
    }

    /** Rows rolled up before this change keep what they have: nothing rewrites or deletes them. */
    @Test
    @DisplayName("summaries already written are neither rewritten nor deleted")
    void earlier_summaries_are_left_alone() {
        ArgumentCaptor<String> executed = ArgumentCaptor.forClass(String.class);
        verify(jdbc, org.mockito.Mockito.atLeastOnce()).execute(executed.capture());

        assertThat(rollUp()).contains("ON CONFLICT (order_id, day) DO NOTHING");
        assertThat(executed.getAllValues())
                .noneMatch(sql -> sql.contains("tracking_event_rollup"));
    }
}

package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;

/**
 * RECON-08 and PT-4: the platform's one calendar, and the configuration it is read from.
 *
 * <p>{@link ReportCalendarTest} and {@link MoneyDayZoneTest} read the shipped {@code
 * application.yml} as a plain map. This reads it the way the service itself does — through Spring
 * Boot's own loader, which is what resolves the YAML alias the three per-reader keys are written as
 * — and then checks what the calendar does with them.
 */
@DisplayName("RECON-08: one calendar, resolved once")
class PlatformCalendarTest {

    private static final Clock AT_MIDNIGHT_IN_BEIRUT =
            Clock.fixed(Instant.parse("2026-09-19T21:16:14Z"), ZoneOffset.UTC);

    private static PropertySource<?> shipped() throws Exception {
        List<PropertySource<?>> sources = new YamlPropertySourceLoader()
                .load("application.yml", new ClassPathResource("application.yml"));
        assertThat(sources).isNotEmpty();
        return sources.get(0);
    }

    private static String property(String key) throws Exception {
        Object value = shipped().getProperty(key);
        return value == null ? null : value.toString();
    }

    @Test
    @DisplayName("the service's own loader reads one zone for every reader")
    void theLoaderResolvesOneZone() throws Exception {
        // The alias is the point: one value in the file, so the keys cannot drift apart.
        assertThat(property("delivery.calendar.zone")).isEqualTo("Asia/Beirut");
        assertThat(property("delivery.accounting.statements.zone")).isEqualTo("Asia/Beirut");
        assertThat(property("delivery.rider-earnings.zone")).isEqualTo("Asia/Beirut");
        assertThat(property("delivery.accounting.payroll.zone")).isEqualTo("Asia/Beirut");
    }

    @Test
    @DisplayName("a reader's own key is honoured when it agrees, and unset is no opinion")
    void agreeingKeysAreAccepted() {
        assertThatCode(() -> new PlatformCalendar("Asia/Beirut", "Asia/Beirut", "Asia/Beirut",
                "Asia/Beirut")).doesNotThrowAnyException();
        assertThatCode(() -> new PlatformCalendar("Asia/Beirut", "", null, "  "))
                .doesNotThrowAnyException();
    }

    @Test
    @DisplayName("a configuration that splits the calendar refuses to start")
    void aSplitCalendarRefusesToStart() {
        assertThatThrownBy(() -> new PlatformCalendar("Asia/Beirut", "UTC", "Asia/Beirut",
                "Asia/Beirut"))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("delivery.accounting.statements.zone")
                .hasMessageContaining("one calendar");
        assertThatThrownBy(() -> new PlatformCalendar("Asia/Beirut", null, "UTC", null))
                .hasMessageContaining("delivery.rider-earnings.zone");
        assertThatThrownBy(() -> new PlatformCalendar("Nowhere/Nothing", null, null, null))
                .hasMessageContaining("not a timezone");
    }

    @Test
    @DisplayName("00:16 on 9 September in Beirut is the 9th, three hours before UTC agrees")
    void theDayIsTheLocalDay() {
        ZoneId zone = new PlatformCalendar("Asia/Beirut", null, null, null).zone();

        assertThat(zone).isEqualTo(ZoneId.of("Asia/Beirut"));
        // The dev order of the deep test: delivered 2026-09-08T21:16:14Z, which is the 9th there,
        // and the day a statement, a rider's week and a pay period all now bucket it on.
        assertThat(LocalDate.ofInstant(Instant.parse("2026-09-08T21:16:14Z"), zone))
                .isEqualTo(LocalDate.parse("2026-09-09"));
        // And "today" on the carrier cash page at 00:16 Beirut is that day, not yesterday (PT-4).
        assertThat(LocalDate.now(AT_MIDNIGHT_IN_BEIRUT.withZone(zone)))
                .isEqualTo(LocalDate.parse("2026-09-20"));
        assertThat(LocalDate.parse("2026-09-09").atStartOfDay(zone).toInstant())
                .isEqualTo(Instant.parse("2026-09-08T21:00:00Z"));
    }
}

package com.delivery.accounting.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Properties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.YamlPropertiesFactoryBean;
import org.springframework.core.io.ClassPathResource;

/**
 * RECON-08: the money reports do not share one calendar.
 *
 * <p>The shipped configuration puts statements and the carrier's cash page
 * ({@code delivery.accounting.statements.zone}) and rider earnings ({@code
 * delivery.rider-earnings.zone}) on UTC, while payroll ({@code delivery.accounting.payroll.zone}) and
 * Order Manager's dashboards run on Asia/Beirut, and every client sends a Beirut calendar date. So
 * an order delivered between 00:00 and 03:00 in Beirut lands on the previous day's statement, and a
 * month's statement ends three hours into the next month.
 *
 * <p>On dev, order 26fae838 was delivered 2026-09-08T21:16:14Z — 00:16 on 9 September in Beirut. The
 * shop's statement "for 2026-09-09" is empty and the one "for 2026-09-08" lists it; three of the 36
 * orders delivered on dev so far fall on a different day in Beirut than in UTC.
 *
 * <p>The first test fails until the zones agree; the second states the effect on that order.
 */
@DisplayName("RECON-08: statements, cash pages, earnings and payroll share one calendar")
class ReportCalendarTest {

    private static Properties shipped() {
        YamlPropertiesFactoryBean yaml = new YamlPropertiesFactoryBean();
        yaml.setResources(new ClassPathResource("application.yml"));
        return yaml.getObject();
    }

    @Test
    @DisplayName("every report is configured in the payroll's zone, Asia/Beirut")
    void oneZone() {
        Properties config = shipped();
        String payroll = config.getProperty("delivery.accounting.payroll.zone");

        assertThat(payroll).isEqualTo("Asia/Beirut");
        assertThat(config.getProperty("delivery.accounting.statements.zone"))
                .as("statements and the carrier cash page").isEqualTo(payroll);
        assertThat(config.getProperty("delivery.rider-earnings.zone"))
                .as("rider earnings").isEqualTo(payroll);
    }

    @Test
    @DisplayName("an order delivered at 00:16 in Beirut belongs to that Beirut day's statement")
    void theDevOrderAtMidnight() {
        Instant delivered = Instant.parse("2026-09-08T21:16:14Z");
        LocalDate beirutDay = LocalDate.parse("2026-09-09");
        ZoneId statementZone = ZoneId.of(shipped().getProperty("delivery.accounting.statements.zone"));

        StatementRange asked = StatementRange.of(beirutDay, beirutDay, statementZone);

        assertThat(asked.contains(delivered))
                .as("the shop's statement for %s (zone %s) contains the order delivered then",
                        beirutDay, statementZone)
                .isTrue();
    }
}

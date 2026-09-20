package com.delivery.accounting.service;

import java.util.Properties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.YamlPropertiesFactoryBean;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * PT-4 (portal deep test, 2026-09-19): which calendar a "day" is on the money pages.
 *
 * <p>{@code delivery.accounting.statements.zone} is the zone a statement's from/to range is read
 * in, and {@link CarrierCashService} uses it for the carrier's cash page ("today", and the day in
 * its CSV's file name). It ships as UTC. Everything else a merchant or a carrier reads a day from is
 * in Asia/Beirut: this service's own pay periods ({@code delivery.accounting.payroll.zone}), and
 * Order Manager's dashboards and daily series.
 *
 * <p>Measured on dev at 00:01 Beirut on 2026-09-20: the merchant and carrier summaries, the daily
 * series and delivered-today had all moved to 2026-09-20, while GET /api/accounting/carrier/cash
 * still answered {@code "day": "2026-09-19"}. So for three hours a night (two in winter) the cash
 * page's "today" is yesterday, and a statement for a month starts and ends at 03:00 Beirut: orders
 * placed just after midnight on the 1st land in the previous month's statement.
 *
 * <p>Fails until the statement zone is the business zone.
 */
@DisplayName("PT-4: the money pages' day")
class MoneyDayZoneTest {

    private static Properties config() {
        YamlPropertiesFactoryBean yaml = new YamlPropertiesFactoryBean();
        yaml.setResources(new ClassPathResource("application.yml"));
        return yaml.getObject();
    }

    @Test
    void statements_and_the_cash_page_count_days_where_pay_periods_do() {
        Properties p = config();

        assertThat(p.getProperty("delivery.accounting.payroll.zone")).isEqualTo("Asia/Beirut");
        assertThat(p.getProperty("delivery.accounting.statements.zone"))
                .as("statement ranges and the carrier cash page's day")
                .isEqualTo(p.getProperty("delivery.accounting.payroll.zone"));
    }
}

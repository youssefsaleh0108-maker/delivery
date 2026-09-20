package com.delivery.product.api;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The platform has ONE lira rate, and this service is the half that displays it.
 *
 * <p>The bug this pins: `delivery.market.lbp-per-usd` was spelled the same here and in
 * transfer-service, and both defaulted to 90000, so it read as one rate — but only
 * transfer-service bound the key to `MARKET_LBP_PER_USD`. This service had no `delivery.market`
 * block at all and fell through to the hard-coded default on {@link MarketController}'s
 * {@code @Value}. An operator moving the rate therefore moved what checkout locks and collects
 * and left every displayed "$3.50 / 315,000 LBP" at the old rate: a customer browsed one lira
 * figure and was asked for another at the door, with neither service inconsistent with itself.
 *
 * <p>So the assertion is not "the default is 90000" — that was always true and told us nothing.
 * It is that the configured environment variable REACHES the property.
 */
class MarketRateConfigurationTest {

    private static final String KEY = "delivery.market.lbp-per-usd";

    /** application.yml as the service actually ships it, resolved against a given environment. */
    private static String resolve(Map<String, Object> environmentVariables) throws Exception {
        StandardEnvironment environment = new StandardEnvironment();
        // Ahead of the file, as a real process environment is.
        environment.getPropertySources()
                .addFirst(new MapPropertySource("test-process-environment", environmentVariables));
        List<PropertySource<?>> loaded = new YamlPropertySourceLoader()
                .load("application.yml", new ClassPathResource("application.yml"));
        assertThat(loaded).isNotEmpty();
        loaded.forEach(environment.getPropertySources()::addLast);
        return environment.getProperty(KEY);
    }

    @Test
    @DisplayName("the displayed rate is read from MARKET_LBP_PER_USD, the one transfer-service locks from")
    void rateFollowsTheConfiguredEnvironmentVariable() throws Exception {
        assertThat(resolve(Map.of("MARKET_LBP_PER_USD", "123000"))).isEqualTo("123000");
    }

    @Test
    @DisplayName("with nothing configured it still falls back to the documented 90000")
    void rateFallsBackWhenNothingIsConfigured() throws Exception {
        assertThat(resolve(Map.of())).isEqualTo("90000");
    }

    @Test
    @DisplayName("the endpoint serves whatever the property resolved to, zero included")
    void endpointServesTheConfiguredRate() {
        assertThat(new MarketController(new BigDecimal("123000")).config())
                .containsEntry("lbpPerUsd", new BigDecimal("123000"));
        assertThat(new MarketController(BigDecimal.ZERO).config())
                .containsEntry("lbpPerUsd", BigDecimal.ZERO);
    }
}

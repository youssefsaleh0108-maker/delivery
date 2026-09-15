package com.delivery.tracking.service;

import java.lang.reflect.Constructor;
import java.lang.reflect.Parameter;
import java.time.ZoneId;
import java.util.Arrays;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MutablePropertySources;
import org.springframework.core.env.PropertySource;
import org.springframework.core.env.PropertySourcesPropertyResolver;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The day zone is Beirut, in the shipped configuration and in the code's own fallback.
 *
 * <p>Every attendance verdict hangs off this one setting: which date a session belongs to, the
 * instant "08:00" means on a given day, and so whether a rider was late. It was UTC until the
 * attendance work, which put every Lebanese day boundary two or three hours out; a later edit that
 * put it back — or a profile that dropped the key and fell through to a UTC default — would not
 * fail a single other test, because those construct the service with a zone of their own.
 */
class DayZoneConfigurationTest {

    private static final String KEY = "delivery.tracking.duty-session.day-zone";

    @Test
    void the_shipped_configuration_splits_days_in_beirut() throws Exception {
        List<PropertySource<?>> yaml = new YamlPropertySourceLoader()
                .load("application", new ClassPathResource("application.yml"));
        MutablePropertySources sources = new MutablePropertySources();
        yaml.forEach(sources::addLast);

        // Resolved against the file alone, so the TRACKING_DAY_ZONE override is absent and the
        // default written in the file is what comes back.
        String zone = new PropertySourcesPropertyResolver(sources).getProperty(KEY);

        assertThat(zone).isEqualTo("Asia/Beirut");
        // A region id, never a fixed offset: "+03:00" would be an hour wrong all winter.
        assertThat(ZoneId.of(zone).getRules().isFixedOffset()).isFalse();
    }

    @Test
    void the_code_falls_back_to_beirut_when_the_key_is_missing() {
        Constructor<?> constructor = DutySessionService.class.getConstructors()[0];

        String placeholder = Arrays.stream(constructor.getParameters())
                .map((Parameter p) -> p.getAnnotation(Value.class))
                .filter(v -> v != null && v.value().contains(KEY))
                .map(Value::value)
                .findFirst()
                .orElseThrow();

        assertThat(placeholder).isEqualTo("${" + KEY + ":Asia/Beirut}");
    }
}

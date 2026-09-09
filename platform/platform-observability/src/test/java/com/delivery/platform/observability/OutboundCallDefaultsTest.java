package com.delivery.platform.observability;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.AutoConfigurations;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.web.client.RestClientCustomizer;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestClient;

/**
 * Every cross-service call gets a deadline, whether or not its author remembered.
 *
 * <p>Spring's default request factory has no connect or read timeout at all. Six clients across
 * three services were built on the plain injected builder, including the account directory that
 * the accounting ledger consumer calls on its single deliberately-serial thread — where one
 * unanswered call stops every settlement on the platform for as long as the far end stays quiet.
 * And because a hang never throws, the careful fallbacks those clients have around their calls
 * were unreachable.
 */
@DisplayName("outbound call deadlines")
class OutboundCallDefaultsTest {

    private final ApplicationContextRunner contexts = new ApplicationContextRunner()
            .withConfiguration(AutoConfigurations.of(ObservabilityAutoConfiguration.class));

    /** The two fields SimpleClientHttpRequestFactory keeps its deadlines in. */
    private static long connectMillis(ClientHttpRequestFactory factory) {
        return (int) ReflectionTestUtils.getField(factory, "connectTimeout");
    }

    private static long readMillis(ClientHttpRequestFactory factory) {
        return (int) ReflectionTestUtils.getField(factory, "readTimeout");
    }

    private static ClientHttpRequestFactory factoryOf(RestClientCustomizer customizer) {
        RestClient.Builder builder = RestClient.builder();
        customizer.customize(builder);
        // The builder keeps whatever factory was last set; that is the thing under test.
        return (ClientHttpRequestFactory) ReflectionTestUtils.getField(builder, "requestFactory");
    }

    @Test
    void are_applied_to_every_builder_without_any_configuration() {
        contexts.run(context -> {
            assertThat(context).hasBean("platformOutboundTimeouts");
            ClientHttpRequestFactory factory =
                    factoryOf(context.getBean(RestClientCustomizer.class));

            assertThat(factory).isInstanceOf(SimpleClientHttpRequestFactory.class);
            assertThat(connectMillis(factory)).isEqualTo(2000);
            assertThat(readMillis(factory)).isEqualTo(5000);
        });
    }

    @Test
    void can_be_lengthened_by_a_service_that_has_a_reason_to_wait() {
        contexts.withPropertyValues(
                        "delivery.clients.connect-timeout=4s",
                        "delivery.clients.read-timeout=30s")
                .run(context -> {
                    ClientHttpRequestFactory factory =
                            factoryOf(context.getBean(RestClientCustomizer.class));

                    assertThat(connectMillis(factory)).isEqualTo(4000);
                    assertThat(readMillis(factory)).isEqualTo(30_000);
                });
    }

    @Test
    @DisplayName("the record itself refuses to describe a call with no deadline")
    void a_missing_value_falls_back_rather_than_meaning_forever() {
        OutboundCallDefaults defaults = new OutboundCallDefaults(null, null);

        assertThat(defaults.connectTimeout()).isEqualTo(Duration.ofSeconds(2));
        assertThat(defaults.readTimeout()).isEqualTo(Duration.ofSeconds(5));
    }
}

package com.delivery.notifications.service;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.notifications.domain.TestCode;
import com.delivery.notifications.domain.TestCodeRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

/**
 * The only place a one-time code is kept, and the locks on it.
 *
 * <p>A code kept for a real address is the account-takeover this sink replaced, so every way a real
 * address could get in is tried here: the sink switched off, as it ships; another domain; a domain
 * that only looks like the test one; another channel. Each must keep nothing.
 */
class TestCodeSinkTest {

    private static final String CODE = "482913";
    private static final String SUBJECT = CODE + " is your YouDrop verification code";
    private static final String BODY = CODE + "\n\nUse this code to confirm your email address.";

    private TestCodeRepository codes;

    @BeforeEach
    void setUp() {
        codes = mock(TestCodeRepository.class);
    }

    @Nested
    @DisplayName("off unless an environment turns it on")
    class OffByDefault {

        /** With no setting at all, the bean Spring builds keeps nothing. */
        @Test
        void the_bean_is_off_when_nothing_is_configured() {
            new ApplicationContextRunner()
                    .withBean(TestCodeRepository.class, () -> codes)
                    .withUserConfiguration(TestCodeSink.class)
                    .run(context -> {
                        TestCodeSink sink = context.getBean(TestCodeSink.class);
                        assertThat(sink.isEnabled()).isFalse();
                        assertThat(sink.capture("EMAIL", "qa.one@youdrop.test",
                                "onboarding.verification", SUBJECT, BODY)).isFalse();
                    });
            verifyNoInteractions(codes);
        }

        /** And the shipped configuration is off too, unless the environment variable says on. */
        @Test
        void the_shipped_configuration_is_off_without_the_environment_variable() throws Exception {
            MockEnvironment environment = new MockEnvironment();
            for (PropertySource<?> source : new YamlPropertySourceLoader()
                    .load("application", new ClassPathResource("application.yml"))) {
                environment.getPropertySources().addLast(source);
            }

            assertThat(environment.getProperty("delivery.notifications.test-code-sink.enabled",
                    Boolean.class)).isFalse();

            environment.setProperty("TEST_CODE_SINK_ENABLED", "true");
            assertThat(environment.getProperty("delivery.notifications.test-code-sink.enabled",
                    Boolean.class)).isTrue();
        }

        @Test
        void switched_off_it_keeps_nothing_even_for_a_test_address() {
            TestCodeSink sink = new TestCodeSink(codes, false);

            assertThat(sink.accepts("EMAIL", "qa.one@youdrop.test")).isFalse();
            assertThat(sink.capture("EMAIL", "qa.one@youdrop.test", "onboarding.verification",
                    SUBJECT, BODY)).isFalse();
            verifyNoInteractions(codes);
        }
    }

    @Nested
    @DisplayName("switched on")
    class SwitchedOn {

        private TestCodeSink sink;

        @BeforeEach
        void on() {
            sink = new TestCodeSink(codes, true);
        }

        @Test
        void keeps_only_the_code_for_an_address_on_the_reserved_domain() {
            assertThat(sink.capture("EMAIL", " QA.One+run7@YouDrop.Test ", "onboarding.verification",
                    SUBJECT, BODY)).isTrue();

            ArgumentCaptor<TestCode> kept = ArgumentCaptor.forClass(TestCode.class);
            verify(codes).save(kept.capture());
            assertThat(kept.getValue().getRecipient()).isEqualTo("qa.one+run7@youdrop.test");
            assertThat(kept.getValue().getPurpose()).isEqualTo("onboarding.verification");
            assertThat(kept.getValue().getCode()).isEqualTo(CODE);
        }

        /** A day is plenty for a code that lives ten minutes; older rows go as new ones arrive. */
        @Test
        void drops_what_is_older_than_a_day_as_it_keeps_a_new_one() {
            Instant before = Instant.now().minus(TestCodeSink.KEPT_FOR);

            sink.capture("EMAIL", "qa.one@youdrop.test", "onboarding.verification", SUBJECT, BODY);

            ArgumentCaptor<Instant> cutoff = ArgumentCaptor.forClass(Instant.class);
            verify(codes).deleteOlderThan(cutoff.capture());
            assertThat(cutoff.getValue()).isAfterOrEqualTo(before)
                    .isBeforeOrEqualTo(Instant.now().minus(TestCodeSink.KEPT_FOR));
        }

        /** Every one of these is somebody's real mailbox, or could be. */
        @ParameterizedTest
        @ValueSource(strings = {
                "sam@example.com",
                "sam@youdrop.shop",
                "sam@youdrop.test.example.com",
                "sam@youdrop.testing",
                "sam@mail.youdrop.test",
                "victim@example.com@youdrop.test",
                "victim@example.com,qa@youdrop.test",
                "qa@youdrop.test victim@example.com",
                "\"victim@example.com\"@youdrop.test",
                "@youdrop.test",
                ""})
        void refuses_every_address_off_the_reserved_domain(String address) {
            assertThat(sink.accepts("EMAIL", address)).isFalse();
            assertThat(sink.capture("EMAIL", address, "onboarding.verification", SUBJECT, BODY))
                    .isFalse();
            verifyNoInteractions(codes);
        }

        @Test
        void refuses_a_missing_address_and_any_channel_but_email() {
            assertThat(sink.capture("EMAIL", null, "onboarding.verification", SUBJECT, BODY))
                    .isFalse();
            assertThat(sink.capture("SMS", "qa.one@youdrop.test", "onboarding.verification", null,
                    BODY)).isFalse();
            verifyNoInteractions(codes);
        }

        @Test
        void a_message_with_no_code_in_it_keeps_nothing() {
            assertThat(sink.capture("EMAIL", "qa.one@youdrop.test", "onboarding.verification",
                    "Welcome", "No code here, only 10 minutes")).isFalse();
            verify(codes, org.mockito.Mockito.never()).save(any());
        }
    }

    /**
     * The table repeats the domain rule as a CHECK, so a row for another address cannot exist
     * whatever writes it. Pinned to the same text, so the two cannot drift apart.
     */
    @Test
    void the_table_checks_the_same_address_rule() throws Exception {
        String migration = new String(new ClassPathResource(
                "db/migration/notification/V20__one_time_codes_out_of_the_log.sql")
                .getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);

        assertThat(migration).contains("recipient ~ '" + TestCodeSink.ADDRESS_RULE + "'");
        assertThat(List.of("qa.one@youdrop.test", "qa.one+run7@youdrop.test"))
                .allMatch(address -> new TestCodeSink(codes, true).accepts("EMAIL", address));
    }
}

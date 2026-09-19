package com.delivery.product.vision;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.vision.VisionProvider.Box;
import com.delivery.product.vision.VisionProvider.Detection;
import com.delivery.product.vision.VisionProvider.ShelfPhoto;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The vision provider seam, and the three ways it must not lie.
 *
 * <p>A typo in the provider name must not quietly mean "the fake" — an operator would believe a paid
 * provider was live. A missing key must not fail every scan either, because that is every
 * environment until the owner provisions one — so it answers with the fake, which stamps its own
 * name on the result. And whatever any provider returns is sanitised before it can reach a screen.
 */
@DisplayName("the vision provider seam")
class VisionProviderSeamTest {

    private static final ShelfPhoto PHOTO_A = new ShelfPhoto("shelf a".getBytes(StandardCharsets.UTF_8));
    private static final ShelfPhoto PHOTO_B = new ShelfPhoto("shelf b".getBytes(StandardCharsets.UTF_8));

    private static ClaudeVisionProvider claude(boolean keyPresent) {
        return new ClaudeVisionProvider("claude-opus-5", 16000, Duration.ofSeconds(1), 120,
                () -> keyPresent,
                params -> {
                    throw new AssertionError("no request may leave this test");
                });
    }

    @Nested
    @DisplayName("choosing a provider")
    class Choosing {

        @Test
        void nobody_choosing_means_the_fake() {
            MockEnvironment environment = new MockEnvironment();
            VisionProviders providers = new VisionProviders(
                    List.of(new FakeVisionProvider(), claude(true)), environment);

            assertThat(providers.active().name()).isEqualTo(FakeVisionProvider.NAME);
        }

        @Test
        void claude_with_a_key_is_claude() {
            MockEnvironment environment = new MockEnvironment()
                    .withProperty(VisionProviders.PROPERTY, "claude");
            VisionProviders providers = new VisionProviders(
                    List.of(new FakeVisionProvider(), claude(true)), environment);

            assertThat(providers.active().name()).isEqualTo(ClaudeVisionProvider.NAME);
        }

        /** The state of every environment until the owner provisions a key. */
        @Test
        void claude_without_a_key_answers_with_the_fake_which_names_itself() {
            MockEnvironment environment = new MockEnvironment()
                    .withProperty(VisionProviders.PROPERTY, "CLAUDE");
            VisionProviders providers = new VisionProviders(
                    List.of(new FakeVisionProvider(), claude(false)), environment);

            assertThat(providers.active().name()).isEqualTo(FakeVisionProvider.NAME);
        }

        @Test
        void a_name_that_matches_nothing_refuses_rather_than_falling_back() {
            MockEnvironment environment = new MockEnvironment()
                    .withProperty(VisionProviders.PROPERTY, "CLAUDIA");
            VisionProviders providers = new VisionProviders(
                    List.of(new FakeVisionProvider(), claude(true)), environment);

            assertThatThrownBy(providers::active)
                    .isInstanceOf(VisionException.class)
                    .hasMessageContaining("CLAUDIA");
        }

        /** Asking Claude directly with no key never reaches the network. */
        @Test
        void claude_refuses_to_call_at_all_without_a_key() {
            assertThatThrownBy(() -> claude(false).detect(List.of(PHOTO_A), List.of()))
                    .isInstanceOf(VisionException.class)
                    .satisfies(e -> assertThat(((VisionException) e).reason())
                            .isEqualTo(VisionException.Reason.NOT_CONFIGURED));
        }

        /**
         * Readiness is asked where the SDK's {@code fromEnv()} looks — the JVM property first, and it
         * wins whenever it is set, even blank — never in Spring's Environment. A key a Config Server
         * property could supply is a key the SDK would not send, and "ready" would then mean every
         * scan failing on authentication instead of answering with labelled samples.
         *
         * <p>Driven through the JVM property only, which is the half of the lookup this test can set
         * without depending on the environment of whatever machine runs the build.
         */
        @Test
        void readiness_is_asked_where_the_sdk_reads_the_key() {
            String previous = System.getProperty(ClaudeVisionProvider.API_KEY_PROPERTY);
            try {
                System.setProperty(ClaudeVisionProvider.API_KEY_PROPERTY, "sk-ant-test");
                assertThat(ClaudeVisionProvider.KeyPresence.SDK.present()).isTrue();

                // Set but blank: the SDK takes it over the environment variable, and sends no key.
                System.setProperty(ClaudeVisionProvider.API_KEY_PROPERTY, "   ");
                assertThat(ClaudeVisionProvider.KeyPresence.SDK.present()).isFalse();
            } finally {
                if (previous == null) {
                    System.clearProperty(ClaudeVisionProvider.API_KEY_PROPERTY);
                } else {
                    System.setProperty(ClaudeVisionProvider.API_KEY_PROPERTY, previous);
                }
            }
        }
    }

    @Nested
    @DisplayName("the fake provider")
    class Fake {

        private final FakeVisionProvider fake = new FakeVisionProvider();

        @Test
        void the_same_photo_gives_the_same_lines_every_time() {
            List<Detection> first = fake.detect(List.of(PHOTO_A, PHOTO_B), List.of("Drinks"));
            List<Detection> second = fake.detect(List.of(PHOTO_A, PHOTO_B), List.of("Drinks"));

            assertThat(first).isEqualTo(second);
            assertThat(first).isNotEmpty();
            assertThat(first).extracting(Detection::photoIndex).containsOnly(0, 1);
        }

        @Test
        void it_only_ever_suggests_a_section_it_was_offered() {
            List<Detection> lines = fake.detect(List.of(PHOTO_A, PHOTO_B), List.of("Cold Drinks"));

            assertThat(lines).extracting(Detection::category).containsOnly("Cold Drinks", "");
        }

        @Test
        void every_line_survives_sanitising_whole() {
            List<Detection> lines = fake.detect(List.of(PHOTO_A), List.of());

            assertThat(Detections.sanitize(lines, 1, 100)).hasSameSizeAs(lines)
                    .allSatisfy(clean -> {
                        assertThat(clean.box()).isNotNull();
                        assertThat(clean.priceGuess()).isNotNull();
                    });
        }
    }

    @Nested
    @DisplayName("sanitising what a provider says")
    class Sanitising {

        private Detection line(int photo, String name, double confidence, BigDecimal guess, Box box) {
            return new Detection(photo, name, "Brand", "1 L", "Drinks", confidence, guess, box);
        }

        @Test
        void a_line_with_no_name_or_for_a_photo_that_was_not_sent_is_dropped() {
            List<Detections.Clean> kept = Detections.sanitize(List.of(
                    line(0, "  ", 0.9, null, null),
                    line(3, "Pepsi", 0.9, null, null),
                    line(-1, "Pepsi", 0.9, null, null),
                    line(1, "Pepsi", 0.9, null, null)), 2, 100);

            assertThat(kept).extracting(Detections.Clean::photoIndex).containsExactly(1);
        }

        /**
         * Printed on a box by a stranger, and on a shopkeeper's screen next. The hostile characters
         * are built from code points so this source file itself stays plain text.
         */
        @Test
        void text_loses_control_characters_and_is_capped_at_its_column() {
            String escape = String.valueOf((char) 0x1B);
            String nul = String.valueOf((char) 0x00);
            String bidi = String.valueOf((char) 0x202E);
            String newline = String.valueOf((char) 0x0A);
            String hostile = "Pepsi " + escape + "[31m" + nul + bidi + " 1L" + newline + newline
                    + "x".repeat(400);

            Detections.Clean clean = Detections.sanitize(
                    List.of(line(0, hostile, 0.9, null, null)), 1, 100).get(0);

            assertThat(clean.name()).doesNotContain(escape).doesNotContain(nul)
                    .doesNotContain(bidi).doesNotContain(newline).startsWith("Pepsi");
            assertThat(clean.name().codePointCount(0, clean.name().length()))
                    .isLessThanOrEqualTo(Detections.MAX_NAME);
        }

        @Test
        void arabic_names_keep_their_letters() {
            Detections.Clean clean = Detections.sanitize(
                    List.of(line(0, "  حليب نيدو  ", 0.9, null, null)), 1, 100).get(0);

            assertThat(clean.name()).isEqualTo("حليب نيدو");
        }

        /** A clamped guess is still a number the platform does not have. */
        @Test
        void an_implausible_price_guess_is_dropped_not_clamped() {
            assertThat(Detections.sanitize(List.of(
                    line(0, "Pepsi", 0.9, new BigDecimal("0.001"), null),
                    line(0, "Nido", 0.9, new BigDecimal("12000"), null),
                    line(0, "Lays", 0.9, new BigDecimal("0.804"), null)), 1, 100))
                    .extracting(Detections.Clean::priceGuess)
                    .containsExactly(null, null, new BigDecimal("0.80"));
        }

        @Test
        void a_guess_sent_as_text_is_read_as_a_decimal_never_a_float() {
            assertThat(Detections.parseGuess("$1.20")).isEqualTo(new BigDecimal("1.20"));
            assertThat(Detections.parseGuess("")).isNull();
            assertThat(Detections.parseGuess("about a dollar")).isNull();
        }

        @Test
        void a_box_that_leaves_its_photo_is_dropped_and_confidence_is_clamped() {
            List<Detections.Clean> kept = Detections.sanitize(List.of(
                    line(0, "Out", 7.0, null, new Box(0.8, 0.1, 0.5, 0.2)),
                    line(0, "Zero", -1.0, null, new Box(0, 0, 0, 0)),
                    line(0, "In", 0.5, null, new Box(0.5, 0.5, 0.5, 0.5))), 1, 100);

            assertThat(kept.get(0).box()).isNull();
            assertThat(kept.get(0).confidence()).isEqualByComparingTo("1.000");
            assertThat(kept.get(1).box()).isNull();
            assertThat(kept.get(1).confidence()).isEqualByComparingTo("0.000");
            assertThat(kept.get(2).box()).isNotNull();
        }

        @Test
        void a_scan_never_stores_more_lines_than_its_cap() {
            List<Detection> many = java.util.stream.IntStream.range(0, 500)
                    .mapToObj(i -> line(0, "Item " + i, 0.5, null, null))
                    .toList();

            assertThat(Detections.sanitize(many, 1, 120)).hasSize(120);
        }
    }

    /**
     * Photo search for customers asks for a REAL reader and never gets the fake in its place: a sample
     * answer for a shopper would be shops selling something they never photographed.
     */
    @Nested
    @DisplayName("a real reader, for customers")
    class Real {

        @Test
        void nobody_choosing_means_no_real_reader_not_the_fake() {
            VisionProviders providers = new VisionProviders(
                    List.of(new FakeVisionProvider(), claude(true)), new MockEnvironment());

            assertThat(providers.real()).isEmpty();
            // Blitz still answers, with samples.
            assertThat(providers.active().name()).isEqualTo(FakeVisionProvider.NAME);
        }

        @Test
        void choosing_the_fake_by_name_is_no_real_reader_either() {
            VisionProviders providers = new VisionProviders(List.of(new FakeVisionProvider(), claude(true)),
                    new MockEnvironment().withProperty(VisionProviders.PROPERTY, "fake"));

            assertThat(providers.real()).isEmpty();
        }

        @Test
        void claude_without_a_key_is_no_real_reader_where_blitz_falls_back_to_samples() {
            VisionProviders providers = new VisionProviders(List.of(new FakeVisionProvider(), claude(false)),
                    new MockEnvironment().withProperty(VisionProviders.PROPERTY, "CLAUDE"));

            assertThat(providers.real()).isEmpty();
            assertThat(providers.active().name()).isEqualTo(FakeVisionProvider.NAME);
        }

        @Test
        void claude_with_a_key_is_the_real_reader() {
            VisionProviders providers = new VisionProviders(List.of(new FakeVisionProvider(), claude(true)),
                    new MockEnvironment().withProperty(VisionProviders.PROPERTY, "claude"));

            assertThat(providers.real()).hasValueSatisfying(
                    provider -> assertThat(provider.name()).isEqualTo(ClaudeVisionProvider.NAME));
        }

        @Test
        void a_name_that_matches_nothing_is_no_real_reader_and_does_not_throw() {
            VisionProviders providers = new VisionProviders(List.of(new FakeVisionProvider(), claude(true)),
                    new MockEnvironment().withProperty(VisionProviders.PROPERTY, "CLAUDIA"));

            assertThat(providers.real()).isEmpty();
        }
    }

    @Nested
    @DisplayName("the fake describing a product photo")
    class FakeDescribing {

        private final FakeVisionProvider fake = new FakeVisionProvider();

        @Test
        void the_same_photo_is_always_the_same_sample_product() {
            VisionProvider.ProductPhoto photo =
                    new VisionProvider.ProductPhoto("a jar".getBytes(StandardCharsets.UTF_8));

            VisionProvider.ProductDescription first = fake.describe(photo);
            VisionProvider.ProductDescription again = fake.describe(
                    new VisionProvider.ProductPhoto("a jar".getBytes(StandardCharsets.UTF_8)));

            assertThat(again).usingRecursiveComparison().isEqualTo(first);
            assertThat(first.isProduct()).isTrue();
            assertThat(first.name()).isNotBlank();
            assertThat(first.nameAr()).isNotBlank();
            assertThat(first.keywords()).isNotEmpty();
            assertThat(fake.name()).isEqualTo("FAKE");
        }

        /** A made-up code prefilled into a merchant's product form would pass for a real one. */
        @Test
        void a_sample_never_carries_a_barcode() {
            for (int i = 0; i < 40; i++) {
                assertThat(fake.describe(new VisionProvider.ProductPhoto(
                        ("photo " + i).getBytes(StandardCharsets.UTF_8))).barcode()).isNull();
            }
        }

        @Test
        void different_photos_choose_across_the_sample_shelf() {
            java.util.Set<String> names = new java.util.HashSet<>();
            for (int i = 0; i < 60; i++) {
                names.add(fake.describe(new VisionProvider.ProductPhoto(
                        ("photo " + i).getBytes(StandardCharsets.UTF_8))).name());
            }
            assertThat(names.size()).isGreaterThan(3);
        }
    }
}

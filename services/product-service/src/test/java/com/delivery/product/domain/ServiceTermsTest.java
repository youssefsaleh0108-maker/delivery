package com.delivery.product.domain;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.ServiceTerms.AttachmentPolicy;
import com.delivery.product.domain.ServiceTerms.Fulfilment;
import com.delivery.product.domain.ServiceTerms.PricingType;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * What a service offer may promise, the pause a service offer adds to a product's life, and the least
 * an option group adds to an offer's "From" price.
 *
 * <p>Pure domain: no repository and no service. The same rules reach a provider as 422s through
 * {@code CatalogService}, which {@code ServiceOffersTest} pins.
 */
@DisplayName("a service offer's terms and lifecycle")
class ServiceTermsTest {

    private static final UUID OFFER = UUID.randomUUID();

    private static ServiceTerms terms(PricingType pricing, String unitLabel, Integer unitSize,
                                      Integer minHours, Integer maxHours, Fulfilment fulfilment) {
        return new ServiceTerms(OFFER, pricing, unitLabel, unitSize, minHours, maxHours, fulfilment,
                null, null);
    }

    @Nested
    @DisplayName("turnaround")
    class Turnaround {

        @Test
        void a_range_of_whole_hours_is_kept() {
            ServiceTerms cards = terms(PricingType.FIXED, "cards", 500, 24, 48, Fulfilment.BOTH);

            assertThat(cards.getTurnaroundMinHours()).isEqualTo(24);
            assertThat(cards.getTurnaroundMaxHours()).isEqualTo(48);
        }

        @Test
        void same_day_work_may_start_at_zero_hours() {
            assertThatCode(() -> terms(PricingType.FIXED, null, 1, 0, 8, Fulfilment.PICKUP))
                    .doesNotThrowAnyException();
        }

        @Test
        void the_longest_may_not_be_shorter_than_the_shortest() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, 48, 24, Fulfilment.PICKUP))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("longest turnaround (24 hours)")
                    .hasMessageContaining("shortest (48 hours)");
        }

        @Test
        void a_start_below_zero_is_refused() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, -1, 24, Fulfilment.PICKUP))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("zero hours");
        }

        /** Work that is ready the moment it is accepted is not a turnaround. */
        @Test
        void work_that_takes_no_time_at_all_is_refused() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, 0, 0, Fulfilment.PICKUP))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("at least one hour");
        }

        @Test
        void thirty_days_is_the_longest_an_offer_may_promise() {
            assertThatCode(() -> terms(PricingType.FIXED, null, 1, 24, 720, Fulfilment.PICKUP))
                    .doesNotThrowAnyException();
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, 24, 721, Fulfilment.PICKUP))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("720 hours");
        }

        @Test
        void both_ends_are_required() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, 24, null, Fulfilment.PICKUP))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("how long the work takes");
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, null, 24, Fulfilment.PICKUP))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    @DisplayName("units and packs")
    class UnitsAndPacks {

        @Test
        void a_pack_says_what_it_is_a_pack_of() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, " ", 500, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("A pack of 500");

            assertThat(terms(PricingType.FIXED, " cards ", 500, 24, 48, Fulfilment.BOTH).getUnitLabel())
                    .isEqualTo("cards");
        }

        /** An order line is priced per pack, so a price per unit is a pack of one. */
        @Test
        void a_price_per_unit_is_for_one_unit() {
            assertThatThrownBy(() -> terms(PricingType.PER_UNIT, "sqm", 10, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("fixed price");

            assertThat(terms(PricingType.PER_UNIT, "sqm", 1, 24, 48, Fulfilment.BOTH).getUnitSize())
                    .isEqualTo(1);
        }

        @Test
        void a_price_per_unit_names_its_unit() {
            assertThatThrownBy(() -> terms(PricingType.PER_UNIT, null, 1, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("sqm or page");
        }

        @Test
        void one_unit_at_a_fixed_price_needs_no_label_and_is_the_default_pack() {
            ServiceTerms alteration = terms(PricingType.FIXED, "", null, 24, 72, Fulfilment.PICKUP);

            assertThat(alteration.getUnitSize()).isEqualTo(1);
            assertThat(alteration.getUnitLabel()).isNull();
        }

        @Test
        void a_pack_is_between_one_and_a_hundred_thousand_units() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, "flyers", 0, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThatThrownBy(() -> terms(PricingType.FIXED, "flyers", 100_001, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class);
            assertThat(terms(PricingType.FIXED, "flyers", 100_000, 24, 48, Fulfilment.BOTH).getUnitSize())
                    .isEqualTo(100_000);
        }

        @Test
        void a_unit_over_forty_characters_is_refused() {
            assertThatThrownBy(() -> terms(PricingType.FIXED, "x".repeat(41), 2, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    @DisplayName("choices and defaults")
    class ChoicesAndDefaults {

        @Test
        void pricing_and_fulfilment_are_required() {
            assertThatThrownBy(() -> terms(null, null, 1, 24, 48, Fulfilment.BOTH))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("priced");
            assertThatThrownBy(() -> terms(PricingType.FIXED, null, 1, 24, 48, null))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("pickup, delivery, or both");
        }

        @Test
        void no_file_is_asked_for_unless_the_provider_says_so() {
            assertThat(terms(PricingType.FIXED, null, 1, 24, 48, Fulfilment.BOTH).getAttachmentPolicy())
                    .isEqualTo(AttachmentPolicy.NONE);
        }

        @Test
        void delivery_is_offered_by_delivery_and_both_but_not_by_pickup() {
            assertThat(Fulfilment.DELIVERY.includesDelivery()).isTrue();
            assertThat(Fulfilment.BOTH.includesDelivery()).isTrue();
            assertThat(Fulfilment.PICKUP.includesDelivery()).isFalse();
            assertThat(Fulfilment.PICKUP.includesPickup()).isTrue();
            assertThat(Fulfilment.DELIVERY.includesPickup()).isFalse();
        }

        @Test
        void a_refused_revision_changes_nothing() {
            ServiceTerms cards = terms(PricingType.FIXED, "cards", 500, 24, 48, Fulfilment.BOTH);

            assertThatThrownBy(() -> cards.revise(PricingType.PER_UNIT, "sqm", 1, 72, 24,
                    Fulfilment.DELIVERY, AttachmentPolicy.REQUIRED, "Which size?"))
                    .isInstanceOf(IllegalArgumentException.class);

            assertThat(cards.getPricingType()).isEqualTo(PricingType.FIXED);
            assertThat(cards.getUnitSize()).isEqualTo(500);
            assertThat(cards.getTurnaroundMaxHours()).isEqualTo(48);
            assertThat(cards.getFulfilmentModes()).isEqualTo(Fulfilment.BOTH);
            assertThat(cards.getAttachmentPolicy()).isEqualTo(AttachmentPolicy.NONE);
        }

        @Test
        void terms_belong_to_an_offer() {
            assertThatThrownBy(() -> new ServiceTerms(null, PricingType.FIXED, null, 1, 24, 48,
                    Fulfilment.BOTH, null, null))
                    .isInstanceOf(IllegalArgumentException.class);
        }
    }

    @Nested
    @DisplayName("pausing and resuming an offer")
    class PausingAndResuming {

        private Product liveOffer() {
            Product offer = new Product("provider-sub", UUID.randomUUID(), "Business card printing",
                    null, new BigDecimal("15.00"), null);
            offer.addImage("products/cards.jpg");
            offer.publish();
            return offer;
        }

        @Test
        void a_live_offer_pauses_and_resumes() {
            Product offer = liveOffer();

            offer.pause();
            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);

            offer.resume();
            assertThat(offer.getStatus()).isEqualTo(Product.Status.ACTIVE);
        }

        @Test
        void only_a_live_offer_can_be_paused() {
            Product draft = new Product("provider-sub", UUID.randomUUID(), "Flyers", null,
                    new BigDecimal("25.00"), null);
            Product archived = liveOffer();
            archived.archive();

            assertThatThrownBy(draft::pause).isInstanceOf(IllegalStateException.class);
            assertThatThrownBy(archived::pause).isInstanceOf(IllegalStateException.class);
            assertThat(draft.getStatus()).isEqualTo(Product.Status.DRAFT);
            assertThat(archived.getStatus()).isEqualTo(Product.Status.ARCHIVED);
        }

        @Test
        void only_a_paused_offer_can_be_resumed() {
            Product live = liveOffer();

            assertThatThrownBy(live::resume)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("Only a paused offer");
        }

        /** Removing the last photo of a paused offer leaves it paused; resuming it needs a photo. */
        @Test
        void resuming_needs_a_photo_again() {
            Product offer = liveOffer();
            offer.pause();
            offer.removeImage("products/cards.jpg");

            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
            assertThatThrownBy(offer::resume)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("photo");
            assertThat(offer.getStatus()).isEqualTo(Product.Status.PAUSED);
        }
    }

    @Nested
    @DisplayName("the least an option group adds")
    class TheLeastAGroupAdds {

        private ProductOptionGroup group(int minSelect, int maxSelect, String... deltas) {
            ProductOptionGroup group = new ProductOptionGroup(OFFER, "Paper type", minSelect,
                    maxSelect, 0);
            List<ProductOption> options = new ArrayList<>();
            for (int i = 0; i < deltas.length; i++) {
                options.add(new ProductOption("Paper " + i, new BigDecimal(deltas[i]), false, i));
            }
            group.replaceOptions(options);
            return group;
        }

        @Test
        void a_required_single_choice_adds_its_cheapest_option() {
            assertThat(group(1, 1, "2.50", "0.75", "4.00").minimumDelta()).isEqualByComparingTo("0.75");
        }

        @Test
        void an_optional_group_of_surcharges_adds_nothing() {
            assertThat(group(0, 3, "1.00", "2.00").minimumDelta()).isEqualByComparingTo("0");
        }

        @Test
        void a_discount_anybody_can_take_lowers_it() {
            assertThat(group(0, 2, "-1.00", "-0.50", "3.00").minimumDelta())
                    .isEqualByComparingTo("-1.50");
        }

        @Test
        void the_group_maximum_caps_the_discounts_taken() {
            assertThat(group(0, 1, "-1.00", "-0.50").minimumDelta()).isEqualByComparingTo("-1.00");
        }

        @Test
        void choose_two_adds_the_two_cheapest() {
            assertThat(group(2, 2, "5.00", "1.00", "2.00").minimumDelta()).isEqualByComparingTo("3.00");
        }

        @Test
        void a_sold_out_option_is_not_counted() {
            ProductOptionGroup papers = group(1, 1, "0.50", "2.00");
            papers.getOptions().get(0).setAvailable(false);

            assertThat(papers.minimumDelta()).isEqualByComparingTo("2.00");
        }
    }
}

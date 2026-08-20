package com.delivery.product.service;

import java.lang.reflect.Field;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductOption;
import com.delivery.product.domain.ProductOptionGroup;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * What a line actually costs once the customer has chosen their options.
 *
 * <p>This is the price the order path trusts. Order Manager deliberately does not add option deltas
 * up itself — the catalog owns prices, and a second implementation of this sum is a second thing
 * that can quietly disagree with the menu the customer was reading. Everything a client could send
 * to try to move the number is checked here: duplicates, ids from another product, stale ids, sold
 * out options, and selections that break the group's own rules.
 */
class ProductOptionPricingTest {

    private static final UUID PRODUCT = UUID.randomUUID();

    private ProductRepository products;
    private ProductOptionGroupRepository groups;
    private ProductOptionService options;

    @BeforeEach
    void setUp() {
        products = mock(ProductRepository.class);
        groups = mock(ProductOptionGroupRepository.class);
        options = new ProductOptionService(products, groups);

        when(groups.findByProductIdOrderByPositionAsc(any(UUID.class))).thenReturn(List.of());
    }

    private void productPricedAt(String price) {
        Product product = mock(Product.class);
        when(product.getPrice()).thenReturn(new BigDecimal(price));
        when(products.findById(PRODUCT)).thenReturn(Optional.of(product));
    }

    private ProductOptionGroup group(String name, int min, int max, ProductOption... within) {
        ProductOptionGroup group = new ProductOptionGroup(PRODUCT, name, min, max, 0);
        group.replaceOptions(List.of(within));
        return group;
    }

    private void groupsAre(ProductOptionGroup... available) {
        when(groups.findByProductIdOrderByPositionAsc(PRODUCT)).thenReturn(List.of(available));
    }

    private static ProductOption option(String name, String delta) {
        return new ProductOption(name, new BigDecimal(delta), false, 0);
    }

    /** The group is what owns the options, so a foreign one needs its own parent. */
    private static ProductOption optionOfAnotherProduct(String name) {
        ProductOptionGroup elsewhere =
                new ProductOptionGroup(UUID.randomUUID(), "Other product's group", 0, 1, 0);
        ProductOption foreign = option(name, "5.00");
        elsewhere.replaceOptions(List.of(foreign));
        return foreign;
    }

    @Nested
    @DisplayName("the sum")
    class Pricing {

        @Test
        void a_product_with_no_options_costs_its_base_price() {
            productPricedAt("12.50");

            ProductOptionService.PricedSelection priced = options.price(PRODUCT, List.of());

            assertThat(priced.unitPrice()).isEqualByComparingTo("12.50");
            assertThat(priced.basePrice()).isEqualByComparingTo("12.50");
            assertThat(priced.options()).isEmpty();
        }

        @Test
        void a_chosen_option_adds_its_delta() {
            productPricedAt("12.50");
            ProductOption large = option("Large", "3.00");
            groupsAre(group("Size", 1, 1, large, option("Small", "0.00")));

            assertThat(options.price(PRODUCT, List.of(large.getId())).unitPrice())
                    .isEqualByComparingTo("15.50");
        }

        @Test
        void deltas_from_several_groups_all_apply() {
            productPricedAt("10.00");
            ProductOption large = option("Large", "3.00");
            ProductOption bacon = option("Bacon", "1.75");
            groupsAre(group("Size", 1, 1, large), group("Extras", 0, 3, bacon));

            assertThat(options.price(PRODUCT, List.of(large.getId(), bacon.getId())).unitPrice())
                    .isEqualByComparingTo("14.75");
        }

        /** A discount option is legitimate — a smaller size that costs less. */
        @Test
        void a_negative_delta_reduces_the_price() {
            productPricedAt("10.00");
            ProductOption small = option("Small", "-2.00");
            groupsAre(group("Size", 1, 1, small));

            assertThat(options.price(PRODUCT, List.of(small.getId())).unitPrice())
                    .isEqualByComparingTo("8.00");
        }

        /** A line cannot pay the customer, however the deltas were configured. */
        @Test
        void a_line_can_never_price_below_zero() {
            productPricedAt("1.00");
            ProductOption absurd = option("Enormous discount", "-99.00");
            groupsAre(group("Size", 1, 1, absurd));

            assertThat(options.price(PRODUCT, List.of(absurd.getId())).unitPrice())
                    .isEqualByComparingTo("0.00");
        }

        @Test
        void the_chosen_options_come_back_named_for_the_receipt() {
            productPricedAt("10.00");
            ProductOption large = option("Large", "3.00");
            groupsAre(group("Size", 1, 1, large));

            List<ProductOptionService.ChosenOption> chosen =
                    options.price(PRODUCT, List.of(large.getId())).options();

            assertThat(chosen).singleElement().satisfies(c -> {
                assertThat(c.groupName()).isEqualTo("Size");
                assertThat(c.optionName()).isEqualTo("Large");
                assertThat(c.priceDelta()).isEqualByComparingTo("3.00");
            });
        }

        /** Fractional deltas must not drift — this is money, so the arithmetic stays decimal. */
        @Test
        void fractional_deltas_add_up_exactly() {
            productPricedAt("0.10");
            ProductOption a = option("a", "0.20");
            ProductOption b = option("b", "0.03");
            groupsAre(group("Extras", 0, 5, a, b));

            assertThat(options.price(PRODUCT, List.of(a.getId(), b.getId())).unitPrice())
                    .isEqualByComparingTo("0.33");
        }

        @Test
        void a_null_selection_is_treated_as_no_selection() {
            productPricedAt("12.50");

            assertThat(options.price(PRODUCT, null).unitPrice()).isEqualByComparingTo("12.50");
        }
    }

    @Nested
    @DisplayName("what a client cannot do to the price")
    class Abuse {

        /**
         * Sending the same id twice must not apply its delta twice — which matters most when the
         * delta is negative and the repeat is a discount.
         */
        @Test
        void sending_the_same_option_twice_only_charges_it_once() {
            productPricedAt("10.00");
            ProductOption discount = option("Loyalty", "-2.00");
            groupsAre(group("Discounts", 0, 1, discount));

            ProductOptionService.PricedSelection priced =
                    options.price(PRODUCT, List.of(discount.getId(), discount.getId(),
                            discount.getId()));

            assertThat(priced.unitPrice()).isEqualByComparingTo("8.00");
            assertThat(priced.options()).hasSize(1);
        }

        /** Borrowing a cheap option from another product would price this one wrongly. */
        @Test
        void an_option_belonging_to_another_product_is_refused() {
            productPricedAt("10.00");
            groupsAre(group("Size", 0, 1, option("Large", "3.00")));

            assertThatThrownBy(() -> options.price(PRODUCT,
                    List.of(optionOfAnotherProduct("Their cheap option").getId())))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("does not belong to this product");
        }

        /** Silently ignoring an unknown id would price a selection the customer did not make. */
        @Test
        void an_invented_option_id_is_refused_rather_than_ignored() {
            productPricedAt("10.00");
            groupsAre(group("Size", 0, 1, option("Large", "3.00")));

            assertThatThrownBy(() -> options.price(PRODUCT, List.of(UUID.randomUUID())))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        @Test
        void an_unknown_product_is_refused() {
            when(products.findById(PRODUCT)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> options.price(PRODUCT, List.of()))
                    .isInstanceOf(ProductNotFoundException.class);
        }
    }

    @Nested
    @DisplayName("the group's own rules")
    class GroupRules {

        /** Checked across every group, not just the answered ones — that is what catches a gap. */
        @Test
        void a_required_group_left_unanswered_is_refused() {
            productPricedAt("10.00");
            groupsAre(group("Size", 1, 1, option("Large", "3.00")));

            assertThatThrownBy(() -> options.price(PRODUCT, List.of()))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("needs a selection");
        }

        @Test
        void an_optional_group_left_unanswered_is_fine() {
            productPricedAt("10.00");
            groupsAre(group("Extras", 0, 3, option("Bacon", "1.75")));

            assertThat(options.price(PRODUCT, List.of()).unitPrice()).isEqualByComparingTo("10.00");
        }

        @Test
        void choosing_more_than_the_group_allows_is_refused() {
            productPricedAt("10.00");
            ProductOption a = option("A", "1.00");
            ProductOption b = option("B", "1.00");
            groupsAre(group("Size", 1, 1, a, b));

            assertThatThrownBy(() -> options.price(PRODUCT, List.of(a.getId(), b.getId())))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        @Test
        void choosing_fewer_than_a_multi_select_group_requires_is_refused() {
            productPricedAt("10.00");
            ProductOption a = option("A", "1.00");
            groupsAre(group("Pick two", 2, 3, a, option("B", "1.00"), option("C", "1.00")));

            assertThatThrownBy(() -> options.price(PRODUCT, List.of(a.getId())))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("at least 2");
        }

        /** A sold-out option must not be orderable just because its id is still valid. */
        @Test
        void a_sold_out_option_is_refused() {
            productPricedAt("10.00");
            ProductOption soldOut = option("Bacon", "1.75");
            soldOut.setAvailable(false);
            groupsAre(group("Extras", 0, 3, soldOut));

            assertThatThrownBy(() -> options.price(PRODUCT, List.of(soldOut.getId())))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("sold out");
        }

        /** A group name written imperatively must still read properly in the refusal. */
        @Test
        void the_group_name_is_quoted_so_imperative_names_still_read() {
            productPricedAt("10.00");
            groupsAre(group("Choose Size", 1, 1, option("Large", "3.00")));

            assertThatThrownBy(() -> options.price(PRODUCT, List.of()))
                    .hasMessageContaining("\"Choose Size\"");
        }
    }

    @Nested
    @DisplayName("editing a product's options")
    class Replacing {

        @BeforeEach
        void productIsOwned() {
            when(products.findByIdAndMerchantId(PRODUCT, "merchant-sub"))
                    .thenReturn(Optional.of(mock(Product.class)));
        }

        /** Another merchant must not be able to reprice this product by editing its options. */
        @Test
        void a_merchant_who_does_not_own_the_product_is_refused() {
            when(products.findByIdAndMerchantId(PRODUCT, "other-merchant"))
                    .thenReturn(Optional.empty());

            assertThatThrownBy(() -> options.replace(PRODUCT, "other-merchant", List.of()))
                    .isInstanceOf(ProductNotFoundException.class);
        }

        /** A group offering nothing is a dead end on the menu. */
        @Test
        void a_group_with_no_options_is_refused() {
            assertThatThrownBy(() -> options.replace(PRODUCT, "merchant-sub",
                    List.of(groupRequest("Size", 0, 1))))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("at least one option");
        }

        /** Asking for two choices from a group offering one can never be satisfied. */
        @Test
        void a_group_demanding_more_choices_than_it_offers_is_refused() {
            assertThatThrownBy(() -> options.replace(PRODUCT, "merchant-sub",
                    List.of(groupRequest("Pick two", 2, 3, optionRequest("Only one")))))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("offers");
        }

        @Test
        void a_group_whose_maximum_is_below_its_minimum_is_refused() {
            assertThatThrownBy(() -> options.replace(PRODUCT, "merchant-sub",
                    List.of(groupRequest("Backwards", 3, 1, optionRequest("A")))))
                    .isInstanceOf(CatalogRuleViolationException.class);
        }

        private com.delivery.product.api.dto.OptionDtos.OptionGroupRequest groupRequest(
                String name, int min, int max,
                com.delivery.product.api.dto.OptionDtos.OptionRequest... within) {
            return new com.delivery.product.api.dto.OptionDtos.OptionGroupRequest(
                    name, min, max, List.of(within));
        }

        private com.delivery.product.api.dto.OptionDtos.OptionRequest optionRequest(String name) {
            return new com.delivery.product.api.dto.OptionDtos.OptionRequest(
                    name, BigDecimal.ZERO, false);
        }
    }
}

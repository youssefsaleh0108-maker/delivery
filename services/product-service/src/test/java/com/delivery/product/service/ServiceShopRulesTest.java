package com.delivery.product.service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.mock.env.MockEnvironment;

import com.delivery.product.api.dto.StoreDtos.StoreRequest;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreFavoriteRepository;
import com.delivery.product.domain.StoreOfferRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

import static com.delivery.product.domain.Store.ServiceCategory.BEAUTY;
import static com.delivery.product.domain.Store.ServiceCategory.CLEANING;
import static com.delivery.product.domain.Store.ServiceCategory.PHOTOGRAPHY;
import static com.delivery.product.domain.Store.ServiceCategory.PRINTING;
import static com.delivery.product.domain.Store.ServiceCategory.REPAIRS;
import static com.delivery.product.domain.Store.ServiceCategory.TAILORING;
import static com.delivery.product.domain.Store.ServiceCategory.TUTORING;
import static com.delivery.product.domain.Store.Vertical.COFFEE;
import static com.delivery.product.domain.Store.Vertical.GROCERY;
import static com.delivery.product.domain.Store.Vertical.RESTAURANT;
import static com.delivery.product.domain.Store.Vertical.SERVICES;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * What a provider may do to a service shop, and what the switch that opens categories means.
 *
 * <p>The rule most worth reading is the first one under "saving": an app built before services
 * existed reads SERVICES as RESTAURANT and sends that back on every profile save. Without the refusal,
 * fixing a typo in a print shop's tagline on an old phone would turn it into a restaurant.
 */
@DisplayName("opening and saving a service shop")
class ServiceShopRulesTest {

    private static final String MERCHANT = "merchant-sub";

    /** A name in the setting that is not a category: the platform's mistake, never the merchant's. */
    private static final String TYPO = "PRINTNG";

    private StoreRepository stores;
    private MockEnvironment environment;
    private StoreService service;

    @BeforeEach
    void setUp() {
        stores = mock(StoreRepository.class);
        environment = new MockEnvironment();
        service = new StoreService(stores, mock(StoreOfferRepository.class),
                mock(StoreFavoriteRepository.class), mock(ProductRepository.class),
                mock(CategoryRepository.class), new ServiceCategories(environment),
                mock(OnboardingApplicationClient.class),
                Clock.fixed(Instant.parse("2026-09-13T10:00:00Z"), ZoneOffset.UTC),
                Duration.ofHours(4), "Asia/Beirut");
        when(stores.save(any(Store.class))).thenAnswer(call -> call.getArgument(0));
    }

    private static StoreRequest profile(String name, Store.Vertical vertical,
                                        Store.ServiceCategory category) {
        return new StoreRequest(name, vertical, "Cards, flyers and banners", null, List.of(), null,
                "Armenia Street", null, category);
    }

    @Nested
    @DisplayName("opening one")
    class Opening {

        @Test
        void a_print_shop_opens_filed_under_printing() {
            Store opened = service.create(MERCHANT,
                    profile("Al Fakhry Press", SERVICES, PRINTING)).store();

            assertThat(opened.getVertical()).isEqualTo(SERVICES);
            assertThat(opened.getServiceCategory()).isEqualTo(PRINTING);
        }

        @Test
        void a_service_shop_must_say_what_it_does() {
            assertThatThrownBy(() -> service.create(MERCHANT,
                    profile("Al Fakhry Press", SERVICES, null)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("needs a service category");
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        void a_goods_shop_cannot_carry_a_service_category() {
            assertThatThrownBy(() -> service.create(MERCHANT,
                    profile("Abu Hassan Mini Market", GROCERY, PRINTING)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Only a services shop");
            verify(stores, never()).save(any(Store.class));
        }

        /** Owner default 1: Cleaning exists in the taxonomy but is not offered. */
        @Test
        void a_closed_category_cannot_be_chosen() {
            assertThatThrownBy(() -> service.create(MERCHANT,
                    profile("Spotless Cleaners", SERVICES, CLEANING)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("CLEANING")
                    .hasMessageContaining("not offered");
            verify(stores, never()).save(any(Store.class));
        }

        @Test
        void a_category_opened_in_configuration_can_be_chosen() {
            environment.setProperty(ServiceCategories.PROPERTY, "PRINTING,CLEANING");

            Store opened = service.create(MERCHANT,
                    profile("Spotless Cleaners", SERVICES, CLEANING)).store();

            assertThat(opened.getServiceCategory()).isEqualTo(CLEANING);
        }

        @Test
        void a_goods_shop_opens_exactly_as_before() {
            Store opened = service.create(MERCHANT, profile("Beirut Grill", RESTAURANT, null)).store();

            assertThat(opened.getVertical()).isEqualTo(RESTAURANT);
            assertThat(opened.getServiceCategory()).isNull();
        }

        /**
         * A typo in the setting is a server error, which the handler logs and answers without naming
         * anything internal. It is not a 422, whose sentence would send a merchant to a property they
         * cannot see. The same answer as re-filing a shop under the same typo, below.
         */
        @Test
        void a_typo_in_the_setting_is_a_server_error_not_a_refusal() {
            environment.setProperty(ServiceCategories.PROPERTY, TYPO);

            assertThatThrownBy(() -> service.create(MERCHANT,
                    profile("Al Fakhry Press", SERVICES, PRINTING)))
                    .isInstanceOf(IllegalStateException.class)
                    .isNotInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining(TYPO);
            verify(stores, never()).save(any(Store.class));
        }

        /** A goods shop never reads the setting, so a mistake in it cannot stop one opening. */
        @Test
        void a_typo_in_the_setting_never_stops_a_goods_shop_opening() {
            environment.setProperty(ServiceCategories.PROPERTY, TYPO);

            Store opened = service.create(MERCHANT, profile("Beirut Grill", RESTAURANT, null)).store();

            assertThat(opened.getVertical()).isEqualTo(RESTAURANT);
        }
    }

    @Nested
    @DisplayName("saving its profile")
    class Saving {

        private Store press;
        private Store grill;

        @BeforeEach
        void shops() {
            press = new Store(MERCHANT, "Al Fakhry Press", SERVICES, PRINTING);
            grill = new Store(MERCHANT, "Beirut Grill", RESTAURANT);
            when(stores.findByIdAndMerchantId(press.getId(), MERCHANT)).thenReturn(Optional.of(press));
            when(stores.findByIdAndMerchantId(grill.getId(), MERCHANT)).thenReturn(Optional.of(grill));
        }

        /**
         * The save this rule exists for. An app built before services reads SERVICES as RESTAURANT,
         * draws the form with Restaurants selected, and sends that back with every tagline edit.
         */
        @Test
        void an_old_app_saving_a_print_shop_as_a_restaurant_is_refused_and_changes_nothing() {
            assertThatThrownBy(() -> service.update(press.getId(), MERCHANT,
                    profile("Renamed by an old app", RESTAURANT, null)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("cannot become a goods shop");

            assertThat(press.getVertical()).isEqualTo(SERVICES);
            assertThat(press.getServiceCategory()).isEqualTo(PRINTING);
            assertThat(press.getName()).isEqualTo("Al Fakhry Press");
        }

        @Test
        void a_goods_shop_cannot_become_a_service_shop() {
            assertThatThrownBy(() -> service.update(grill.getId(), MERCHANT,
                    profile("Beirut Grill", SERVICES, PRINTING)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("cannot become a services shop");

            assertThat(grill.getVertical()).isEqualTo(RESTAURANT);
            assertThat(grill.getServiceCategory()).isNull();
        }

        @Test
        void goods_verticals_still_move_between_themselves() {
            service.update(grill.getId(), MERCHANT, profile("Beirut Grill", COFFEE, null));

            assertThat(grill.getVertical()).isEqualTo(COFFEE);
        }

        @Test
        void a_save_that_does_not_mention_the_category_keeps_it() {
            service.update(press.getId(), MERCHANT, profile("Al Fakhry Press & Sons", SERVICES, null));

            assertThat(press.getServiceCategory()).isEqualTo(PRINTING);
            assertThat(press.getName()).isEqualTo("Al Fakhry Press & Sons");
        }

        @Test
        void a_service_shop_can_be_refiled_under_another_open_category() {
            service.update(press.getId(), MERCHANT, profile("Al Fakhry Press", SERVICES, PHOTOGRAPHY));

            assertThat(press.getServiceCategory()).isEqualTo(PHOTOGRAPHY);
        }

        @Test
        void but_not_under_a_closed_one() {
            assertThatThrownBy(() -> service.update(press.getId(), MERCHANT,
                    profile("Al Fakhry Press", SERVICES, TUTORING)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("TUTORING");

            assertThat(press.getServiceCategory()).isEqualTo(PRINTING);
        }

        /**
         * Re-filing under a typo in the setting: the same server error as opening a shop under it.
         * The setting used to be read inside the block that turns a refused save into a 422, so the
         * merchant was answered with a sentence naming it, and only after the profile had been
         * applied to the shop.
         */
        @Test
        void a_typo_in_the_setting_fails_a_refiling_as_a_server_error_before_touching_the_shop() {
            environment.setProperty(ServiceCategories.PROPERTY, TYPO);

            assertThatThrownBy(() -> service.update(press.getId(), MERCHANT,
                    profile("Renamed mid-save", SERVICES, PHOTOGRAPHY)))
                    .isInstanceOf(IllegalStateException.class)
                    .isNotInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining(TYPO);

            assertThat(press.getServiceCategory()).isEqualTo(PRINTING);
            assertThat(press.getName()).isEqualTo("Al Fakhry Press");
        }

        /** A save that re-files nothing judges no category, so a tagline edit survives the typo. */
        @Test
        void a_typo_in_the_setting_does_not_stop_a_save_that_refiles_nothing() {
            environment.setProperty(ServiceCategories.PROPERTY, TYPO);

            service.update(press.getId(), MERCHANT,
                    profile("Al Fakhry Press & Sons", SERVICES, PRINTING));

            assertThat(press.getName()).isEqualTo("Al Fakhry Press & Sons");
            assertThat(press.getServiceCategory()).isEqualTo(PRINTING);
        }

        /** Closing a category is about what is offered next, not a reason to rewrite a shop in it. */
        @Test
        void a_shop_whose_category_has_since_closed_can_still_save_its_profile() {
            environment.setProperty(ServiceCategories.PROPERTY, "TAILORING");

            service.update(press.getId(), MERCHANT, profile("Al Fakhry Press", SERVICES, PRINTING));

            assertThat(press.getServiceCategory()).isEqualTo(PRINTING);
            assertThat(press.getTagline()).isEqualTo("Cards, flyers and banners");
        }

        @Test
        void a_goods_shop_cannot_take_a_service_category() {
            assertThatThrownBy(() -> service.update(grill.getId(), MERCHANT,
                    profile("Beirut Grill", RESTAURANT, PRINTING)))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("Only a services shop");

            assertThat(grill.getServiceCategory()).isNull();
        }
    }

    @Nested
    @DisplayName("the switch that opens categories")
    class Switch {

        @Test
        void with_nothing_configured_the_four_launch_categories_are_open() {
            assertThat(new ServiceCategories(new MockEnvironment()).enabled())
                    .containsExactly(PRINTING, TAILORING, REPAIRS, PHOTOGRAPHY);
        }

        /** The shipped configuration opens the same four: owner default 1. */
        @Test
        void the_shipped_configuration_opens_the_same_four() throws Exception {
            MockEnvironment shipped = shippedConfiguration();

            assertThat(shipped.getProperty(ServiceCategories.PROPERTY)).isNotNull();
            assertThat(new ServiceCategories(shipped).enabled())
                    .containsExactly(PRINTING, TAILORING, REPAIRS, PHOTOGRAPHY);
        }

        @Test
        void a_list_is_read_forgivingly_for_spaces_and_case() {
            MockEnvironment env = new MockEnvironment()
                    .withProperty(ServiceCategories.PROPERTY, " printing , Cleaning,");

            assertThat(new ServiceCategories(env).enabled()).containsExactly(PRINTING, CLEANING);
        }

        /** A YAML list arrives as indexed keys, which a plain property lookup does not see. */
        @Test
        void a_yaml_list_is_read_too() {
            MockEnvironment env = new MockEnvironment()
                    .withProperty(ServiceCategories.PROPERTY + "[0]", "REPAIRS")
                    .withProperty(ServiceCategories.PROPERTY + "[1]", "BEAUTY");

            assertThat(new ServiceCategories(env).enabled()).containsExactly(REPAIRS, BEAUTY);
        }

        /**
         * The shape a Config Server or a profile override takes: a YAML list, in a source above
         * application.yml, whose own value is the flat launch default. The list replaces the default,
         * as a list does for any Spring Boot setting. Asking the environment for the property by name
         * found the flat default first, so a category closed this way stayed open.
         */
        @Test
        void a_list_set_above_the_shipped_default_replaces_it() throws Exception {
            MockEnvironment env = shippedConfiguration();
            env.getPropertySources().addFirst(new MapPropertySource("configserver", Map.of(
                    ServiceCategories.PROPERTY + "[0]", "PRINTING",
                    ServiceCategories.PROPERTY + "[1]", "REPAIRS")));

            assertThat(new ServiceCategories(env).enabled()).containsExactly(PRINTING, REPAIRS);
        }

        /** And the other way round: one value above a listed default replaces the whole list. */
        @Test
        void a_value_set_above_a_listed_default_replaces_it() {
            MockEnvironment env = new MockEnvironment();
            env.getPropertySources().addLast(new MapPropertySource("defaults", Map.of(
                    ServiceCategories.PROPERTY + "[0]", "PRINTING",
                    ServiceCategories.PROPERTY + "[1]", "TAILORING")));
            env.getPropertySources().addFirst(new MapPropertySource("override", Map.of(
                    ServiceCategories.PROPERTY, "REPAIRS")));

            assertThat(new ServiceCategories(env).enabled()).containsExactly(REPAIRS);
        }

        @Test
        void a_blank_setting_closes_every_category() {
            MockEnvironment env = new MockEnvironment().withProperty(ServiceCategories.PROPERTY, "");

            assertThat(new ServiceCategories(env).enabled()).isEmpty();
        }

        @Test
        void a_name_that_is_not_a_category_fails_loudly() {
            MockEnvironment env = new MockEnvironment()
                    .withProperty(ServiceCategories.PROPERTY, TYPO);

            assertThatThrownBy(() -> new ServiceCategories(env).enabled())
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining(TYPO)
                    .hasMessageContaining("PRINTING");
        }

        @Test
        void the_open_categories_are_served_in_taxonomy_order() {
            environment.setProperty(ServiceCategories.PROPERTY, "PHOTOGRAPHY,PRINTING");

            assertThat(service.openServiceCategories()).containsExactly(PRINTING, PHOTOGRAPHY);
        }

        /** application.yml as the service loads it, as the lowest-precedence source. */
        private MockEnvironment shippedConfiguration() throws Exception {
            List<PropertySource<?>> yaml = new YamlPropertySourceLoader()
                    .load("application", new ClassPathResource("application.yml"));
            MockEnvironment shipped = new MockEnvironment();
            yaml.forEach(source -> shipped.getPropertySources().addLast(source));
            return shipped;
        }
    }
}

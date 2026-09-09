package com.delivery.product.service;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import com.delivery.platform.storage.StorageService;
import com.delivery.product.api.dto.BannerDtos.BannerRequest;
import com.delivery.product.domain.Banner;
import com.delivery.product.domain.BannerRepository;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.BannerService.VerticalTakenException;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.CategoryNotFoundException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Editorial content: what the home screen promotes, and which chip stands for which vertical.
 *
 * <p>Everything here is platform-wide, which is what makes the mistakes expensive. A banner is on
 * every customer's home screen or it is on nobody's, and there is exactly one chip per vertical —
 * so a draft that publishes itself and a clash reported as a bare constraint violation are both
 * felt by the whole marketplace rather than by one shop.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("home-screen editorial")
class BannerEditorialRulesTest {

    private static final String EDITOR = "backoffice-sub";

    @Mock
    private BannerRepository banners;
    @Mock
    private CategoryRepository categories;
    @Mock
    private StoreRepository stores;
    @Mock
    private StorageService storage;

    private BannerService service;

    @BeforeEach
    void setUp() {
        service = new BannerService(banners, categories, stores, storage,
                Clock.fixed(Instant.parse("2026-09-09T09:00:00Z"), ZoneOffset.UTC));
        when(banners.save(any(Banner.class))).thenAnswer(call -> call.getArgument(0));
    }

    private static BannerRequest banner(boolean active) {
        return new BannerRequest("Ramadan offers", "All week", Banner.LinkKind.NONE, null,
                1, active);
    }

    @Nested
    @DisplayName("creating a banner")
    class Creating {

        /**
         * The field was accepted, validated and then thrown away: the constructor hardcoded active,
         * so a banner saved as a draft went out to every customer's home screen immediately and the
         * only remedy was for somebody to notice.
         */
        @Test
        void a_draft_does_not_go_live() {
            Banner created = service.create(banner(false));

            assertThat(created.isActive()).isFalse();
            assertThat(created.isLiveAt(Instant.parse("2026-09-09T09:00:01Z"))).isFalse();
        }

        @Test
        void one_created_as_live_runs_from_now() {
            Banner created = service.create(banner(true));

            assertThat(created.isActive()).isTrue();
            assertThat(created.isLiveAt(Instant.parse("2026-09-09T09:00:01Z"))).isTrue();
        }
    }

    @Nested
    @DisplayName("tagging a category with a vertical")
    class Verticals {

        private Category category(String name, Store.Vertical vertical) {
            Category category = new Category(name, null);
            category.setVertical(vertical);
            when(categories.findById(category.getId())).thenReturn(Optional.of(category));
            return category;
        }

        @Test
        void an_unclaimed_vertical_is_taken() {
            Category chip = category("Groceries", null);
            when(categories.findFirstByVertical(Store.Vertical.GROCERY))
                    .thenReturn(Optional.empty());

            assertThat(service.setVertical(chip.getId(), Store.Vertical.GROCERY).getVertical())
                    .isEqualTo(Store.Vertical.GROCERY);
        }

        /**
         * One chip per vertical is deliberate — two would render the strip twice — but the refusal
         * used to be the database's, a 409 saying a uniqueness rule had been violated. The editor
         * could not act on that; the name of the category holding the vertical is the whole fix.
         */
        @Test
        void a_vertical_another_category_holds_is_refused_by_name() {
            Category holder = category("Groceries", Store.Vertical.GROCERY);
            Category other = category("Corner shops", null);
            when(categories.findFirstByVertical(Store.Vertical.GROCERY))
                    .thenReturn(Optional.of(holder));

            assertThatThrownBy(() -> service.setVertical(other.getId(), Store.Vertical.GROCERY))
                    .isInstanceOf(VerticalTakenException.class)
                    .hasMessageContaining("Groceries");

            assertThat(other.getVertical()).isNull();
        }

        /** And says nothing a caller would have to go and look up. */
        @Test
        void the_refusal_never_names_the_constraint() {
            Category holder = category("Groceries", Store.Vertical.GROCERY);
            Category other = category("Corner shops", null);
            when(categories.findFirstByVertical(Store.Vertical.GROCERY))
                    .thenReturn(Optional.of(holder));

            assertThatThrownBy(() -> service.setVertical(other.getId(), Store.Vertical.GROCERY))
                    .hasMessageNotContainingAny("uq_category_vertical", "uniqueness", "constraint");
        }

        /** Re-saving the chip that already holds the vertical is a no-op, not a clash with itself. */
        @Test
        void re_tagging_the_holder_with_what_it_already_has_is_allowed() {
            Category holder = category("Groceries", Store.Vertical.GROCERY);
            when(categories.findFirstByVertical(Store.Vertical.GROCERY))
                    .thenReturn(Optional.of(holder));

            assertThatCode(() -> service.setVertical(holder.getId(), Store.Vertical.GROCERY))
                    .doesNotThrowAnyException();
        }

        @Test
        void clearing_a_vertical_needs_no_clash_check() {
            Category holder = category("Groceries", Store.Vertical.GROCERY);

            assertThat(service.setVertical(holder.getId(), null).getVertical()).isNull();
            verify(categories, never()).findFirstByVertical(any());
        }

        /** A path id that names nothing is a 404 here as everywhere else, not a rule violation. */
        @Test
        void a_category_that_does_not_exist_is_not_found() {
            UUID unknown = UUID.randomUUID();
            when(categories.findById(unknown)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.setVertical(unknown, Store.Vertical.GROCERY))
                    .isInstanceOf(CategoryNotFoundException.class)
                    .hasMessageContaining(unknown.toString());
        }
    }

    @Nested
    @DisplayName("asking for an upload URL")
    class Uploads {

        @Test
        void a_format_no_thumbnail_can_be_made_from_never_gets_a_url() {
            Banner target = service.create(banner(true));
            when(banners.findById(target.getId())).thenReturn(Optional.of(target));

            assertThatThrownBy(() ->
                    service.presignBanner(target.getId(), EDITOR, "image/webp"))
                    .isInstanceOf(CatalogRuleViolationException.class);

            verify(storage, never()).presignUpload(anyString(), any(), anyString(), anyString());
        }

        @Test
        void category_artwork_is_held_to_the_same_rule() {
            Category chip = new Category("Groceries", null);
            when(categories.findById(chip.getId())).thenReturn(Optional.of(chip));

            assertThatThrownBy(() ->
                    service.presignCategory(chip.getId(), EDITOR, "image/webp"))
                    .isInstanceOf(CatalogRuleViolationException.class);

            verify(storage, never()).presignUpload(anyString(), any(), anyString(), anyString());
        }
    }
}

package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
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
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;

import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

/**
 * The "People Also Ordered" rail.
 *
 * <p>Every test here is really about one thing: the rail must not claim to know something it does
 * not. A count on an item means that many delivered baskets genuinely held both products; an item
 * with no count is same-shelf fill and says so. The two must never be confused, and the product a
 * customer is already looking at must never appear on its own rail.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("cross-sell")
class CrossSellServiceTest {

    private static final UUID STORE = UUID.randomUUID();
    private static final UUID MEZZE = UUID.randomUUID();
    private static final UUID DRINKS = UUID.randomUUID();

    @Mock
    private DeliveredOrderLineRepository deliveredLines;
    @Mock
    private ProductRepository products;

    private CrossSellService service;
    private Product hummus;

    @BeforeEach
    void setUp() {
        service = new CrossSellService(deliveredLines, products, 2L);
        hummus = product("Hummus", MEZZE);

        // Nothing has ever been delivered and nothing else is on the shelf, unless a test says so.
        when(deliveredLines.findBoughtWith(any(), anyLong(), any())).thenReturn(List.of());
        when(products.findActiveInStoreByIds(any(), any(), any()))
                .thenReturn(new PageImpl<>(List.of()));
        when(products.findActiveInStore(any(), any(), any(), any()))
                .thenReturn(new PageImpl<>(List.of()));
    }

    private static Product product(String name, UUID categoryId) {
        return new Product("merchant-1", STORE, name, "A thing", new BigDecimal("9.50"), categoryId);
    }

    /** Says which products shared delivered baskets with the one being viewed, and how many. */
    private void boughtTogether(Product... withCounts) {
        List<Object[]> rows = new ArrayList<>();
        long count = 10;
        for (Product other : withCounts) {
            rows.add(new Object[]{other.getId(), count});
            count -= 1;
        }
        when(deliveredLines.findBoughtWith(eq(hummus.getId()), anyLong(), any())).thenReturn(rows);

        List<Product> catalogued = List.of(withCounts);
        when(products.findActiveInStoreByIds(eq(STORE), any(), any()))
                .thenAnswer(invocation -> {
                    Collection<UUID> wanted = invocation.getArgument(1);
                    return new PageImpl<>(catalogued.stream()
                            .filter(p -> wanted.contains(p.getId())).toList());
                });
    }

    /** Says what else the shop stocks, for the same-aisle fill to draw on. */
    private void onTheShelf(Product... shelf) {
        when(products.findActiveInStore(eq(STORE), any(), any(), any()))
                .thenReturn(new PageImpl<>(List.of(shelf)));
    }

    private List<String> railFor(Product product, int limit) {
        return service.boughtTogetherWith(product, limit).stream()
                .map(s -> s.product().getName()).toList();
    }

    @Nested
    @DisplayName("the product being viewed")
    class NeverItself {

        @Test
        void is_never_on_its_own_rail_when_the_rail_is_filled_from_the_shelf() {
            onTheShelf(hummus, product("Tabbouleh", MEZZE), product("Fattoush", MEZZE));

            assertThat(railFor(hummus, 5)).doesNotContain("Hummus");
        }

        /**
         * The co-occurrence query already excludes it in SQL. Asserted again here because the rail
         * has two sources and only one of them is that query — a rule enforced in one branch is a
         * rule the other branch can break.
         */
        @Test
        void is_never_on_its_own_rail_even_if_the_evidence_query_offers_it() {
            when(deliveredLines.findBoughtWith(eq(hummus.getId()), anyLong(), any()))
                    .thenReturn(List.<Object[]>of(new Object[]{hummus.getId(), 7L}));
            when(products.findActiveInStoreByIds(eq(STORE), any(), any()))
                    .thenReturn(new PageImpl<>(List.of(hummus)));

            assertThat(railFor(hummus, 5)).doesNotContain("Hummus");
        }

        @Test
        void is_not_counted_towards_the_requested_size_either() {
            Product tabbouleh = product("Tabbouleh", MEZZE);
            Product fattoush = product("Fattoush", MEZZE);
            onTheShelf(hummus, tabbouleh, fattoush);

            assertThat(railFor(hummus, 2)).containsExactlyInAnyOrder("Fattoush", "Tabbouleh");
        }
    }

    @Nested
    @DisplayName("with real delivered baskets to count")
    class WithEvidence {

        @Test
        void labels_a_counted_suggestion_as_bought_together_and_reports_the_real_count() {
            Product bread = product("Pita Bread", MEZZE);
            boughtTogether(bread);

            List<CrossSellService.Suggestion> rail = service.boughtTogetherWith(hummus, 5);

            assertThat(rail).first().satisfies(suggestion -> {
                assertThat(suggestion.product().getName()).isEqualTo("Pita Bread");
                assertThat(suggestion.basis()).isEqualTo(CrossSellService.Basis.BOUGHT_TOGETHER);
                assertThat(suggestion.ordersTogether()).isEqualTo(10L);
            });
        }

        @Test
        void puts_the_strongest_evidence_first() {
            Product bread = product("Pita Bread", MEZZE);
            Product olives = product("Olives", MEZZE);
            Product water = product("Water", DRINKS);
            boughtTogether(bread, olives, water);

            assertThat(railFor(hummus, 5))
                    .containsExactly("Pita Bread", "Olives", "Water");
        }

        /**
         * The projection remembers what was sold; the catalog decides what is on sale. Offering a
         * customer something the shop has withdrawn is worse than a shorter rail.
         */
        @Test
        void drops_a_product_that_has_since_been_archived() {
            Product bread = product("Pita Bread", MEZZE);
            Product discontinued = product("Discontinued Dip", MEZZE);
            boughtTogether(bread, discontinued);

            // The catalog re-read only knows about the bread — the other has been archived out of it.
            when(products.findActiveInStoreByIds(eq(STORE), any(), any()))
                    .thenReturn(new PageImpl<>(List.of(bread)));

            assertThat(railFor(hummus, 5)).containsExactly("Pita Bread");
        }

        /** Evidence leads; fill follows and stays labelled as fill. */
        @Test
        void tops_a_short_rail_up_from_the_shelf_without_promoting_the_fill() {
            Product bread = product("Pita Bread", MEZZE);
            boughtTogether(bread);
            onTheShelf(product("Tabbouleh", MEZZE), product("Fattoush", MEZZE));

            List<CrossSellService.Suggestion> rail = service.boughtTogetherWith(hummus, 3);

            assertThat(rail).hasSize(3);
            assertThat(rail.get(0).basis()).isEqualTo(CrossSellService.Basis.BOUGHT_TOGETHER);
            assertThat(rail.subList(1, 3)).allSatisfy(fill -> {
                assertThat(fill.basis()).isEqualTo(CrossSellService.Basis.SAME_AISLE);
                assertThat(fill.ordersTogether()).isNull();
            });
        }

        @Test
        void does_not_repeat_an_evidenced_product_as_fill() {
            Product bread = product("Pita Bread", MEZZE);
            boughtTogether(bread);
            onTheShelf(bread, product("Tabbouleh", MEZZE));

            assertThat(railFor(hummus, 5)).containsExactly("Pita Bread", "Tabbouleh");
        }
    }

    @Nested
    @DisplayName("with no delivered baskets yet")
    class WithoutEvidence {

        /**
         * The state every shop starts in, and the reason the label is on each item rather than on
         * the endpoint. {@code delivered_order_lines} fills from order.delivered and cannot be
         * backfilled, so until baskets accumulate this is the whole of the rail.
         */
        @Test
        void every_suggestion_is_labelled_same_aisle_with_no_count() {
            onTheShelf(product("Tabbouleh", MEZZE), product("Fattoush", MEZZE));

            List<CrossSellService.Suggestion> rail = service.boughtTogetherWith(hummus, 5);

            assertThat(rail).isNotEmpty();
            assertThat(rail).allSatisfy(suggestion -> {
                assertThat(suggestion.basis()).isEqualTo(CrossSellService.Basis.SAME_AISLE);
                assertThat(suggestion.ordersTogether())
                        .as("no popularity was measured, so none may be reported")
                        .isNull();
            });
        }

        /** An empty rail is a correct answer for a shop with one product. Nothing is invented. */
        @Test
        void a_shop_with_nothing_else_on_the_shelf_gets_an_empty_rail() {
            onTheShelf(hummus);

            assertThat(service.boughtTogetherWith(hummus, 5)).isEmpty();
        }
    }

    @Nested
    @DisplayName("the size of the rail")
    class Size {

        @Test
        void never_exceeds_what_was_asked_for() {
            onTheShelf(product("A", MEZZE), product("B", MEZZE), product("C", MEZZE),
                    product("D", MEZZE), product("E", MEZZE));

            assertThat(service.boughtTogetherWith(hummus, 2)).hasSize(2);
        }

        @Test
        void is_empty_when_nothing_was_asked_for() {
            onTheShelf(product("Tabbouleh", MEZZE));

            assertThat(service.boughtTogetherWith(hummus, 0)).isEmpty();
        }

        @Test
        void asks_the_evidence_query_for_the_floor_it_was_configured_with() {
            CrossSellService strict = new CrossSellService(deliveredLines, products, 5L);

            strict.boughtTogetherWith(hummus, 5);

            org.mockito.Mockito.verify(deliveredLines)
                    .findBoughtWith(eq(hummus.getId()), eq(5L), any(PageRequest.class));
        }
    }
}

package com.delivery.product.service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The rules a shop's own sections keep.
 *
 * <p>Every case here is one an end-to-end run caught in the first cut of this service, and each
 * failed silently rather than loudly: a parent quietly discarded, two sections sharing a position,
 * a shelf pinned open by goods that were withdrawn months ago. None of them throws on its own.
 */
class StoreCategoryRulesTest {

    private static final UUID STORE = UUID.randomUUID();

    private CategoryRepository categories;
    private ProductRepository products;
    private StoreCategoryService sections;

    @BeforeEach
    void setUp() {
        categories = mock(CategoryRepository.class);
        products = mock(ProductRepository.class);
        sections = new StoreCategoryService(categories, products);
        when(categories.save(any(Category.class))).thenAnswer(i -> i.getArgument(0));
    }

    private Category section(String name, short position) {
        return new Category(STORE, name, null, position);
    }

    @Test
    @DisplayName("a section created under a platform category keeps that parent")
    void createKeepsTheParent() {
        UUID platformParent = UUID.randomUUID();
        // A platform row: no owning store, which is the only kind a section may hang under.
        when(categories.findById(platformParent)).thenReturn(Optional.of(new Category("Food", null)));
        when(categories.existsByStoreIdAndNameIgnoreCase(eq(STORE), anyString())).thenReturn(false);
        when(categories.countByStoreId(STORE)).thenReturn(0L);

        Category created = sections.create(STORE, "Breads", platformParent);

        // The first cut validated the parent and then dropped it on the floor.
        assertThat(created.getParentId()).isEqualTo(platformParent);
    }

    @Test
    @DisplayName("a section cannot hang under another shop's section")
    void createRefusesAStoreOwnedParent() {
        UUID foreign = UUID.randomUUID();
        when(categories.findById(foreign)).thenReturn(Optional.of(section("Someone else's", (short) 0)));

        assertThatThrownBy(() -> sections.create(STORE, "Breads", foreign))
                .isInstanceOf(CatalogRuleViolationException.class);
    }

    @Test
    @DisplayName("reorder refuses a list that names one section twice")
    void reorderRefusesDuplicates() {
        Category a = section("A", (short) 0);
        Category b = section("B", (short) 1);
        Category c = section("C", (short) 2);
        when(categories.findByStoreIdOrderByPositionAscNameAsc(STORE)).thenReturn(List.of(a, b, c));

        // Same length as the store's section list, so a size-only check let this through and left
        // A moved twice while C silently kept its old position.
        assertThatThrownBy(() -> sections.reorder(STORE,
                List.of(a.getId(), a.getId(), b.getId())))
                .isInstanceOf(CatalogRuleViolationException.class);

        assertThat(a.getPosition()).isZero();
        assertThat(c.getPosition()).isEqualTo((short) 2);
    }

    @Test
    @DisplayName("reorder applies a complete, distinct list")
    void reorderAppliesAValidList() {
        Category a = section("A", (short) 0);
        Category b = section("B", (short) 1);
        when(categories.findByStoreIdOrderByPositionAscNameAsc(STORE)).thenReturn(List.of(a, b));

        sections.reorder(STORE, List.of(b.getId(), a.getId()));

        assertThat(b.getPosition()).isZero();
        assertThat(a.getPosition()).isEqualTo((short) 1);
    }

    @Test
    @DisplayName("rename refuses a name another section already holds in a different case")
    void renameKeepsTheSameRuleAsCreate() {
        // Renaming SNACKS onto the name DRINKS already holds. The section's own name has to differ
        // from the target, or this would be the recasing case below rather than a collision.
        Category snacks = section("Snacks", (short) 1);
        when(categories.findById(snacks.getId())).thenReturn(Optional.of(snacks));
        when(categories.existsByStoreIdAndNameIgnoreCase(STORE, "drinks")).thenReturn(true);

        assertThatThrownBy(() -> sections.rename(STORE, snacks.getId(), "drinks"))
                .isInstanceOf(CatalogRuleViolationException.class);
    }

    @Test
    @DisplayName("a section can be renamed to a new case of its own name")
    void renameAllowsRecasingItself() {
        Category drinks = section("drinks", (short) 0);
        when(categories.findById(drinks.getId())).thenReturn(Optional.of(drinks));
        // The store does hold that name — itself. Comparing against its own name is what keeps
        // "fix the capitalisation" from being refused as a duplicate of itself.
        when(categories.existsByStoreIdAndNameIgnoreCase(STORE, "Drinks")).thenReturn(true);

        sections.rename(STORE, drinks.getId(), "Drinks");

        assertThat(drinks.getName()).isEqualTo("Drinks");
    }

    @Test
    @DisplayName("archived goods neither count on a section nor keep it from being deleted")
    void archivedProductsDoNotPinASectionOpen() {
        Category empty = section("Seasonal", (short) 0);
        when(categories.findById(empty.getId())).thenReturn(Optional.of(empty));
        // One archived product, nothing live: products are archived and never deleted, so an
        // unfiltered count would pin this shelf open for the rest of the shop's life.
        when(products.countByCategoryIdAndStatusNot(empty.getId(), Product.Status.ARCHIVED))
                .thenReturn(0L);

        assertThat(sections.productCount(empty.getId())).isZero();
        sections.delete(STORE, empty.getId());
    }

    @Test
    @DisplayName("a section holding live goods still refuses deletion")
    void liveProductsStillBlockDeletion() {
        Category stocked = section("Bakery", (short) 0);
        when(categories.findById(stocked.getId())).thenReturn(Optional.of(stocked));
        when(products.countByCategoryIdAndStatusNot(stocked.getId(), Product.Status.ARCHIVED))
                .thenReturn(3L);

        assertThatThrownBy(() -> sections.delete(STORE, stocked.getId()))
                .isInstanceOf(CatalogRuleViolationException.class)
                .hasMessageContaining("3");
    }
}

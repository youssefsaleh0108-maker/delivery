package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

import org.hibernate.annotations.BatchSize;

/**
 * A question asked about a product before it goes in the basket — "Choose Size", "Extras".
 *
 * <p>The selection rule is a range rather than a pair of booleans. {@code min=1, max=1} is "pick
 * exactly one", {@code min=0, max=3} is "up to three toppings", {@code min=2, max=2} is "choose two
 * sides". A required/multi-select pair of flags cannot express the third case at all.
 */
@Entity
@Table(name = "product_option_groups")
public class ProductOptionGroup {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /**
     * Writable, and set at construction.
     *
     * <p>Not a read-only mirror of a parent's join column: nothing owns a collection of these on
     * {@code Product}, they are saved through their own repository. Mapping it read-only left
     * product_id null on insert and every save failed the not-null constraint.
     */
    @Column(name = "product_id", nullable = false, updatable = false)
    private UUID productId;

    @Column(name = "name", nullable = false, length = 120)
    private String name;

    @Column(name = "min_select", nullable = false)
    private short minSelect;

    @Column(name = "max_select", nullable = false)
    private short maxSelect;

    @Column(name = "position", nullable = false)
    private short position;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @OneToMany(cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @JoinColumn(name = "group_id", nullable = false)
    @OrderBy("position ASC")
    @BatchSize(size = 64)
    private List<ProductOption> options = new ArrayList<>();

    protected ProductOptionGroup() {
        // for JPA
    }

    public ProductOptionGroup(UUID productId, String name, int minSelect, int maxSelect,
                              int position) {
        if (maxSelect < 1 || minSelect < 0 || maxSelect < minSelect) {
            throw new IllegalArgumentException(
                    "A group must allow at least one choice, and max cannot be below min");
        }
        this.id = UUID.randomUUID();
        this.productId = productId;
        this.name = name;
        this.minSelect = (short) minSelect;
        this.maxSelect = (short) maxSelect;
        this.position = (short) position;
    }

    /** Whether the customer must answer before the product can be added. */
    public boolean isRequired() {
        return minSelect >= 1;
    }

    public boolean isSingleChoice() {
        return maxSelect == 1;
    }

    /**
     * Validates a set of chosen options against this group's rule.
     *
     * @throws IllegalArgumentException with a message written for a customer, not a developer —
     *         it is surfaced directly by the API.
     */
    public void validateSelection(List<ProductOption> chosen) {
        for (ProductOption option : chosen) {
            if (options.stream().noneMatch(o -> o.getId().equals(option.getId()))) {
                throw new IllegalArgumentException(
                        "\"" + option.getName() + "\" is not an option under " + name);
            }
            if (!option.isAvailable()) {
                throw new IllegalArgumentException("\"" + option.getName() + "\" is sold out");
            }
        }
        // The group name is quoted and never grammatically absorbed into the sentence.
        //
        // Merchants name groups imperatively as often as nominally — "Choose Size" is as natural as
        // "Size", and the Toters menus this was modelled on use the imperative form. A template
        // like "Choose an option under " + name then reads "Choose an option under Choose Size".
        // Quoting turns the name into a label the sentence refers to rather than a phrase it
        // continues, which works for either style.
        if (chosen.size() < minSelect) {
            throw new IllegalArgumentException(minSelect == 1
                    ? "\"" + name + "\" needs a selection"
                    : "\"" + name + "\" needs at least " + minSelect + " selections");
        }
        if (chosen.size() > maxSelect) {
            throw new IllegalArgumentException(
                    "\"" + name + "\" allows at most " + maxSelect
                            + " selection" + (maxSelect == 1 ? "" : "s"));
        }
    }

    public void replaceOptions(List<ProductOption> replacement) {
        this.options.clear();
        this.options.addAll(replacement);
    }

    /** The cheapest way to satisfy this group, used to show a product's "from" price. */
    public BigDecimal minimumDelta() {
        if (!isRequired()) {
            return BigDecimal.ZERO;
        }
        return options.stream()
                .filter(ProductOption::isAvailable)
                .map(ProductOption::getPriceDelta)
                .min(BigDecimal::compareTo)
                .orElse(BigDecimal.ZERO);
    }

    public UUID getId() {
        return id;
    }

    public UUID getProductId() {
        return productId;
    }

    public String getName() {
        return name;
    }

    public short getMinSelect() {
        return minSelect;
    }

    public short getMaxSelect() {
        return maxSelect;
    }

    public short getPosition() {
        return position;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public List<ProductOption> getOptions() {
        return Collections.unmodifiableList(options);
    }
}

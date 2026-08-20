package com.delivery.whatsapp.domain;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

/**
 * One thing the merchant put in a draft.
 *
 * <p>A product from their own catalog, never free text. The price, the shop's minimum and the
 * settlement split all come from the catalog, so a line naming something we cannot price is a line
 * nobody can charge for.
 */
@Entity
@Table(name = "wa_draft_lines")
public class DraftLine {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "product_id", nullable = false, updatable = false)
    private UUID productId;

    /**
     * The name and price as they were when the merchant added the line.
     *
     * <p>Snapshotted so the draft still reads correctly if the product is renamed or delisted while
     * the merchant is mid-conversation. Not what the customer will be charged — the catalog prices
     * the real order at the moment it is placed.
     *
     * <p>{@code unitPrice} is the price <em>with</em> the chosen options, as the catalog priced it,
     * so the estimate the merchant reads back matches what will actually be charged.
     */
    @Column(name = "product_name", nullable = false, length = 200)
    private String productName;

    @Column(name = "unit_price", nullable = false, precision = 12, scale = 2)
    private BigDecimal unitPrice;

    @Column(name = "qty", nullable = false)
    private int qty;

    /** Eager for the same reason the draft's lines are: nothing ever reads one without the other. */
    @OneToMany(cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @JoinColumn(name = "line_id", nullable = false)
    private List<DraftLineOption> options = new ArrayList<>();

    protected DraftLine() {
        // for JPA
    }

    DraftLine(UUID productId, String productName, BigDecimal unitPrice, int qty,
              List<DraftLineOption> options) {
        this.id = UUID.randomUUID();
        this.productId = productId;
        this.productName = productName;
        this.unitPrice = unitPrice;
        this.qty = qty;
        this.options = options == null ? new ArrayList<>() : new ArrayList<>(options);
    }

    void addQty(int more) {
        this.qty += more;
    }

    public BigDecimal lineTotal() {
        return unitPrice.multiply(BigDecimal.valueOf(qty));
    }

    /**
     * Whether this line is the same configuration as another.
     *
     * <p>Product <em>and</em> selection, not product alone. With options the same product legitimately
     * appears twice in one basket — a large pizza and a small one are two lines, not quantity two —
     * and merging them would silently change what the customer gets. The same rule Order Manager
     * applies to a basket from the app.
     */
    public boolean matches(UUID productId, List<UUID> optionIds) {
        return this.productId.equals(productId) && chosenOptionIds().equals(normalise(optionIds));
    }

    /** Sorted and de-duplicated, so picking the same two extras in a different order is one line. */
    public static List<UUID> normalise(List<UUID> optionIds) {
        return optionIds == null ? List.of() : optionIds.stream().distinct().sorted().toList();
    }

    public List<UUID> chosenOptionIds() {
        return normalise(options.stream().map(DraftLineOption::getOptionId).toList());
    }

    /** "Choose Size: Large, Extras: extra cheese" — what the merchant reads back to the customer. */
    public String optionsSummary() {
        return options.stream()
                .map(option -> option.getGroupName() + ": " + option.getOptionName())
                .collect(Collectors.joining(", "));
    }

    public UUID getId() {
        return id;
    }

    public UUID getProductId() {
        return productId;
    }

    public String getProductName() {
        return productName;
    }

    public BigDecimal getUnitPrice() {
        return unitPrice;
    }

    public int getQty() {
        return qty;
    }

    public List<DraftLineOption> getOptions() {
        return options;
    }
}

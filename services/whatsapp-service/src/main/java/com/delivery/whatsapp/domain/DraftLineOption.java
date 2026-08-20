package com.delivery.whatsapp.domain;

import java.math.BigDecimal;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * One option chosen on a draft line — "Large", "extra cheese", "no onions".
 *
 * <p>The id is the only authoritative field: it goes to Order Manager, which prices the selection
 * from the catalog exactly as it does for an app order. The name and delta beside it are a snapshot,
 * so the merchant reads the draft back to the customer as words rather than as UUIDs.
 */
@Entity
@Table(name = "wa_draft_line_options")
public class DraftLineOption {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "option_id", nullable = false, updatable = false)
    private UUID optionId;

    @Column(name = "group_name", nullable = false, length = 120)
    private String groupName;

    @Column(name = "option_name", nullable = false, length = 120)
    private String optionName;

    @Column(name = "price_delta", nullable = false, precision = 12, scale = 2)
    private BigDecimal priceDelta = BigDecimal.ZERO;

    protected DraftLineOption() {
        // for JPA
    }

    /** Public because the snapshot is assembled in the service, where the catalog answer arrives. */
    public DraftLineOption(UUID optionId, String groupName, String optionName,
                           BigDecimal priceDelta) {
        this.id = UUID.randomUUID();
        this.optionId = optionId;
        this.groupName = groupName;
        this.optionName = optionName;
        this.priceDelta = priceDelta == null ? BigDecimal.ZERO : priceDelta;
    }

    public UUID getId() {
        return id;
    }

    public UUID getOptionId() {
        return optionId;
    }

    public String getGroupName() {
        return groupName;
    }

    public String getOptionName() {
        return optionName;
    }

    public BigDecimal getPriceDelta() {
        return priceDelta;
    }
}

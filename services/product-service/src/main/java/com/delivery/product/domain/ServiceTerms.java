package com.delivery.product.domain;

import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * What a service offer promises, beside the {@link Product} it describes (V34).
 *
 * <p>A service offer is a product: its USD price, photos with thumbnails, publish rule and option
 * groups such as "Paper type" all come from there, and the catalogue prices it as it prices any basket
 * line. What a product cannot say is how the work is sold and handed over. That is this row: one per
 * offer, keyed by the product's id, and present exactly when the product sits in a
 * {@link Store.Vertical#SERVICES} shop ({@code CatalogService} holds that rule in both directions).
 *
 * <p>Saved through its own repository rather than mapped as an association on {@code Product}. The
 * product side of a one-to-one cannot be lazy without bytecode enhancement, so every goods shelf would
 * pay one query per card for a row goods never have. The lists that do need terms read a whole page of
 * them in one query instead.
 *
 * <p>Every rule is checked before anything is assigned, so a refused revision leaves the terms as they
 * were. The messages are written for the provider, because {@code CatalogService} returns them as the
 * detail of its 422.
 */
@Entity
@Table(name = "service_terms")
public class ServiceTerms {

    /**
     * The longest turnaround an offer may promise: thirty days.
     *
     * <p>A customer's estimated completion is the accept time plus the maximum (owner default 7), and a
     * print shop, tailor, repairer or photo studio quoting more than a month has almost certainly typed
     * days into a box that asks for hours. Policy rather than schema, so the CHECK in V34 holds only
     * what no turnaround can ever be, and moving this needs no migration.
     */
    public static final int MAX_TURNAROUND_HOURS = 720;

    /** The largest pack: a run of 100,000 flyers is a real print job, and more is a slipped zero. */
    public static final int MAX_UNIT_SIZE = 100_000;

    public static final int MAX_UNIT_LABEL_LENGTH = 40;

    public static final int MAX_INSTRUCTIONS_PROMPT_LENGTH = 160;

    public enum PricingType {
        /** One price for one pack of {@link #getUnitSize()} units: "500 cards, $15.00". */
        FIXED,
        /**
         * One price for one unit, such as a square metre or a page: "$8.00 per sqm". Always a pack of
         * one, because an order line counts packs and prices each at the product's price.
         */
        PER_UNIT,
        /** A starting price that the offer's required options add to: "From $15.00". */
        FROM
    }

    /** How the customer gets the finished work. */
    public enum Fulfilment {
        /** Collected at the provider's shop. */
        PICKUP,
        /** Carried to the customer by YouDrop, on the shop's delivery terms. */
        DELIVERY,
        /** Either, chosen by the customer when ordering. */
        BOTH;

        public boolean includesDelivery() {
            return this != PICKUP;
        }

        public boolean includesPickup() {
            return this != DELIVERY;
        }
    }

    /** Whether the customer sends a file with the order: a design to print, a photo to enlarge. */
    public enum AttachmentPolicy {
        NONE, OPTIONAL, REQUIRED
    }

    @Id
    @Column(name = "product_id", nullable = false, updatable = false)
    private UUID productId;

    @Enumerated(EnumType.STRING)
    @Column(name = "pricing_type", nullable = false, length = 16)
    private PricingType pricingType;

    /** What one unit is called: "cards", "sqm". Absent only for a single unit sold at a fixed price. */
    @Column(name = "unit_label", length = 40)
    private String unitLabel;

    @Column(name = "unit_size", nullable = false)
    private int unitSize = 1;

    @Column(name = "turnaround_min_hours", nullable = false)
    private int turnaroundMinHours;

    @Column(name = "turnaround_max_hours", nullable = false)
    private int turnaroundMaxHours;

    @Enumerated(EnumType.STRING)
    @Column(name = "fulfilment_modes", nullable = false, length = 16)
    private Fulfilment fulfilmentModes;

    @Enumerated(EnumType.STRING)
    @Column(name = "attachment_policy", nullable = false, length = 16)
    private AttachmentPolicy attachmentPolicy = AttachmentPolicy.NONE;

    @Column(name = "instructions_prompt", length = 160)
    private String instructionsPrompt;

    protected ServiceTerms() {
        // for JPA
    }

    /**
     * Terms for a new offer. See {@link #revise} for what each value may be.
     *
     * @throws IllegalArgumentException with a message for the provider, when a rule is broken
     */
    public ServiceTerms(UUID productId, PricingType pricingType, String unitLabel, Integer unitSize,
                        Integer turnaroundMinHours, Integer turnaroundMaxHours,
                        Fulfilment fulfilmentModes, AttachmentPolicy attachmentPolicy,
                        String instructionsPrompt) {
        if (productId == null) {
            throw new IllegalArgumentException("Service terms belong to an offer");
        }
        this.productId = productId;
        revise(pricingType, unitLabel, unitSize, turnaroundMinHours, turnaroundMaxHours,
                fulfilmentModes, attachmentPolicy, instructionsPrompt);
    }

    /**
     * Replaces every term at once, as the offer form sends them.
     *
     * <ul>
     *   <li>A pricing type and a fulfilment are required; the file policy defaults to NONE and the
     *       pack to a single unit.
     *   <li>The turnaround is a range of whole hours: from zero, up to {@link #MAX_TURNAROUND_HOURS},
     *       at least one hour at the slow end, and never slower at the fast end than at the slow end.
     *   <li>A pack larger than one unit must say what the units are, or the stepper would read "500".
     *   <li>A per-unit price is a pack of one, and must say what the unit is, or it would read "per".
     * </ul>
     *
     * <p>Blank text is stored as absent, as a form clearing a field means it.
     *
     * @throws IllegalArgumentException with a message for the provider, when a rule is broken; nothing
     *         has been changed when it is thrown
     */
    public void revise(PricingType pricingType, String unitLabel, Integer unitSize,
                       Integer turnaroundMinHours, Integer turnaroundMaxHours,
                       Fulfilment fulfilmentModes, AttachmentPolicy attachmentPolicy,
                       String instructionsPrompt) {
        String label = blankToNull(unitLabel);
        String prompt = blankToNull(instructionsPrompt);
        int size = unitSize == null ? 1 : unitSize;

        if (pricingType == null) {
            throw new IllegalArgumentException(
                    "Choose how the offer is priced: a fixed price, a price per unit, or a starting price");
        }
        if (fulfilmentModes == null) {
            throw new IllegalArgumentException(
                    "Choose how customers get the work: pickup, delivery, or both");
        }
        requireTurnaround(turnaroundMinHours, turnaroundMaxHours);
        if (size < 1 || size > MAX_UNIT_SIZE) {
            throw new IllegalArgumentException(
                    "Units per step must be between 1 and " + MAX_UNIT_SIZE);
        }
        if (label != null && label.length() > MAX_UNIT_LABEL_LENGTH) {
            throw new IllegalArgumentException(
                    "A unit can be at most " + MAX_UNIT_LABEL_LENGTH + " characters");
        }
        if (pricingType == PricingType.PER_UNIT && size != 1) {
            throw new IllegalArgumentException("A price per unit is the price of one unit, so it cannot "
                    + "come in steps of " + size + ". Sell a pack at a fixed price instead.");
        }
        if (pricingType == PricingType.PER_UNIT && label == null) {
            throw new IllegalArgumentException("A price per unit needs its unit, such as sqm or page");
        }
        if (size > 1 && label == null) {
            throw new IllegalArgumentException(
                    "A pack of " + size + " needs its unit, such as cards or pages");
        }
        if (prompt != null && prompt.length() > MAX_INSTRUCTIONS_PROMPT_LENGTH) {
            throw new IllegalArgumentException("The question for customers can be at most "
                    + MAX_INSTRUCTIONS_PROMPT_LENGTH + " characters");
        }

        this.pricingType = pricingType;
        this.unitLabel = label;
        this.unitSize = size;
        this.turnaroundMinHours = turnaroundMinHours;
        this.turnaroundMaxHours = turnaroundMaxHours;
        this.fulfilmentModes = fulfilmentModes;
        this.attachmentPolicy = attachmentPolicy == null ? AttachmentPolicy.NONE : attachmentPolicy;
        this.instructionsPrompt = prompt;
    }

    private static void requireTurnaround(Integer min, Integer max) {
        if (min == null || max == null) {
            throw new IllegalArgumentException(
                    "Say how long the work takes: the shortest and the longest turnaround, in hours");
        }
        if (min < 0) {
            throw new IllegalArgumentException("A turnaround cannot be shorter than zero hours");
        }
        if (max < 1) {
            throw new IllegalArgumentException("A turnaround must allow at least one hour");
        }
        if (max > MAX_TURNAROUND_HOURS) {
            throw new IllegalArgumentException(
                    "A turnaround can be at most " + MAX_TURNAROUND_HOURS + " hours (30 days)");
        }
        if (max < min) {
            throw new IllegalArgumentException("The longest turnaround (" + max
                    + " hours) cannot be shorter than the shortest (" + min + " hours)");
        }
    }

    private static String blankToNull(String value) {
        return (value == null || value.isBlank()) ? null : value.trim();
    }

    /** Whether a customer can have this offer delivered, which needs the shop to reach them. */
    public boolean offersDelivery() {
        return fulfilmentModes.includesDelivery();
    }

    public UUID getProductId() {
        return productId;
    }

    public PricingType getPricingType() {
        return pricingType;
    }

    public String getUnitLabel() {
        return unitLabel;
    }

    public int getUnitSize() {
        return unitSize;
    }

    public int getTurnaroundMinHours() {
        return turnaroundMinHours;
    }

    public int getTurnaroundMaxHours() {
        return turnaroundMaxHours;
    }

    public Fulfilment getFulfilmentModes() {
        return fulfilmentModes;
    }

    public AttachmentPolicy getAttachmentPolicy() {
        return attachmentPolicy;
    }

    public String getInstructionsPrompt() {
        return instructionsPrompt;
    }
}

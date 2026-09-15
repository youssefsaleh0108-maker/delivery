package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import org.hibernate.annotations.Generated;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.generator.EventType;
import org.hibernate.type.SqlTypes;

@Entity
@Table(name = "products")
public class Product {

    public enum Status {
        /** Created but not on the customer-facing catalog. Where a product starts. */
        DRAFT,
        /** Visible to customers and orderable. */
        ACTIVE,
        /**
         * A service offer its provider has taken off sale for now (V35).
         *
         * <p>Hidden from customers and refused at placement exactly like a draft: every customer read
         * asks for ACTIVE, and order-manager refuses anything else. Unlike an archived product it is
         * kept whole, with its photos, options and terms, so resuming it puts it back as it was.
         *
         * <p>Only service offers are paused ({@code CatalogService}). Installed goods merchant apps
         * read a status they do not know as DRAFT, and archiving is already how those apps take a
         * product off sale.
         */
        PAUSED,
        /**
         * Withdrawn from sale. Products are archived, never deleted, because past orders reference
         * them and an order history that cannot name what was bought is worthless.
         *
         * <p>Also where back office's take-down leaves a service offer ({@link Product#takeDown}), with
         * a hold its provider cannot lift. Every reader of products already takes ARCHIVED as off sale.
         */
        ARCHIVED
    }

    /** The longest reason back office may give for taking an offer down, as V36's columns hold it. */
    public static final int MAX_TAKEDOWN_REASON_LENGTH = 500;

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** The owning merchant's Keycloak {@code sub}. Never accepted from a request body. */
    @Column(name = "merchant_id", nullable = false, length = 64, updatable = false)
    private String merchantId;

    /**
     * The store this product sits in.
     *
     * <p>Redundant with {@code merchantId} only for as long as a merchant runs a single store, and
     * that is exactly why both exist: {@code merchantId} answers "who may edit this", {@code storeId}
     * answers "where does a customer find it". Collapsing them would make a second store
     * unrepresentable.
     */
    @Column(name = "store_id", nullable = false)
    private UUID storeId;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "description", columnDefinition = "text")
    private String description;

    @Column(name = "price", nullable = false, precision = 12, scale = 2)
    private BigDecimal price;

    @Column(name = "category_id")
    private UUID categoryId;

    /**
     * The merchant's own code for this item, unique within the store when set.
     *
     * <p>Optional: most catalogues arrive without one, and the till can fall back to search.
     */
    @Column(name = "sku", length = 64)
    private String sku;

    /** Scanned at the till. Not unique — the same EAN legitimately appears in two stores. */
    @Column(name = "barcode", length = 32)
    private String barcode;

    /**
     * Whether inventory-service currently believes this item can be sold.
     *
     * <p>A read-only projection of {@code inventory.level_changed}, never set from a request: the
     * stock ledger is owned by inventory-service and this column only exists so the storefront can
     * filter without a cross-service call on its hot path. Products the merchant has not opted into
     * tracking have no ledger row and stay {@code true} forever.
     */
    @Column(name = "in_stock", nullable = false)
    private boolean inStock = true;

    /** Object keys in the {@code product-images} bucket, in display order. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "image_refs", nullable = false, columnDefinition = "jsonb")
    private List<String> imageRefs = new ArrayList<>();

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.DRAFT;

    /**
     * Picked by the back office for the customer gift hub's featured care bundles (V31).
     *
     * <p>Moved only by {@link #featureAsGift} and {@link #unfeatureAsGift}, which only the back
     * office can reach: the hub is the platform's window, and a merchant who could feature their
     * own products would turn it into ad space. {@link #giftFeaturedAt} orders the hub and says
     * when the pick was made.
     */
    @Column(name = "gift_featured", nullable = false)
    private boolean giftFeatured;

    @Column(name = "gift_featured_at")
    private Instant giftFeaturedAt;

    /**
     * When back office took this offer down (V36), or null while it is not taken down.
     *
     * <p>A taken-down offer is ARCHIVED, so every customer read and order-manager refuse it as they
     * refuse anything not on sale. This column adds the hold. {@link #publish}, {@link #resume} and
     * {@link #pause} are refused while it is set, so the provider cannot put the offer back on sale, and
     * only {@link #restore} lifts it. It is moved only by {@link #takeDown} and {@link #restore}, which
     * only back office can reach ({@code OfferModerationService}).
     */
    @Column(name = "taken_down_at")
    private Instant takenDownAt;

    /** Why back office took the offer down, which its provider reads. Set exactly while taken down. */
    @Column(name = "takedown_reason", length = MAX_TAKEDOWN_REASON_LENGTH)
    private String takedownReason;

    /** What the offer was when it was taken down, which {@link #restore} returns it to. */
    @Enumerated(EnumType.STRING)
    @Column(name = "status_before_takedown", length = 16)
    private Status statusBeforeTakedown;

    /**
     * Moved on by every save, which writes only where the row still holds the version it read (V36).
     *
     * <p>Every save judges the product's rules on what it read, and most saves read without a lock: a
     * provider's edit, publish, pause, resume, archive or photo change, and back office's gift-hub switch.
     * Two saves from one read would each apply their rules to a product the other had already changed. A
     * publish after the last photo was removed would put a blank card on sale, a gift-hub pick after an
     * archive would send the product back to the hub when it is next published, and an archive read just
     * before a take-down would come back from the restore paused. The second save now matches no row and is
     * refused, the API answers 409 PRODUCT_CHANGED, and its caller reloads.
     *
     * <p>So a save writes every column from what it read, which the version guarantees is still the row as
     * it stands. Writing only the changed columns protected nothing more, and it mixed two saves' reads into
     * a row neither of them made.
     *
     * <p>Null until the product is first saved, which is how Spring Data tells a new product from one to
     * merge.
     */
    @Version
    @Column(name = "version", nullable = false)
    private Long version;

    /**
     * Written by the column default, and read straight back.
     *
     * <p>{@code @Generated} is what makes the 201 on a create honest. Without it the entity is
     * serialised holding the null it was constructed with — the column is not insertable, so
     * nothing in Java ever knows what the database wrote — and every freshly created product came
     * back with {@code createdAt: null}. With it, Hibernate re-reads the row after the insert.
     */
    @Generated(event = EventType.INSERT)
    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    /** Maintained by a database trigger, so it cannot drift when a writer forgets to set it. */
    @Generated(event = {EventType.INSERT, EventType.UPDATE})
    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    protected Product() {
        // for JPA
    }

    public Product(String merchantId, UUID storeId, String name, String description,
                   BigDecimal price, UUID categoryId) {
        this.id = UUID.randomUUID();
        this.merchantId = merchantId;
        this.storeId = storeId;
        this.name = name;
        this.description = description;
        this.price = price;
        this.categoryId = categoryId;
        this.status = Status.DRAFT;
        this.imageRefs = new ArrayList<>();
    }

    /**
     * The single ownership predicate for this aggregate.
     *
     * <p>Section 3: ownership is enforced in service code against the {@code sub} claim, not by
     * Keycloak. Holding the MERCHANT role says you may edit <em>some</em> products; this says which.
     */
    public boolean isOwnedBy(String userId) {
        return this.merchantId.equals(userId);
    }

    /**
     * Rewrites what the product says. Allowed while the offer is taken down: fixing what back office
     * objected to is exactly what its provider should be doing, and an edit puts nothing on sale.
     */
    public void update(String name, String description, BigDecimal price, UUID categoryId,
                       String sku, String barcode) {
        this.name = name;
        this.description = description;
        this.price = price;
        this.categoryId = categoryId;
        assignCodes(sku, barcode);
    }

    /**
     * Sets the merchant's own item codes.
     *
     * <p>Blank is how a form says "cleared", so it is stored as absent: the partial unique index on
     * {@code (store_id, sku)} would otherwise treat several empty strings as a collision.
     */
    public void assignCodes(String sku, String barcode) {
        this.sku = blankToNull(sku);
        this.barcode = blankToNull(barcode);
    }

    /**
     * Applies inventory-service's view of whether this item is sellable.
     *
     * <p>Separate from {@link #update} because it arrives on the event bus, not from the merchant,
     * and must never be writable through the product API.
     */
    public void applyStockProjection(boolean inStock) {
        this.inStock = inStock;
    }

    private static String blankToNull(String value) {
        return (value == null || value.isBlank()) ? null : value.trim();
    }

    /** Puts the product on sale. Refused while back office holds it taken down. */
    public void publish() {
        refuseWhileTakenDown("published");
        if (this.imageRefs.isEmpty()) {
            throw new IllegalStateException(
                    "A product needs at least one image before it can be published");
        }
        this.status = Status.ACTIVE;
    }

    /**
     * Withdraws the product from sale — and from the gift hub, for good: a product brought back
     * later is picked for the hub again on purpose, not returned to it by accident.
     *
     * <p>Allowed while the offer is taken down, when it is the provider withdrawing it for good. The
     * hold stays, and restoring it then brings back an archived offer rather than a paused one. An archive
     * that read the offer before it was taken down is refused as stale ({@link #version}), so a take-down
     * never keeps, as the status to restore, one its provider had already withdrawn.
     */
    public void archive() {
        this.status = Status.ARCHIVED;
        unfeatureAsGift();
        if (isTakenDown()) {
            this.statusBeforeTakedown = Status.ARCHIVED;
        }
    }

    /**
     * Takes a live offer off sale for now, keeping everything about it.
     *
     * <p>Only from ACTIVE: a draft was never on sale, and an archived product comes back by being
     * published on purpose, not by a resume.
     */
    public void pause() {
        refuseWhileTakenDown("paused");
        if (this.status != Status.ACTIVE) {
            throw new IllegalStateException("Only a live offer can be paused; this one is " + status);
        }
        this.status = Status.PAUSED;
    }

    /**
     * Puts a paused offer back on sale, under the rule {@link #publish} applies: a listing with no
     * photo would be a blank card, and a photo removed while the offer was paused is exactly that case.
     */
    public void resume() {
        refuseWhileTakenDown("resumed");
        if (this.status != Status.PAUSED) {
            throw new IllegalStateException("Only a paused offer can be resumed; this one is " + status);
        }
        if (this.imageRefs.isEmpty()) {
            throw new IllegalStateException(
                    "An offer needs at least one photo before it can be resumed");
        }
        this.status = Status.ACTIVE;
    }

    /**
     * Back office takes this offer down: off sale at once, and held there until back office restores it.
     *
     * <p>It is left ARCHIVED and off the gift hub, as {@link #archive} leaves a product, so nothing that
     * reads products has to learn a new status. It remembers what it was, for {@link #restore}. The
     * reason is stored trimmed.
     *
     * <p>Only service offers are taken down, which {@code OfferModerationService} decides from the shop.
     *
     * @throws IllegalStateException    when the offer is already taken down. A second take-down would
     *                                  otherwise replace the reason its provider was given and what a
     *                                  restore returns the offer to.
     * @throws IllegalArgumentException when the reason is blank or longer than
     *                                  {@value #MAX_TAKEDOWN_REASON_LENGTH} characters
     */
    public void takeDown(String reason, Instant at) {
        if (isTakenDown()) {
            throw new IllegalStateException("This offer is already taken down");
        }
        String given = reason == null ? "" : reason.trim();
        if (given.isEmpty()) {
            throw new IllegalArgumentException("Say why the offer is being taken down");
        }
        if (given.length() > MAX_TAKEDOWN_REASON_LENGTH) {
            throw new IllegalArgumentException(
                    "A reason is at most " + MAX_TAKEDOWN_REASON_LENGTH + " characters");
        }
        this.statusBeforeTakedown = this.status;
        this.status = Status.ARCHIVED;
        unfeatureAsGift();
        this.takenDownAt = at;
        this.takedownReason = given;
    }

    /**
     * Back office lifts the hold, and the offer returns to what it was when it was taken down, except
     * that an offer that was on sale comes back PAUSED.
     *
     * <p>Back office never puts an offer in front of customers. Its provider resumes it, and resuming
     * runs the publishing rules again, which a photo removed or a pin cleared during the hold may now
     * fail. A draft stays a draft, a paused offer stays paused, and an offer archived before or during
     * the hold stays archived.
     *
     * @throws IllegalStateException when the offer is not taken down
     */
    public void restore() {
        if (!isTakenDown()) {
            throw new IllegalStateException("This offer is not taken down, so there is nothing to restore");
        }
        this.status = this.statusBeforeTakedown == Status.ACTIVE ? Status.PAUSED : this.statusBeforeTakedown;
        this.takenDownAt = null;
        this.takedownReason = null;
        this.statusBeforeTakedown = null;
    }

    /** Whether back office holds this offer taken down. */
    public boolean isTakenDown() {
        return takenDownAt != null;
    }

    /**
     * The provider's refusal while the hold is on, with back office's reason: the one thing they can act
     * on is what back office objected to.
     */
    private void refuseWhileTakenDown(String act) {
        if (isTakenDown()) {
            throw new IllegalStateException("YouDrop has taken this offer down, so it cannot be " + act
                    + " until YouDrop restores it. The reason given: " + takedownReason);
        }
    }

    /**
     * Puts this product on the gift hub.
     *
     * <p>Only a live product: a draft or archived one on the hub would be a card nobody can buy.
     * Featuring what is already featured keeps the original moment, so saving the switch twice
     * does not reshuffle the hub.
     */
    public void featureAsGift(Instant now) {
        if (this.status != Status.ACTIVE) {
            throw new IllegalStateException(
                    "Only a live product can be featured on the gift hub; this one is " + status);
        }
        if (!this.giftFeatured) {
            this.giftFeatured = true;
            this.giftFeaturedAt = now;
        }
    }

    /** Takes this product off the gift hub. Harmless on one that was never on it. */
    public void unfeatureAsGift() {
        this.giftFeatured = false;
        this.giftFeaturedAt = null;
    }

    public boolean isGiftFeatured() {
        return giftFeatured;
    }

    public Instant getGiftFeaturedAt() {
        return giftFeaturedAt;
    }

    public Instant getTakenDownAt() {
        return takenDownAt;
    }

    public String getTakedownReason() {
        return takedownReason;
    }

    public Status getStatusBeforeTakedown() {
        return statusBeforeTakedown;
    }

    public void addImage(String objectKey) {
        if (!this.imageRefs.contains(objectKey)) {
            this.imageRefs.add(objectKey);
        }
    }

    public boolean removeImage(String objectKey) {
        boolean removed = this.imageRefs.remove(objectKey);
        // A published product with no images would render as a blank card in the catalog.
        if (removed && this.imageRefs.isEmpty() && this.status == Status.ACTIVE) {
            this.status = Status.DRAFT;
        }
        return removed;
    }

    public UUID getId() {
        return id;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public String getName() {
        return name;
    }

    public String getDescription() {
        return description;
    }

    public BigDecimal getPrice() {
        return price;
    }

    public UUID getCategoryId() {
        return categoryId;
    }

    public String getSku() {
        return sku;
    }

    public String getBarcode() {
        return barcode;
    }

    public boolean isInStock() {
        return inStock;
    }

    public List<String> getImageRefs() {
        return Collections.unmodifiableList(imageRefs);
    }

    public Status getStatus() {
        return status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}

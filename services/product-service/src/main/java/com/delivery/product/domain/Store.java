package com.delivery.product.domain;

import java.math.BigDecimal;
import java.time.DateTimeException;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import org.hibernate.annotations.BatchSize;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * A shop. The unit a customer browses, favourites and orders from.
 *
 * <p>The catalog was product-first before this existed: a product carried a merchant's Keycloak
 * {@code sub} and nothing a storefront could render. Everything a marketplace home screen shows —
 * a name, a rating, a delivery fee, an ETA, whether the place is even open — lives here.
 */
@Entity
@Table(name = "stores")
public class Store {

    /**
     * How long before closing time a store starts warning customers.
     *
     * <p>The number is a product decision, not an implementation detail: it is the window in which
     * a customer can still order but should be told they are cutting it fine.
     */
    private static final Duration CLOSING_SOON_WINDOW = Duration.ofMinutes(30);

    public enum Vertical {
        RESTAURANT, COFFEE, GROCERY, CONVENIENCE, PHARMACY, ELECTRONICS, FLOWERS_GIFTS
    }

    public enum Status {
        /** Created but not listed. Where a store starts. */
        DRAFT,
        /** Listed and orderable, subject to opening hours. */
        ACTIVE,
        /** Delisted by an administrator. Distinct from closed, which is a function of the clock. */
        SUSPENDED
    }

    /**
     * What the customer sees on the card.
     *
     * <p>Deliberately derived rather than stored. A stored "open" flag is wrong the moment the clock
     * passes closing time and nothing runs a job, and the failure is silent — the shop keeps taking
     * orders it cannot fulfil.
     */
    public enum Availability {
        OPEN, BUSY, CLOSING_SOON, CLOSED
    }

    /**
     * What the lights are doing right now — the Lebanese storefront's first question.
     *
     * <p>Merchant-declared, like busy, and honestly defaulted: UNKNOWN draws no chip at all,
     * because a shop that never said should not wear a green badge it did not earn.
     */
    public enum PowerStatus {
        UNKNOWN, MAINS, GENERATOR, DARK
    }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** The owning merchant's Keycloak {@code sub}. Never accepted from a request body. */
    @Column(name = "merchant_id", nullable = false, length = 64, updatable = false)
    private String merchantId;

    @Column(name = "name", nullable = false, length = 160)
    private String name;

    /** Derived from the name once, at creation, and never again. See {@link #slugify}. */
    @Column(name = "slug", nullable = false, length = 180, updatable = false)
    private String slug;

    @Enumerated(EnumType.STRING)
    @Column(name = "vertical", nullable = false, length = 24)
    private Vertical vertical;

    @Column(name = "tagline", length = 240)
    private String tagline;

    @Column(name = "description", columnDefinition = "text")
    private String description;

    @Column(name = "logo_ref", length = 512)
    private String logoRef;

    @Column(name = "cover_ref", length = 512)
    private String coverRef;

    /** Cuisine and category chips. Drives the storefront's tag filter. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "tags", nullable = false, columnDefinition = "jsonb")
    private List<String> tags = new ArrayList<>();

    /** Null until the store has been rated at all — which is not the same as a rating of zero. */
    @Column(name = "rating", precision = 2, scale = 1)
    private BigDecimal rating;

    @Column(name = "rating_count", nullable = false)
    private int ratingCount;

    @Column(name = "delivery_fee", nullable = false, precision = 12, scale = 2)
    private BigDecimal deliveryFee = BigDecimal.ZERO;

    @Column(name = "min_order", nullable = false, precision = 12, scale = 2)
    private BigDecimal minOrder = BigDecimal.ZERO;

    @Column(name = "eta_min_minutes", nullable = false)
    private int etaMinMinutes = 20;

    @Column(name = "eta_max_minutes", nullable = false)
    private int etaMaxMinutes = 40;

    @Column(name = "timezone", nullable = false, length = 64)
    private String timezone = "UTC";

    @Column(name = "address", length = 400)
    private String address;

    /**
     * The map pin, or null when the merchant has not dropped one.
     *
     * <p>Stored as two loose columns rather than a mapped PostGIS type so this service needs no
     * spatial Hibernate dialect: V20 derives an indexed {@code geography} column from these two,
     * generated by the database, which keeps the pin and the geometry from ever disagreeing. The
     * pair is read and written through {@link GeoPoint}, which is where the range and Null Island
     * rules live.
     *
     * <p>Nullable, and it must stay that way. Coordinates are a map affordance, not a pricing
     * input — delivery is still priced by the areas V18 introduced, for the reasons set out there —
     * so a shop with no pin has to keep trading exactly as it does today. It simply does not appear
     * in a "near me" list.
     */
    @Column(name = "latitude", precision = 9, scale = 6)
    private BigDecimal latitude;

    @Column(name = "longitude", precision = 9, scale = 6)
    private BigDecimal longitude;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private Status status = Status.DRAFT;

    /** Self-expiring "the kitchen is behind" flag. Null, or in the past, means not busy. */
    @Column(name = "busy_until")
    private Instant busyUntil;

    @Enumerated(EnumType.STRING)
    @Column(name = "power_status", nullable = false, length = 16)
    private PowerStatus powerStatus = PowerStatus.UNKNOWN;

    /** The one-liner under the chip: "Ovens fully hot", "Cold storage active". */
    @Column(name = "power_note", length = 160)
    private String powerNote;

    /** When the merchant last said — what "auto-updated" honestly means on the storefront. */
    @Column(name = "power_updated_at")
    private Instant powerUpdatedAt;

    /** District identity for the hyperlocal browse: Mar Mikhael, Hamra, Badaro... */
    @Column(name = "neighborhood", length = 80)
    private String neighborhood;

    /** The dekkane trust badge. Backoffice-set, never merchant-writable. */
    @Column(name = "verified_local", nullable = false)
    private boolean verifiedLocal;

    /**
     * How far from the pin this shop delivers, in metres. Null keeps the old behaviour — the
     * platform's zones alone decide. Only meaningful with a pin; the service refuses to set it
     * without one, because a circle needs a centre.
     */
    @Column(name = "delivery_radius_metres")
    private Integer deliveryRadiusMetres;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false, insertable = false, updatable = false)
    private Instant updatedAt;

    /**
     * Opening hours.
     *
     * <p>{@code @BatchSize} is what keeps the home screen off an N+1: rendering a page of stores
     * needs every store's hours to derive availability, and without batching that is one query per
     * card. With it, Hibernate fetches the whole page's hours in a single {@code IN} query.
     */
    @OneToMany(cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    @JoinColumn(name = "store_id", nullable = false)
    @BatchSize(size = 64)
    private List<StoreHours> hours = new ArrayList<>();

    protected Store() {
        // for JPA
    }

    public Store(String merchantId, String name, Vertical vertical) {
        this.id = UUID.randomUUID();
        this.merchantId = merchantId;
        this.name = name;
        this.slug = slugify(name) + "-" + this.id.toString().substring(0, 8);
        this.vertical = vertical;
        this.status = Status.DRAFT;
    }

    /**
     * Builds the URL key.
     *
     * <p>A short id fragment is appended by the constructor rather than relying on the name alone:
     * two merchants may legitimately open shops with the same name, and a unique constraint that
     * rejects the second one is a bad answer to a normal situation.
     */
    static String slugify(String name) {
        String cleaned = name.toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("(^-+)|(-+$)", "");
        if (cleaned.isEmpty()) {
            cleaned = "store";
        }
        return cleaned.length() > 160 ? cleaned.substring(0, 160) : cleaned;
    }

    // ---------------------------------------------------------------- availability

    /**
     * What this store's card should say right now.
     *
     * <p>Order of the checks is the product rule, and it is not arbitrary. Closed wins over busy,
     * because a shut shop being "behind on orders" is a nonsense state to render. Busy wins over
     * closing soon, because a customer needs the more urgent operational warning first.
     */
    public Availability availabilityAt(Instant now) {
        if (status != Status.ACTIVE) {
            return Availability.CLOSED;
        }

        LocalTime closesAt = closingTimeAt(now);
        if (closesAt == null) {
            return Availability.CLOSED;
        }

        if (busyUntil != null && busyUntil.isAfter(now)) {
            return Availability.BUSY;
        }

        Duration remaining = Duration.between(now.atZone(zone()).toLocalTime(), closesAt);
        return remaining.compareTo(CLOSING_SOON_WINDOW) <= 0
                ? Availability.CLOSING_SOON
                : Availability.OPEN;
    }

    /**
     * When the current opening window ends, or null if none is open right now.
     *
     * <p>Also the "is it open at all" test that {@link #availabilityAt} builds on — the two questions
     * share one walk over the hours so they can never disagree about which window applies.
     *
     * <p>Overlapping windows resolve to the latest closing time. Two windows that touch are one
     * stretch of open time as far as a customer is concerned.
     */
    public LocalTime closingTimeAt(Instant now) {
        ZonedDateTime local = now.atZone(zone());
        LocalTime timeOfDay = local.toLocalTime();
        int day = local.getDayOfWeek().getValue();

        LocalTime closesAt = null;
        for (StoreHours window : hours) {
            if (window.covers(day, timeOfDay)
                    && (closesAt == null || window.getClosesAt().isAfter(closesAt))) {
                closesAt = window.getClosesAt();
            }
        }
        return closesAt;
    }

    /**
     * Resolves the store's zone, falling back to UTC.
     *
     * <p>A bad zone string must not be able to take the storefront down. It is a data-entry field,
     * and an unrecognised value should degrade one store's clock, not throw out of a list query
     * rendering fifty of them.
     */
    private ZoneId zone() {
        try {
            return ZoneId.of(timezone);
        } catch (DateTimeException e) {
            // Covers both an unparseable id and a well-formed one with no rules loaded
            // (ZoneRulesException extends DateTimeException).
            return ZoneId.of("UTC");
        }
    }

    public boolean isOrderable(Instant now) {
        return availabilityAt(now) != Availability.CLOSED;
    }

    // ---------------------------------------------------------------- behaviour

    public boolean isOwnedBy(String candidateMerchantId) {
        return merchantId.equals(candidateMerchantId);
    }

    public void publish() {
        if (hours.isEmpty()) {
            // Publishing without hours would list a store that can never be open, because
            // availability is derived entirely from them.
            throw new IllegalStateException("A store needs opening hours before it can be listed");
        }
        this.status = Status.ACTIVE;
    }

    public void suspend() {
        this.status = Status.SUSPENDED;
    }

    /**
     * Flags the store as behind on orders until a given moment.
     *
     * <p>Takes the instant rather than a duration so the entity never reads the clock itself. Every
     * other time-dependent answer here is derived from a caller-supplied {@code now}, and one method
     * quietly consulting the system clock would make the whole class untestable at a chosen time.
     */
    public void markBusyUntil(Instant until) {
        this.busyUntil = until;
    }

    public void clearBusy() {
        this.busyUntil = null;
    }

    /**
     * Swaps the whole week's hours.
     *
     * <p>Replace rather than merge: opening hours are edited as a set ("here is our new week"), and
     * a merge would need every caller to work out which windows to delete, which is exactly the
     * bookkeeping {@code orphanRemoval} already does correctly.
     */
    public void replaceHours(List<StoreHours> replacement) {
        this.hours.clear();
        this.hours.addAll(replacement);
    }

    public void updateProfile(String name, String tagline, String description, Vertical vertical,
                              List<String> tags, String timezone, String address) {
        // Note the slug is not touched. Renaming a shop must not break a shared link.
        this.name = name;
        this.tagline = tagline;
        this.description = description;
        this.vertical = vertical;
        this.tags = tags == null ? new ArrayList<>() : new ArrayList<>(tags);
        if (timezone != null && !timezone.isBlank()) {
            this.timezone = timezone;
        }
        this.address = address;
    }

    public void updateCommercials(BigDecimal deliveryFee, BigDecimal minOrder,
                                  int etaMinMinutes, int etaMaxMinutes) {
        if (etaMaxMinutes < etaMinMinutes) {
            throw new IllegalArgumentException("The ETA range ends before it begins");
        }
        this.deliveryFee = deliveryFee;
        this.minOrder = minOrder;
        this.etaMinMinutes = etaMinMinutes;
        this.etaMaxMinutes = etaMaxMinutes;
    }

    /**
     * Writes the denormalised rating back from the reviews.
     *
     * <p>Null average means no reviews yet, and is stored as null rather than zero — the storefront
     * has to be able to tell "nobody has rated this" from "everybody rated it badly".
     */
    public void applyRating(BigDecimal average, int count) {
        this.rating = average == null ? null : average.setScale(1, java.math.RoundingMode.HALF_UP);
        this.ratingCount = count;
    }

    public void setImagery(String logoRef, String coverRef) {
        this.logoRef = logoRef;
        this.coverRef = coverRef;
    }

    /**
     * Drops the map pin.
     *
     * <p>Deliberately NOT part of {@link #updateProfile}. The profile form is saved every time a
     * merchant edits their tagline, and a nullable coordinate pair on that request would silently
     * clear the pin on every save made by a client that does not know the fields exist — including
     * the Merchant Portal as it stands today. Moving the shop is its own decision, so it gets its
     * own operation and its own endpoint.
     */
    public void pinAt(GeoPoint point) {
        this.latitude = point.latitude();
        this.longitude = point.longitude();
    }

    /** Removes the pin. The store keeps its address text; it just stops appearing on the map. */
    public void clearPin() {
        this.latitude = null;
        this.longitude = null;
    }

    /** The pin as a value object, or null when this store has never been placed on a map. */
    public GeoPoint location() {
        return GeoPoint.ofNullable(latitude, longitude);
    }

    // ---------------------------------------------------------------- accessors

    public UUID getId() {
        return id;
    }

    public String getMerchantId() {
        return merchantId;
    }

    public String getName() {
        return name;
    }

    public String getSlug() {
        return slug;
    }

    public Vertical getVertical() {
        return vertical;
    }

    public String getTagline() {
        return tagline;
    }

    public String getDescription() {
        return description;
    }

    public String getLogoRef() {
        return logoRef;
    }

    public String getCoverRef() {
        return coverRef;
    }

    public List<String> getTags() {
        return Collections.unmodifiableList(tags);
    }

    public BigDecimal getRating() {
        return rating;
    }

    public int getRatingCount() {
        return ratingCount;
    }

    public BigDecimal getDeliveryFee() {
        return deliveryFee;
    }

    public BigDecimal getMinOrder() {
        return minOrder;
    }

    public int getEtaMinMinutes() {
        return etaMinMinutes;
    }

    public int getEtaMaxMinutes() {
        return etaMaxMinutes;
    }

    public String getTimezone() {
        return timezone;
    }

    public String getAddress() {
        return address;
    }

    public PowerStatus getPowerStatus() {
        return powerStatus;
    }

    public String getPowerNote() {
        return powerNote;
    }

    public Instant getPowerUpdatedAt() {
        return powerUpdatedAt;
    }

    /** The merchant's declaration, stamped so the storefront can say how fresh it is. */
    public void declarePower(PowerStatus status, String note) {
        this.powerStatus = status == null ? PowerStatus.UNKNOWN : status;
        this.powerNote = note;
        this.powerUpdatedAt = Instant.now();
    }

    public String getNeighborhood() {
        return neighborhood;
    }

    public void setNeighborhood(String neighborhood) {
        this.neighborhood = neighborhood;
    }

    public boolean isVerifiedLocal() {
        return verifiedLocal;
    }

    public Integer getDeliveryRadiusMetres() {
        return deliveryRadiusMetres;
    }

    public void setDeliveryRadiusMetres(Integer metres) {
        this.deliveryRadiusMetres = metres;
    }

    public BigDecimal getLatitude() {
        return latitude;
    }

    public BigDecimal getLongitude() {
        return longitude;
    }

    public Status getStatus() {
        return status;
    }

    public Instant getBusyUntil() {
        return busyUntil;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public List<StoreHours> getHours() {
        return Collections.unmodifiableList(hours);
    }
}

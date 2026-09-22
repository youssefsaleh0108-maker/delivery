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
import org.hibernate.annotations.Generated;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.generator.EventType;
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
        RESTAURANT, COFFEE, GROCERY, CONVENIENCE, PHARMACY, ELECTRONICS, FLOWERS_GIFTS,

        /**
         * A shop that makes something to order instead of selling stock off a shelf: a print shop, a
         * tailor, a repairer, a photo studio. It carries a {@link ServiceCategory}, and no other
         * vertical does.
         *
         * <p>Left off every goods surface unless a read asks for it by name: the storefront and its
         * search, "near me", the district chips, the catalogue, the Home strip, banners and the gift
         * hub. The reason is on the phones: an installed app reads an unknown vertical as RESTAURANT,
         * so a print shop that reached the Home storefront would be drawn as a restaurant.
         *
         * <p>A store never moves into or out of it ({@link Store#updateProfile}). A goods shop and a
         * service shop are listed, ordered from and fulfilled differently, so a move would strand
         * whatever was built for the other one. The same rule stops an old merchant app, which reads
         * SERVICES as RESTAURANT, from rewriting a provider's shop on a profile save.
         */
        SERVICES
    }

    /**
     * What a {@link Vertical#SERVICES} shop does.
     *
     * <p>The whole taxonomy lives here, including categories that are not offered yet. Which ones are
     * open is configuration ({@code ServiceCategories}), so opening or closing one needs no migration
     * and orphans no shop.
     */
    public enum ServiceCategory {
        PRINTING,
        /** Tailoring and alterations. */
        TAILORING,
        REPAIRS,
        PHOTOGRAPHY,
        CLEANING,
        BEAUTY,
        TUTORING
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

    /**
     * What a service shop does, and null for every other shop. V33's CHECKs hold the pair together in
     * both directions, and so does this class: the constructor refuses a mismatch, and
     * {@link #changeServiceCategory} only re-files a service shop.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "service_category", length = 24)
    private ServiceCategory serviceCategory;

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

    /**
     * The calendar this shop's opening hours are in.
     *
     * <p>Not a default anybody chose for a shop: {@link StoreService#open} sets the platform's own
     * zone ({@code delivery.platform.zone}, {@code Asia/Beirut}) on every shop it opens, and a
     * merchant may set another. What is left below is the last resort for a row that names no zone
     * at all — an older shop, a seed, a hand-written INSERT — and it stays UTC deliberately: an
     * existing row's hours were entered against whatever it says, so reinterpreting them here would
     * move every one of those shops' opening times by the offset.
     */
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
     * When the shop first listed — what "New on YouDrop" means. Stamped by the first
     * {@link #publish}, never moved by a later one: a shop suspended and listed again has not just
     * joined. Null for a shop that has never listed. V32 backfilled it from {@code created_at} for
     * shops already past DRAFT, which errs towards "not new" — see the migration.
     */
    @Column(name = "published_at")
    private Instant publishedAt;

    /**
     * How far from the pin this shop delivers, in metres. Null keeps the old behaviour — the
     * platform's zones alone decide. Only meaningful with a pin; the service refuses to set it
     * without one, because a circle needs a centre.
     */
    @Column(name = "delivery_radius_metres")
    private Integer deliveryRadiusMetres;

    /**
     * How many tables this shop has QR codes for (V42), zero when it has none.
     *
     * <p>A property of the shop and not of whichever device printed the sheet: the codes are
     * generated from it, so a merchant who reprints table 7 from the portal next month gets the
     * card the phone printed today, byte for byte.
     *
     * <p>Lowering it does not invalidate anything already on a table — a printed code is a URL to
     * the page, not to this service — it only stops the shop printing new cards for tables it has
     * said it no longer has.
     */
    @Column(name = "table_count", nullable = false)
    private short tableCount;

    /**
     * Written by the column default, and read straight back — see {@link Product#getCreatedAt}.
     * Without {@code @Generated} a store serialised in the same transaction it was created in
     * carries the null it was constructed with, because the column is not insertable.
     */
    @Generated(event = EventType.INSERT)
    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    /** Maintained by a database trigger, so it cannot drift when a writer forgets to set it. */
    @Generated(event = {EventType.INSERT, EventType.UPDATE})
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

    /** A goods shop. A service shop needs its category: see the constructor below. */
    public Store(String merchantId, String name, Vertical vertical) {
        this(merchantId, name, vertical, null);
    }

    /**
     * A shop, with what it does when it is a service shop.
     *
     * @throws IllegalArgumentException when the vertical and the category disagree: a service shop
     *         with no category, or a goods shop with one. V33 refuses both; refusing here first turns
     *         a constraint name into a sentence the merchant can act on.
     */
    public Store(String merchantId, String name, Vertical vertical, ServiceCategory serviceCategory) {
        if (vertical == Vertical.SERVICES && serviceCategory == null) {
            throw new IllegalArgumentException("A services shop needs a service category");
        }
        if (vertical != Vertical.SERVICES && serviceCategory != null) {
            throw new IllegalArgumentException("Only a services shop has a service category");
        }
        this.id = UUID.randomUUID();
        this.merchantId = merchantId;
        this.name = name;
        this.slug = slugify(name) + "-" + this.id.toString().substring(0, 8);
        this.vertical = vertical;
        this.serviceCategory = serviceCategory;
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
     *
     * <p>Public because the fallback is the interesting part and there must be exactly one of it.
     * The public shop page prints this shop's week in this shop's calendar, so it needs the same
     * {@link ZoneId} the availability answers above were computed in — a second
     * {@code ZoneId.of(getTimezone())} somewhere else would be a second copy of the rule, and the
     * two would disagree about a bad value on the one page a stranger reads.
     */
    public ZoneId zone() {
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

    /**
     * Whether an order placed now could still arrive before the shop shuts: it is taking orders,
     * and the slow end of its delivery estimate fits inside the opening window it is in.
     *
     * <p>What the gift hub's "Same-day Deliverable" means. Derived from the clock on every read,
     * like {@link #availabilityAt}, and never stored: a flag that was true in the morning is a lie
     * by the evening, and the promise is made to somebody paying from abroad for a family's dinner.
     */
    public boolean deliversBeforeClosing(Instant now) {
        if (!isOrderable(now)) {
            return false;
        }
        LocalTime closesAt = closingTimeAt(now);
        if (closesAt == null) {
            return false;
        }
        long minutesLeft = Duration.between(now.atZone(zone()).toLocalTime(), closesAt).toMinutes();
        if (minutesLeft < 0) {
            // A window running past midnight closes earlier on the clock face than it is now.
            minutesLeft += Duration.ofDays(1).toMinutes();
        }
        return minutesLeft >= etaMaxMinutes;
    }

    // ---------------------------------------------------------------- behaviour

    public boolean isOwnedBy(String candidateMerchantId) {
        return merchantId.equals(candidateMerchantId);
    }

    /**
     * What a shop still has to have before it may be listed, or null when it is ready.
     *
     * <p>Asked as a question as well as enforced as a rule, so the merchant's Publish button can say
     * what is missing <em>before</em> it is pressed instead of turning a press into an error. One
     * method answers both; a button and a refusal that computed the rule separately would eventually
     * disagree.
     *
     * <p>Order is the order a merchant fixes them in: hours first, because a shop with neither is
     * being set up rather than being corrected, and a list of two problems is harder to act on than
     * the first one.
     */
    public NotListable whyNotListable() {
        if (hours.isEmpty()) {
            // Listing without hours would show a store that can never be open, because availability
            // is derived entirely from them.
            return NotListable.NO_HOURS;
        }
        if (location() == null) {
            return NotListable.NO_PIN;
        }
        return null;
    }

    /** @see #whyNotListable() */
    public boolean isListable() {
        return whyNotListable() == null;
    }

    /**
     * Lists the store, stamping {@link #getPublishedAt} the first time.
     *
     * <p>Takes the instant rather than reading the clock, for the reason {@link #markBusyUntil}
     * gives.
     *
     * <p>Refuses a shop that is not ready — see {@link #whyNotListable()}. Only the transition is
     * guarded: a shop that is ACTIVE already stays exactly as it is, pin or no pin, because
     * unlisting the shops that went live before this rule existed would take real traders off the
     * storefront to fix a data problem they never caused.
     *
     * @throws NotListableException naming the one thing that is missing
     */
    public void publish(Instant at) {
        NotListable blocker = whyNotListable();
        if (blocker != null) {
            throw new NotListableException(blocker);
        }
        this.status = Status.ACTIVE;
        if (publishedAt == null) {
            publishedAt = at;
        }
    }

    /**
     * Why a shop may not be listed yet.
     *
     * <p>Each carries the {@code code} a client branches on. A code rather than only a sentence
     * because the merchant app has to send the merchant somewhere — to the week's hours, or to the
     * map picker — and matching on English prose to decide which is not something that survives
     * translation.
     */
    public enum NotListable {

        NO_HOURS("STORE_HOURS_REQUIRED",
                "This shop has no opening hours yet, so it could never be open. Set the week's hours "
                        + "before listing it."),

        /**
         * The gap this rule was written for. Without a pin the shop cannot be found by distance, has
         * no delivery-area circle, cannot have its delivery radius enforced and cannot be ranked in
         * a customer's "near you" — it is listed and unreachable by every feature that asks where it
         * is.
         */
        NO_PIN("STORE_PIN_REQUIRED",
                "This shop has no location on the map yet. Drop its pin before listing it, or "
                        + "customers nearby will never find it.");

        private final String code;
        private final String message;

        NotListable(String code, String message) {
            this.code = code;
            this.message = message;
        }

        public String code() {
            return code;
        }

        public String message() {
            return message;
        }
    }

    /** A refused {@link #publish(Instant)}, with the {@code code} the client branches on. */
    public static class NotListableException extends IllegalStateException {

        private final NotListable reason;

        public NotListableException(NotListable reason) {
            super(reason.message());
            this.reason = reason;
        }

        public NotListable reason() {
            return reason;
        }

        public String getCode() {
            return reason.code();
        }
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

    /**
     * Saves the profile form's fields.
     *
     * <p>The vertical may move between goods verticals — a café that turns out to be a bakery — but
     * never into or out of {@link Vertical#SERVICES}; see there for why. The move is refused before
     * anything is written, so a refused save leaves the shop exactly as it was.
     *
     * @throws IllegalStateException when the save would move the shop into or out of SERVICES
     */
    public void updateProfile(String name, String tagline, String description, Vertical vertical,
                              List<String> tags, String timezone, String address) {
        if (isServices() != (vertical == Vertical.SERVICES)) {
            throw new IllegalStateException(isServices()
                    ? "A services shop cannot become a goods shop. Open a separate shop to sell goods."
                    : "A goods shop cannot become a services shop. Open a separate shop to offer "
                            + "services.");
        }
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

    /**
     * Sets the calendar this shop's opening hours are read in.
     *
     * <p>Its own method rather than a field on the profile form's save, because the two have
     * different owners: {@link StoreService} puts the platform's zone on a shop it opens, and the
     * merchant may then choose another. Blank is ignored for the reason {@link #updateProfile}
     * ignores it — a client that does not know the field exists must not be able to clear it.
     */
    public void useTimezone(String timezone) {
        if (timezone != null && !timezone.isBlank()) {
            this.timezone = timezone;
        }
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

    /** Whether this is a service shop: {@link Vertical#SERVICES}, with a {@link ServiceCategory}. */
    public boolean isServices() {
        return vertical == Vertical.SERVICES;
    }

    /** What a service shop does; null for a goods shop. */
    public ServiceCategory getServiceCategory() {
        return serviceCategory;
    }

    /**
     * Re-files a service shop under another category — a print shop that turned out to be mostly a
     * photo studio. The shop stays a service shop; a goods shop has no category to change.
     *
     * <p>Whether the category is open is not this class's to know: {@code StoreService} checks that
     * first, because it reads configuration.
     *
     * @throws IllegalStateException    on a goods shop
     * @throws IllegalArgumentException for null, because a service shop always has a category
     */
    public void changeServiceCategory(ServiceCategory category) {
        if (!isServices()) {
            throw new IllegalStateException("Only a services shop has a service category");
        }
        if (category == null) {
            throw new IllegalArgumentException("A services shop needs a service category");
        }
        this.serviceCategory = category;
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

    /**
     * The merchant's declaration, stamped so the storefront can say how fresh it is.
     *
     * <p>Takes the instant, like {@link #markBusyUntil}. It used to read {@code Instant.now()}, which
     * left "is this declaration still current" impossible to check at a chosen time.
     */
    public void declarePower(PowerStatus status, String note, Instant at) {
        this.powerStatus = status == null ? PowerStatus.UNKNOWN : status;
        this.powerNote = note;
        this.powerUpdatedAt = at;
    }

    /**
     * Whether the merchant declared what the lights are doing at or after {@code since} — recent
     * enough to be presented as happening now. A shop that never declared has nothing current to
     * say, and neither does a declaration with no time on it.
     */
    public boolean powerDeclaredSince(Instant since) {
        return powerStatus != PowerStatus.UNKNOWN
                && powerUpdatedAt != null
                && !powerUpdatedAt.isBefore(since);
    }

    public String getNeighborhood() {
        return neighborhood;
    }

    /**
     * Declares the shop's district, or clears it.
     *
     * <p>Trimmed, and blank stored as null. The district list is the distinct values of this column
     * and every filter on it is an exact match, so " Hamra" and "Hamra" would otherwise be two
     * districts in the list and two different answers to one question.
     */
    public void setNeighborhood(String neighborhood) {
        this.neighborhood = neighborhood == null || neighborhood.isBlank()
                ? null
                : neighborhood.trim();
    }

    public boolean isVerifiedLocal() {
        return verifiedLocal;
    }

    /**
     * Grants or withdraws the dekkane trust badge.
     *
     * <p>Only ever called on Backoffice's behalf, and deliberately nowhere near
     * {@link #updateProfile}: a badge the shop could award itself would certify nothing. V23 made the
     * column not merchant-writable and, until this existed, nothing could write it at all — so the
     * badge the customer app draws for it could never appear.
     */
    public void setVerifiedLocal(boolean verified) {
        this.verifiedLocal = verified;
    }

    public Integer getDeliveryRadiusMetres() {
        return deliveryRadiusMetres;
    }

    public void setDeliveryRadiusMetres(Integer metres) {
        this.deliveryRadiusMetres = metres;
    }

    /** The most tables one shop may have codes for. The database check constraint says the same. */
    public static final int MAX_TABLES = 400;

    /**
     * Says how many tables the room has, which is how many QR cards the shop can print.
     *
     * <p>Refused outside {@code 0..}{@value #MAX_TABLES} rather than clamped: a merchant who typed
     * a number this shop cannot have is better told so than handed a different one silently, and a
     * clamp would turn one mistyped digit into a print job nobody asked for.
     */
    public void seatTables(int tables) {
        if (tables < 0 || tables > MAX_TABLES) {
            throw new IllegalArgumentException(
                    "A shop can have between 0 and " + MAX_TABLES + " tables");
        }
        this.tableCount = (short) tables;
    }

    public short getTableCount() {
        return tableCount;
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

    public Instant getPublishedAt() {
        return publishedAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public List<StoreHours> getHours() {
        return Collections.unmodifiableList(hours);
    }
}

package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.accounting.domain.PointsEntry;
import com.delivery.accounting.domain.PointsEntry.OwnerKind;
import com.delivery.accounting.domain.PointsRedemption;
import com.delivery.accounting.domain.PointsEntryRepository;
import com.delivery.accounting.domain.PointsRedemptionRepository;

/**
 * Earning and redeeming points.
 *
 * <p>What replaced bank settlement as the way merchants and riders are actually paid. The ledger in
 * {@code transactions} still records who is owed what and is what a future bank settlement would
 * post from; this is what somebody can convert into money today.
 *
 * <p><strong>Nothing here moves money.</strong> A redemption is a request an operator approves and
 * then pays by hand. Saying so in the model is more honest than a {@code payout()} that only writes
 * a row.
 */
@Service
public class PointsService {

    private static final Logger log = LoggerFactory.getLogger(PointsService.class);

    private final PointsEntryRepository entries;
    private final PointsRedemptionRepository redemptions;
    private final BigDecimal merchantRate;
    private final BigDecimal deliveryRate;
    private final BigDecimal customerRate;
    private final BigDecimal pointValue;
    private final long minimumRedemption;
    private final String currency;

    public PointsService(PointsEntryRepository entries,
                         PointsRedemptionRepository redemptions,
                         // Points per unit of the goods subtotal. A percentage-shaped reward: a
                         // bigger basket is worth more, which is what a shop expects.
                         @Value("${delivery.points.merchant-rate:5}") BigDecimal merchantRate,
                         // Points per unit of the delivery fee. Separate from the merchant rate
                         // because the two reward different work and will be tuned against each
                         // other, not together.
                         @Value("${delivery.points.delivery-rate:10}") BigDecimal deliveryRate,
                         // Points per unit of the order TOTAL, for the customer who placed it —
                         // the loyalty half. Its own rate because loyalty is priced against
                         // marketing spend, not against what a shop or a carrier is owed.
                         @Value("${delivery.points.customer-rate:5}") BigDecimal customerRate,
                         // What one point is worth on redemption.
                         @Value("${delivery.points.point-value:0.01}") BigDecimal pointValue,
                         // Below this a request is refused. Stops the payout queue filling with
                         // requests that cost more in operator time than they are worth.
                         @Value("${delivery.points.minimum-redemption:1000}") long minimumRedemption,
                         @Value("${delivery.accounting.currency:USD}") String currency) {
        this.entries = entries;
        this.redemptions = redemptions;
        this.merchantRate = merchantRate;
        this.deliveryRate = deliveryRate;
        this.customerRate = customerRate;
        this.pointValue = pointValue;
        this.minimumRedemption = minimumRedemption;
        this.currency = currency;
    }

    /**
     * Awards points for a delivered order.
     *
     * <p>Two awards, to two different parties, from two different amounts: the shop earns on what
     * it sold, and whoever carried it earns on the delivery fee. Awarding both from the total would
     * pay the shop for the delivery and the carrier for the goods.
     *
     * <p><strong>Who the delivery points belong to.</strong> A rider employed by a delivery company
     * earns into that COMPANY's balance, tagged with the rider who did the work so the company can
     * see it and pay them. A rider on the platform's own fleet has no company, so they hold their
     * own points. {@code carrierRef} being null is what distinguishes the two, and it comes
     * straight from the event's {@code deliveryProviderAccount} being null for platform riders.
     *
     * <p>Idempotent by construction: a partial unique index on (order_id, owner_kind, owner_ref)
     * for earned rows means a redelivered {@code order.delivered} cannot pay anybody twice. The
     * bus is at-least-once, so this is not a theoretical concern.
     */
    @Transactional
    public void awardForDelivery(UUID orderId, String merchantRef, BigDecimal goodsAmount,
                                 String riderRef, String carrierRef, BigDecimal deliveryFee,
                                 String customerRef, BigDecimal totalAmount) {

        if (merchantRef != null && isPositive(goodsAmount)) {
            long points = pointsFor(goodsAmount, merchantRate);
            if (points > 0) {
                award(PointsEntry.earned(OwnerKind.MERCHANT, merchantRef, orderId, points, null),
                        orderId);
            }
        }

        if (isPositive(deliveryFee)) {
            long points = pointsFor(deliveryFee, deliveryRate);
            if (points > 0) {
                if (carrierRef != null) {
                    award(PointsEntry.earned(
                            OwnerKind.CARRIER, carrierRef, orderId, points, riderRef), orderId);
                } else if (riderRef != null) {
                    award(PointsEntry.earned(
                            OwnerKind.RIDER, riderRef, orderId, points, null), orderId);
                }
            }
        }

        // The customer's loyalty half: earned on the TOTAL, because loyalty rewards what they
        // spent — goods, fee and all — where the shop and the carrier are each paid for their own
        // part. Same idempotent index, so a redelivered event still pays nobody twice.
        if (customerRef != null && isPositive(totalAmount)) {
            long points = pointsFor(totalAmount, customerRate);
            if (points > 0) {
                award(PointsEntry.earned(OwnerKind.CUSTOMER, customerRef, orderId, points, null),
                        orderId);
            }
        }
    }

    // ---------------------------------------------------------------------------- loyalty tiers

    /**
     * The loyalty ladder, judged on LIFETIME earnings so spending points never demotes anybody.
     *
     * <p>Constants rather than configuration: a tier threshold is a promise printed on a
     * customer's screen, and quietly moving it in a config file is how "550 points to Gold"
     * becomes a lie between two deploys. Changing these is a product decision that should look
     * like one — a code change with a review.
     */
    public enum Tier {
        BRONZE(0),
        SILVER(1_000),
        GOLD(3_000),
        PLATINUM(8_000);

        private final long floor;

        Tier(long floor) {
            this.floor = floor;
        }

        public long floor() {
            return floor;
        }

        public static Tier forLifetime(long lifetimeEarned) {
            Tier current = BRONZE;
            for (Tier tier : values()) {
                if (lifetimeEarned >= tier.floor) {
                    current = tier;
                }
            }
            return current;
        }

        /** The next rung, or null from the top one. */
        public Tier next() {
            int i = ordinal() + 1;
            return i < values().length ? values()[i] : null;
        }
    }

    /** Everything the rewards screen needs in one read. */
    public record LoyaltyStanding(long balance, long lifetimeEarned, long ordersCompleted,
                                  Tier tier, Tier nextTier, long pointsToNextTier,
                                  BigDecimal cashbackValue, String currency) {
    }

    @Transactional(readOnly = true)
    public LoyaltyStanding standingOf(OwnerKind kind, String ref) {
        long balance = entries.balanceOf(kind, ref);
        long lifetime = entries.lifetimeEarnedOf(kind, ref);
        long orders = entries.earnedCountOf(kind, ref);
        Tier tier = Tier.forLifetime(lifetime);
        Tier next = tier.next();
        long toNext = next == null ? 0 : Math.max(0, next.floor() - lifetime);
        return new LoyaltyStanding(balance, lifetime, orders, tier, next, toNext,
                valueOf(Math.max(0, balance)), currency);
    }

    /**
     * Writes one award, tolerating the duplicate a redelivery causes.
     *
     * <p>Caught rather than pre-checked. An exists-then-insert has a window between the two, and
     * the index is what actually guarantees this — so the honest implementation is to let it fire
     * and treat it as the no-op it is.
     */
    private void award(PointsEntry entry, UUID orderId) {
        try {
            entries.saveAndFlush(entry);
            log.debug("Awarded {} points to {} {} for order {}",
                    entry.getPoints(), entry.getOwnerKind(), entry.getOwnerRef(), orderId);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            log.debug("Order {} already earned points for {} {}; ignoring the redelivery",
                    orderId, entry.getOwnerKind(), entry.getOwnerRef());
        }
    }

    /**
     * Points for an amount, rounded down.
     *
     * <p>DOWN rather than HALF_UP: rounding up gives away a point the platform did not earn on
     * every fractional order, and across a lot of small orders that is a real cost with no upside.
     */
    private long pointsFor(BigDecimal amount, BigDecimal rate) {
        return amount.multiply(rate).setScale(0, RoundingMode.DOWN).longValue();
    }

    private static boolean isPositive(BigDecimal value) {
        return value != null && value.signum() > 0;
    }

    public long balanceOf(OwnerKind kind, String ref) {
        return entries.balanceOf(kind, ref);
    }

    /** What a balance is currently worth, at today's rate. */
    public BigDecimal valueOf(long points) {
        return BigDecimal.valueOf(points).multiply(pointValue).setScale(2, RoundingMode.DOWN);
    }

    public List<PointsEntry> history(OwnerKind kind, String ref, int limit) {
        return entries.findByOwnerKindAndOwnerRefOrderByCreatedAtDesc(
                kind, ref, PageRequest.of(0, limit));
    }

    /** What each of a carrier's riders earned, most first. */
    public List<RiderEarning> riderBreakdown(String carrierRef) {
        return entries.earnedPerRider(OwnerKind.CARRIER, carrierRef).stream()
                .map(row -> new RiderEarning((String) row[0], ((Number) row[1]).longValue()))
                .toList();
    }

    public record RiderEarning(String riderRef, long points) {
    }

    public Optional<PointsRedemption> openRequestFor(OwnerKind kind, String ref) {
        return redemptions.findOpenFor(kind, ref);
    }

    public List<PointsRedemption> requestsFor(OwnerKind kind, String ref) {
        return redemptions.findByOwnerKindAndOwnerRefOrderByRequestedAtDesc(kind, ref);
    }

    public List<PointsRedemption> queue() {
        return redemptions.findByStatusInOrderByRequestedAtAsc(
                List.of(PointsRedemption.Status.PENDING, PointsRedemption.Status.APPROVED));
    }

    /**
     * Requests a redemption, holding the points immediately.
     *
     * <p>The hold is written in the same transaction as the request. If it were not, a slow
     * approval would leave the points spendable and the platform could owe them twice.
     */
    @Transactional
    public PointsRedemption request(OwnerKind kind, String ref, long points, String payoutNote,
                                    String requestedBy) {
        if (points < minimumRedemption) {
            throw new IllegalArgumentException(
                    "The minimum redemption is " + minimumRedemption + " points");
        }
        if (redemptions.findOpenFor(kind, ref).isPresent()) {
            throw new IllegalStateException(
                    "There is already a redemption request waiting on a decision");
        }
        long balance = entries.balanceOf(kind, ref);
        if (points > balance) {
            throw new IllegalArgumentException(
                    "Not enough points: the balance is " + balance);
        }

        PointsRedemption redemption = new PointsRedemption(
                kind, ref, points, valueOf(points), currency, payoutNote, requestedBy);
        redemptions.save(redemption);
        entries.save(PointsEntry.held(kind, ref, redemption.getId(), points));

        log.info("{} {} requested {} points ({} {})", kind, ref, points,
                redemption.getAmount(), currency);
        return redemption;
    }

    @Transactional
    public PointsRedemption approve(UUID id, String by, String note) {
        PointsRedemption redemption = load(id);
        redemption.approve(by, note);
        return redemption;
    }

    /** Refuses a request and gives the held points back. */
    @Transactional
    public PointsRedemption reject(UUID id, String by, String note) {
        PointsRedemption redemption = load(id);
        redemption.reject(by, note);
        entries.save(PointsEntry.released(redemption.getOwnerKind(), redemption.getOwnerRef(),
                redemption.getId(), redemption.getPoints()));
        return redemption;
    }

    /** The requester withdrawing their own request. Also gives the points back. */
    @Transactional
    public PointsRedemption cancel(UUID id, String by) {
        PointsRedemption redemption = load(id);
        redemption.cancel(by);
        entries.save(PointsEntry.released(redemption.getOwnerKind(), redemption.getOwnerRef(),
                redemption.getId(), redemption.getPoints()));
        return redemption;
    }

    /**
     * Records that an operator handed the money over.
     *
     * <p>The ledger row written here carries zero points: the balance already fell when the hold
     * was taken, and taking them again would charge the requester twice for one redemption. It
     * exists so the history shows the payment.
     */
    @Transactional
    public PointsRedemption markPaid(UUID id, String by, String reference) {
        PointsRedemption redemption = load(id);
        redemption.markPaid(by, reference);
        entries.save(PointsEntry.paid(redemption.getOwnerKind(), redemption.getOwnerRef(),
                redemption.getId()));
        log.info("Redemption {} paid: {} points, {} {}, ref {}", id, redemption.getPoints(),
                redemption.getAmount(), redemption.getCurrency(), reference);
        return redemption;
    }

    private PointsRedemption load(UUID id) {
        return redemptions.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No such redemption: " + id));
    }
}

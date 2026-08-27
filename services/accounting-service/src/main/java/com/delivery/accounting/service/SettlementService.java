package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;
import com.delivery.accounting.domain.RiderLedgerEntry;
import com.delivery.accounting.domain.RiderLedgerRepository;

/**
 * Opens a settlement: works out who is owed what, records the legs, and asks the bank.
 *
 * <p><strong>Settlement happens at delivery, not at checkout.</strong> There is no payment provider
 * in this architecture — the bank is the ledger — so there is no authorisation to capture against.
 * Settling on delivery means the money moves when the goods arrive, and an order cancelled before
 * delivery has nothing to unwind. The alternative, debiting at checkout, would need a refund path
 * for every cancellation and a held-funds concept the bank contract does not describe.
 *
 * <p>Three legs, and the arithmetic is deliberate: the merchant's share is computed as
 * <em>total minus commission</em> rather than as its own percentage, so the legs always sum to
 * exactly the total. Computing both sides independently from percentages is how a rounding
 * remainder ends up unaccounted for on every order.
 */
@Service
public class SettlementService {

    private static final Logger log = LoggerFactory.getLogger(SettlementService.class);

    /**
     * How a settled leg is discharged.
     *
     * <p>A switch rather than a deletion. The bank path — the postings queue, the Core Banking
     * connector's provider abstraction, the sync log, the compensation on a refused posting — is
     * built and tested, and the intent is to return to it once there is a banking agreement. What
     * changed is that there is no bank today, so nothing should be waiting for one.
     */
    public enum SettlementMode {
        /**
         * Record who is owed what and ask no bank. Every leg is terminal as it is written.
         *
         * <p>What the platform runs on now: cash on delivery, and merchants and riders paid in
         * points they redeem, rather than bank transfers.
         */
        LEDGER_ONLY,
        /**
         * Publish each leg to the Core Banking connector and advance on its answer.
         *
         * <p>Requires that connector to be deployed. It is not, so selecting this leaves every
         * credit PENDING forever.
         */
        BANK
    }

    private final AccountingTransactionRepository transactions;
    private final CashFloatRepository floatEntries;
    private final RiderLedgerRepository riderLedger;
    private final BankPostingPublisher postings;
    private final SettlementMode settlementMode;
    private final BigDecimal commissionPercentage;
    private final BigDecimal deliveryCommissionPercentage;
    private final BigDecimal riderFeeSharePercentage;
    private final String platformAccount;
    private final String currency;

    public SettlementService(AccountingTransactionRepository transactions,
                             CashFloatRepository floatEntries,
                             RiderLedgerRepository riderLedger,
                             BankPostingPublisher postings,
                             @Value("${delivery.ordering.commission-percentage:12.5}")
                             BigDecimal commissionPercentage,
                             // The platform's take on a delivery it did not perform. Lower than the
                             // goods commission on purpose: finding a carrier work is worth less
                             // than selling a merchant a customer.
                             @Value("${delivery.ordering.delivery-commission-percentage:10}")
                             BigDecimal deliveryCommissionPercentage,
                             // What one of the PLATFORM'S OWN riders keeps of a delivery fee, as a
                             // percentage of it.
                             //
                             // BLANK BY DEFAULT, AND THAT DEFAULT IS THE POINT. Nobody has told
                             // this codebase what the platform pays its own riders — the commercial
                             // arrangement genuinely is not encoded anywhere — so rather than pick
                             // a plausible-looking number, a blank value means "pay them exactly
                             // what an outside carrier would have been paid for the same job":
                             // the fee less the platform's delivery commission. That is the one
                             // split the platform HAS decided, mirrored rather than reinvented, and
                             // it is defensible on its face — the platform takes the same cut for
                             // the same work whoever performed it.
                             //
                             // Set it to a number to override. See riderShareOf() below.
                             @Value("${delivery.rider-earnings.platform-fleet-fee-share-percentage:}")
                             String riderFeeSharePercentage,
                             @Value("${delivery.accounting.platform-account:ACC-PLATFORM}")
                             String platformAccount,
                             @Value("${delivery.accounting.currency:USD}") String currency,
                             // LEDGER_ONLY by default, and deliberately so: a default that waits
                             // for a bank nobody deployed leaves every credit PENDING and pays no
                             // one, which is a worse failure than a ledger that settles too easily.
                             @Value("${delivery.accounting.settlement-mode:LEDGER_ONLY}")
                             SettlementMode settlementMode) {
        this.transactions = transactions;
        this.floatEntries = floatEntries;
        this.riderLedger = riderLedger;
        this.postings = postings;
        this.settlementMode = settlementMode;
        this.commissionPercentage = commissionPercentage;
        this.deliveryCommissionPercentage = deliveryCommissionPercentage;
        this.riderFeeSharePercentage =
                (riderFeeSharePercentage == null || riderFeeSharePercentage.isBlank())
                        ? null
                        : new BigDecimal(riderFeeSharePercentage.trim());
        this.platformAccount = platformAccount;
        this.currency = currency;
    }

    /**
     * Who took the notes, when an order was paid in cash.
     *
     * <p>Null means it was not — a card order has no holder, because the money went straight to a
     * bank account and nobody is carrying it.
     */
    public record CashHolder(String ref, CashFloatEntry.HolderKind kind) {
    }

    /**
     * Settles a delivered order.
     *
     * <p>Two amounts, not one, and the distinction is the whole point. The customer is debited the
     * <strong>total</strong>, which includes the delivery fee. Commission and the merchant's share
     * are computed from the <strong>merchant base</strong> — the goods subtotal — because the
     * delivery fee is not the merchant's revenue: it pays for the delivery. Splitting the total
     * would hand the shop the fee and then take a cut of it, which is wrong twice.
     *
     * <p>The platform leg is therefore whatever is left once the merchant, the carrier and the
     * rider have been paid, so the legs still sum to the total exactly however the fee is split.
     * Before riders earned per job that residue was commission <em>plus</em> the whole delivery fee
     * on an own-fleet order; it is now commission plus whatever of the fee the rider did not keep.
     *
     * @param total          what the customer pays: goods plus delivery
     * @param merchantBase   the goods subtotal; commission is a percentage of this
     * @param customerAccount where the money comes from
     * @param merchantAccount where the merchant's share goes
     * @return the legs created, empty if this order was already settled
     */
    /**
     * What the platform absorbed on this order, as decided when it was placed.
     *
     * @param deliveryFee     what delivery COSTS — what the carrier is owed, whoever paid it
     * @param customerWaived  the customer was not charged the delivery fee; the platform absorbs it
     * @param merchantWaived  no commission is taken; the merchant keeps the whole goods amount
     * @param carrierWaived   no platform cut; the carrier keeps the whole delivery fee
     * @param discount        money a promo code took off what the customer paid.
     *                        <p>A promotion comes out of the platform's margin and never out of what
     *                        somebody else is paid, which Order Manager states as part of the event
     *                        contract: the merchant is still owed the whole {@code subtotal} and the
     *                        carrier the whole {@code deliveryFee}. That falls out of the arithmetic
     *                        on its own — the platform leg is the residue and simply goes negative,
     *                        posting a PLATFORM_SUBSIDY. What does <em>not</em> fall out on its own
     *                        is the sanity clamp on the merchant base: {@code totalAmount} is net of
     *                        the discount, so on a well-discounted order the goods subtotal exceeds
     *                        it, and clamping the base to the total would pay the merchant less than
     *                        they sold — charging the shop for the platform's promotion. This is the
     *                        figure that tells the clamp what the order was worth before the
     *                        platform gave money away. Null on an order with no code, and on every
     *                        event published before codes existed
     */
    public record Waivers(BigDecimal deliveryFee, boolean customerWaived, boolean merchantWaived,
                          boolean carrierWaived, BigDecimal discount) {

        /**
         * No offers, and no explicit fee — the shape of every event published before waivers
         * existed. The fee is then derived from the total exactly as it always was.
         */
        public static Waivers none() {
            return new Waivers(null, false, false, false, null);
        }

        /** The pre-promotions shape, kept so callers written before codes existed read unchanged. */
        public Waivers(BigDecimal deliveryFee, boolean customerWaived, boolean merchantWaived,
                       boolean carrierWaived) {
            this(deliveryFee, customerWaived, merchantWaived, carrierWaived, null);
        }

        /** What the order was worth before the platform discounted it. */
        BigDecimal grossOf(BigDecimal netTotal) {
            return discount == null || discount.signum() <= 0
                    ? netTotal
                    : netTotal.add(discount);
        }
    }

    /**
     * The person who actually carried the order, and who employs them.
     *
     * <p>Null when the event does not name a rider, which is what every event looked like before
     * the rider app had an Earnings screen. Settlement is unchanged in that case: the whole
     * delivery fee stays where it went before, and no rider is credited for work nobody recorded.
     *
     * @param riderRef    the rider's Keycloak subject
     * @param accountRef  where the platform pays them, from the account directory
     * @param carrierRef  the delivery company they ride for; null on the platform's own fleet.
     *                    A LABEL only — the fleet itself is decided by whether the order has a
     *                    carrier account, which is the discriminator the settlement already turns
     *                    on. Two facts that could disagree would eventually disagree
     * @param customerRef who paid for the order, kept so a tip can be proved to come from them
     */
    public record Rider(String riderRef, String accountRef, String carrierRef, String customerRef) {
    }

    /** The pre-waiver signature, kept so existing callers and tests read unchanged. */
    @Transactional
    public List<AccountingTransaction> settle(UUID orderId, BigDecimal total,
                                              BigDecimal merchantBase,
                                              String customerAccount, String merchantAccount,
                                              String carrierAccount,
                                              CashHolder cashHolder, String correlationId) {
        return settle(orderId, total, merchantBase, customerAccount, merchantAccount,
                carrierAccount, cashHolder, correlationId, Waivers.none());
    }

    /** The pre-rider signature: settles exactly as it did before riders earned per job. */
    @Transactional
    public List<AccountingTransaction> settle(UUID orderId, BigDecimal total,
                                              BigDecimal merchantBase,
                                              String customerAccount, String merchantAccount,
                                              String carrierAccount,
                                              CashHolder cashHolder, String correlationId,
                                              Waivers waivers) {
        return settle(orderId, total, merchantBase, customerAccount, merchantAccount,
                carrierAccount, cashHolder, correlationId, waivers, null, null);
    }

    /**
     * @param rider     who carried it, or null when the event does not say
     * @param earnedAt  when it was delivered, for the rider's per-day statement. The row must land
     *                  in the day the work happened, not the day a slow bus delivered the event
     */
    @Transactional
    public List<AccountingTransaction> settle(UUID orderId, BigDecimal total,
                                              BigDecimal merchantBase,
                                              String customerAccount, String merchantAccount,
                                              String carrierAccount,
                                              CashHolder cashHolder, String correlationId,
                                              Waivers waivers, Rider rider,
                                              java.time.Instant earnedAt) {

        // At-least-once bus delivery means order.delivered can arrive twice. Settling twice would
        // really move money twice, so this check — backed by the unique constraint on
        // (order_id, leg) — is the most important line in this class.
        if (transactions.existsByOrderId(orderId)) {
            log.debug("Order {} is already settled", orderId);
            return List.of();
        }

        BigDecimal amount = total.setScale(2, RoundingMode.HALF_UP);
        if (amount.signum() <= 0) {
            log.warn("Refusing to settle order {} with a total of {}", orderId, total);
            return List.of();
        }

        // Defaults to the whole amount when no base is given, which keeps the old behaviour for an
        // event published before the breakdown existed rather than silently paying the merchant
        // nothing.
        BigDecimal goods = (merchantBase == null ? amount : merchantBase)
                .setScale(2, RoundingMode.HALF_UP);
        // Clamped: a base above what the order was worth would produce a merchant share nobody paid
        // for, and a negative one would invert the legs.
        //
        // Compared against the GROSS, not against what the customer paid. A promo code comes off the
        // total and never off the merchant's goods, so on a well-discounted order the subtotal is
        // legitimately larger than the total — clamping to the total there would quietly pay the
        // shop less than they sold, charging the merchant for the platform's own promotion. Adding
        // the discount back is what tells the two cases apart: a real inconsistency in the event
        // still trips the clamp, and a discounted order does not.
        BigDecimal gross = waivers.grossOf(amount);
        if (goods.signum() < 0 || goods.compareTo(gross) > 0) {
            log.warn("Order {} has a merchant base of {} against a gross of {}; using the gross",
                    orderId, goods, gross);
            goods = gross;
        }

        // No commission at all when the merchant's fee was waived: they keep the whole goods amount
        // and the platform absorbs what it would have taken.
        BigDecimal commission = waivers.merchantWaived()
                ? BigDecimal.ZERO
                : goods.multiply(commissionPercentage)
                        .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        // Not `goods * (100 - pct)`: derived by subtraction so nothing is lost to rounding.
        BigDecimal merchantShare = goods.subtract(commission);

        // What the delivery was worth, and who gets it.
        //
        // Taken from the event when it is there, and only derived as `total - goods` when it is not.
        // The derivation is what every event carried before waivers existed, and it is exactly wrong
        // for a waived delivery fee: the customer paid nothing towards it, so the subtraction gives
        // zero and a carrier who did the work would be paid nothing. What delivery costs and who
        // paid for it are two different facts.
        // The fallback subtracts from the gross for the same reason the clamp compares against it:
        // a discount comes off the total, not off the delivery. In practice the two are identical —
        // an event old enough to omit the fee is older than promo codes — but a subtraction that is
        // only right when a field happens to be absent is a trap for whoever reads it next.
        BigDecimal deliveryFee = waivers.deliveryFee() != null
                ? waivers.deliveryFee().setScale(2, RoundingMode.HALF_UP)
                : gross.subtract(goods);

        // When the platform's own riders carried the order there is no carrier account and the fee
        // stays with the platform, exactly as it did before delivery could be bought from anybody
        // else. When somebody else carried it, the fee is theirs less the platform's cut for
        // finding them the work — the delivery fee is not platform revenue, it is what delivery
        // costs, and only the take rate on it ever was.
        BigDecimal carrierShare = BigDecimal.ZERO;
        if (carrierAccount != null && deliveryFee.signum() > 0) {
            carrierShare = deliveryFee.subtract(deliveryCut(deliveryFee, waivers.carrierWaived()));
        }

        // What one of the PLATFORM'S OWN riders is paid for carrying it.
        //
        // Only when there is no carrier: a company's rider is paid by their company out of the
        // PROVIDER_CREDIT above, and crediting them here as well would pay for one delivery twice.
        // That is the difference between the two employment cases, and it is decided by the same
        // null the carrier leg turns on rather than by a second flag that could disagree with it.
        //
        // Before this, the whole fee stayed with the platform on an own-fleet order because there
        // was nobody else in the model to give it to. Paying a rider is therefore a genuine RE-SPLIT
        // of the order total, not a new charge: the platform's leg below shrinks by exactly this
        // amount and the legs still sum to what the customer paid.
        //
        // The account is required as well as the rider: account_ref is NOT NULL on the leg, and a
        // rider the directory could not resolve would take the whole settlement down with a
        // constraint violation rather than being quietly left unpaid in the reconciliation view.
        BigDecimal riderShare = BigDecimal.ZERO;
        if (carrierAccount == null && rider != null && rider.accountRef() != null
                && deliveryFee.signum() > 0) {
            riderShare = riderShareOf(deliveryFee, waivers.carrierWaived());
        }

        // Everything the customer paid that neither the merchant nor the carrier receives. Derived
        // by subtraction so the legs sum to the total exactly whatever the rounding did.
        //
        // This goes NEGATIVE when the platform gave away more than it took — most obviously a free
        // delivery whose fee exceeds the commission on a small basket. That is the offer working as
        // intended, not a fault: the platform is buying the order. It is also precisely what the
        // budget in FeeWaiverService exists to bound, and why the leg below is only posted when
        // there is something positive to post.
        BigDecimal platformShare =
                amount.subtract(merchantShare).subtract(carrierShare).subtract(riderShare);

        List<AccountingTransaction> legs = new ArrayList<>();
        legs.add(collectionLeg(orderId, amount, customerAccount, cashHolder, correlationId));
        legs.add(new AccountingTransaction(orderId, Leg.MERCHANT_CREDIT, merchantAccount,
                merchantShare, currency, Direction.CREDIT, correlationId));

        if (carrierShare.signum() > 0) {
            legs.add(new AccountingTransaction(orderId, Leg.PROVIDER_CREDIT, carrierAccount,
                    carrierShare, currency, Direction.CREDIT, correlationId));
        }

        if (riderShare.signum() > 0) {
            legs.add(new AccountingTransaction(orderId, Leg.RIDER_CREDIT, rider.accountRef(),
                    riderShare, currency, Direction.CREDIT, correlationId));
        }

        // A zero-value posting (a fully-discounted order, or a rounding floor) must not be sent:
        // the bank rejects those, and the rejection would look like a real failure.
        if (platformShare.signum() > 0) {
            legs.add(new AccountingTransaction(orderId, Leg.PLATFORM_COMMISSION, platformAccount,
                    platformShare, currency, Direction.CREDIT, correlationId));
        } else if (platformShare.signum() < 0) {
            // The platform is paying in. Posted as its own DEBIT leg rather than skipped: dropping
            // it would leave the credits exceeding what was collected, and the books not balancing
            // is a worse problem than the loss it is hiding.
            legs.add(new AccountingTransaction(orderId, Leg.PLATFORM_SUBSIDY, platformAccount,
                    platformShare.negate(), currency, Direction.DEBIT, correlationId));
        }

        transactions.saveAll(legs);
        log.info("Settling order {}: total {} (goods {} + delivery {}) "
                        + "= merchant {} + carrier {} + rider {} + platform {}",
                orderId, amount, goods, deliveryFee, merchantShare, carrierShare, riderShare,
                platformShare);

        // The rider's own ledger row, written in THIS transaction.
        //
        // Deliberately not deferred to a listener the way points are. Points are a separate reward
        // scheme that can be adjusted by an operator if it drifts; this row is the balance the rider
        // cashes out, so it must be exactly as true as the RIDER_CREDIT leg beside it. Two writes
        // that can succeed independently are two numbers that will eventually disagree, and the
        // disagreement is discovered by a rider being paid the wrong amount.
        creditRider(orderId, rider, carrierAccount, carrierShare, riderShare, earnedAt);

        // The debit is asked for now; the credits wait until it has actually posted. Sequencing
        // them means the platform never credits a merchant for money it failed to collect — the
        // one ordering mistake in a settlement saga that costs real money rather than time.
        openWithTheBank(legs);
        return legs;
    }

    /**
     * Settles a delivered errand, where there is no merchant.
     *
     * <p>The parties are different and so is the commission base. On a catalog order the platform
     * takes a cut of the <em>goods</em>, because it sold them on the shop's behalf. On an errand it
     * sold nothing: the rider bought the goods with their own money at whatever they cost, and what
     * the platform provided — and may take a cut of — is the errand itself. Charging commission on
     * the goods would bill the rider for the privilege of fronting the money.
     *
     * <p>So the rider is credited the goods back <em>in full</em> plus what is left of the fee, and
     * the platform takes its percentage of the fee alone. On a SEND the goods are zero and this
     * reduces to a straight fee split, which is why one method serves both.
     *
     * <p>Derived by subtraction, as above, so the legs sum to exactly what the customer paid
     * whatever the rounding did.
     *
     * @param total     what the customer pays: goods plus the errand fee
     * @param goodsCost what the rider spent out of pocket; zero when nothing was bought
     */
    /** The pre-rider signature: settles exactly as it did before riders earned per job. */
    @Transactional
    public List<AccountingTransaction> settleErrand(UUID orderId, BigDecimal total,
                                                    BigDecimal goodsCost,
                                                    String customerAccount, String riderAccount,
                                                    CashHolder cashHolder, String correlationId) {
        return settleErrand(orderId, total, goodsCost, customerAccount, riderAccount, cashHolder,
                correlationId, null, null);
    }

    /**
     * @param rider    who ran it, or null when the event does not say
     * @param earnedAt when it was delivered, so the statement buckets it on the day it was worked
     */
    @Transactional
    public List<AccountingTransaction> settleErrand(UUID orderId, BigDecimal total,
                                                    BigDecimal goodsCost,
                                                    String customerAccount, String riderAccount,
                                                    CashHolder cashHolder, String correlationId,
                                                    Rider rider, java.time.Instant earnedAt) {

        if (transactions.existsByOrderId(orderId)) {
            log.debug("Errand {} is already settled", orderId);
            return List.of();
        }

        BigDecimal amount = total.setScale(2, RoundingMode.HALF_UP);
        if (amount.signum() <= 0) {
            log.warn("Refusing to settle errand {} with a total of {}", orderId, total);
            return List.of();
        }

        BigDecimal goods = (goodsCost == null ? BigDecimal.ZERO : goodsCost)
                .setScale(2, RoundingMode.HALF_UP);
        // Clamped for the same reason as the catalog path: goods above the total would credit the
        // rider money the customer never paid, and negative goods would invert the legs.
        if (goods.signum() < 0 || goods.compareTo(amount) > 0) {
            log.warn("Errand {} claims goods of {} against a total of {}; treating goods as the total",
                    orderId, goods, amount);
            goods = amount;
        }

        // What the platform actually sold. Everything the customer paid that was not reimbursement.
        BigDecimal fee = amount.subtract(goods);
        BigDecimal commission = fee
                .multiply(commissionPercentage)
                .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        BigDecimal riderShare = amount.subtract(commission);

        List<AccountingTransaction> legs = new ArrayList<>();
        legs.add(collectionLeg(orderId, amount, customerAccount, cashHolder, correlationId));
        legs.add(new AccountingTransaction(orderId, Leg.RIDER_CREDIT, riderAccount,
                riderShare, currency, Direction.CREDIT, correlationId));

        // A fee small enough to round the commission to zero produces no leg: the bank rejects a
        // zero posting, and that rejection would look like a real failure.
        if (commission.signum() > 0) {
            legs.add(new AccountingTransaction(orderId, Leg.PLATFORM_COMMISSION, platformAccount,
                    commission, currency, Direction.CREDIT, correlationId));
        }

        transactions.saveAll(legs);
        log.info("Settling errand {}: total {} (goods {} + fee {}) = rider {} + platform {}",
                orderId, amount, goods, fee, riderShare, commission);

        // The rider's own record, split into the two things the credit above is made of.
        //
        // The RIDER_CREDIT leg is one number, and showing it as "earnings" would flatter every
        // Butler shift: most of it is the rider's own money coming back to them. So the goods go in
        // as a REIMBURSEMENT and only the fee less commission counts as earned. Both are the
        // platform's debt — the rider fronted the money on the platform's instruction, so a company
        // that never saw that transaction cannot be asked to refund it, and an errand's ledger rows
        // are PLATFORM-payable whoever the rider rides for.
        creditErrandRider(orderId, rider, goods, riderShare.subtract(goods), earnedAt);

        openWithTheBank(legs);
        return legs;
    }

    /** Splits an errand's rider credit into reimbursement and earnings. See {@link #creditRider}. */
    private void creditErrandRider(UUID orderId, Rider rider, BigDecimal goods,
                                   BigDecimal earned, java.time.Instant earnedAt) {
        if (rider == null || rider.riderRef() == null) {
            return;
        }
        // Written one at a time and flushed one at a time: they carry different entry types, so a
        // redelivery that duplicates one must not take the other down with it.
        if (goods.signum() > 0) {
            saveRiderRow(RiderLedgerEntry.reimbursement(rider.riderRef(), orderId, goods, currency,
                    RiderLedgerEntry.Fleet.PLATFORM, null, earnedAt), orderId, rider.riderRef());
        }
        if (earned.signum() > 0) {
            saveRiderRow(RiderLedgerEntry.jobEarning(rider.riderRef(), orderId, earned, currency,
                            RiderLedgerEntry.Fleet.PLATFORM, null, rider.customerRef(), earnedAt),
                    orderId, rider.riderRef());
        }
    }

    private void saveRiderRow(RiderLedgerEntry entry, UUID orderId, String riderRef) {
        try {
            riderLedger.saveAndFlush(entry);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            log.debug("Rider {} already has a {} row for order {}; ignoring the redelivery",
                    riderRef, entry.getEntryType(), orderId);
        }
    }

    /**
     * The platform's take on a delivery fee.
     *
     * <p>Extracted so the carrier case and the own-fleet case cannot drift apart. There is one
     * decision about what the platform charges for finding a delivery job a rider, and it applies
     * whoever the rider turns out to work for.
     */
    private BigDecimal deliveryCut(BigDecimal deliveryFee, boolean waived) {
        return waived
                ? BigDecimal.ZERO
                : deliveryFee.multiply(deliveryCommissionPercentage)
                        .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
    }

    /**
     * What one of the platform's own riders keeps of the delivery fee.
     *
     * <p><strong>The unconfigured answer mirrors the carrier arrangement.</strong> Nobody has told
     * this codebase what the platform pays its own riders — it is a commercial term that exists in
     * somebody's head and in no property file — so the honest default is the split the platform HAS
     * already decided for exactly the same work: the fee less the platform's delivery commission,
     * which is precisely what an outside carrier is paid a few lines above. Inventing a second,
     * lower number would be the platform quietly deciding its own riders are worth less, on no
     * authority, in a place nobody would look.
     *
     * <p>{@code delivery.rider-earnings.platform-fleet-fee-share-percentage} overrides it once
     * somebody knows the real figure. Clamped to the fee, because a share above 100% would pay a
     * rider money the customer never handed over and drive the platform leg negative for no reason
     * a subsidy report could explain.
     */
    private BigDecimal riderShareOf(BigDecimal deliveryFee, boolean cutWaived) {
        if (riderFeeSharePercentage == null) {
            return deliveryFee.subtract(deliveryCut(deliveryFee, cutWaived));
        }
        BigDecimal share = deliveryFee.multiply(riderFeeSharePercentage)
                .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
        return share.min(deliveryFee).max(BigDecimal.ZERO);
    }

    /**
     * Writes the rider's own record of the job.
     *
     * <p>Two different rows for two different employment cases, and the difference is the reason
     * this method exists rather than one unconditional insert.
     *
     * <p><strong>Platform fleet:</strong> the amount is the {@code RIDER_CREDIT} leg just written,
     * and the platform owes it. It counts toward the balance and the rider can cash it out.
     *
     * <p><strong>A delivery company's rider:</strong> the platform owes them nothing — it paid
     * their COMPANY for the job through {@code PROVIDER_CREDIT}, and what the company passes on is
     * an employment contract the platform has never been shown. The row is written anyway, marked
     * {@code PayableBy.CARRIER}, so the rider's app can show the work they did; the amount on it is
     * what the platform paid the company for that job, because that is the only figure the platform
     * can state truthfully. It is excluded from the balance by construction, so no amount of
     * getting it wrong can cause the platform to pay it.
     *
     * <p>Tolerates the duplicate a redelivery causes rather than pre-checking it: an
     * exists-then-insert has a window between the two, and the unique index is what actually
     * guarantees this. The outer {@code existsByOrderId} guard means it should never fire; this is
     * the second line of defence, not the first.
     */
    private void creditRider(UUID orderId, Rider rider, String carrierAccount,
                             BigDecimal carrierShare, BigDecimal riderShare,
                             java.time.Instant earnedAt) {
        if (rider == null || rider.riderRef() == null) {
            return;
        }

        boolean onCarrierFleet = carrierAccount != null;
        BigDecimal amount = onCarrierFleet ? carrierShare : riderShare;
        if (amount.signum() <= 0) {
            // Nothing was earned: a zero delivery fee, or an own-fleet order with no fee at all.
            // A zero row would say the rider worked for nothing, which is a different claim.
            return;
        }

        saveRiderRow(RiderLedgerEntry.jobEarning(
                rider.riderRef(), orderId, amount, currency,
                onCarrierFleet ? RiderLedgerEntry.Fleet.CARRIER : RiderLedgerEntry.Fleet.PLATFORM,
                onCarrierFleet ? rider.carrierRef() : null,
                rider.customerRef(), earnedAt), orderId, rider.riderRef());
    }

    /**
     * The leg that says the customer paid, which is a different event for each payment method.
     *
     * <p><strong>Card:</strong> money really does leave a bank account, so this is an ordinary
     * posting the credits behind it wait on.
     *
     * <p><strong>Cash:</strong> nothing leaves any account. The customer handed notes to whoever
     * turned up, and the platform now pays the merchant against money it does not yet hold. That is
     * an obligation, not a transfer — so it is recorded as one, and a matching float entry says who
     * is holding the cash until they bank it.
     *
     * <p>This is the whole fix. The previous attempt kept asking the bank to post it and only
     * changed whose account was named, which failed for want of funds because a rider holds notes
     * and not a balance — taking the merchant and commission legs down with it.
     */
    private AccountingTransaction collectionLeg(UUID orderId, BigDecimal amount,
                                                String customerAccount, CashHolder holder,
                                                String correlationId) {
        if (holder == null) {
            return new AccountingTransaction(orderId, Leg.CUSTOMER_DEBIT, customerAccount,
                    amount, currency, Direction.DEBIT, correlationId);
        }

        // Guarded as well as constrained: the bus delivers at least once, and booking the same
        // order's cash twice would invent a debt the holder does not owe.
        if (!floatEntries.existsByOrderIdAndEntryKind(orderId, CashFloatEntry.Kind.COLLECTED)) {
            floatEntries.save(CashFloatEntry.collected(
                    holder.ref(), holder.kind(), orderId, amount, currency));
        }

        return AccountingTransaction.obligation(orderId, Leg.CASH_COLLECTED, holder.ref(),
                amount, currency, Direction.DEBIT, correlationId);
    }

    /**
     * Asks the bank for the next leg in the sequence.
     *
     * <p><strong>One leg at a time, in order: debit, then merchant, then commission.</strong>
     * Firing both credits together looks faster and is wrong. If the merchant credit is refused
     * while the commission has already posted, the platform has kept its cut of an order it then
     * refunds to the customer — money created from nothing, and only invisible because a simulator
     * does not enforce double-entry. Sequencing removes that state instead of adding a reversal to
     * clean it up.
     *
     * <p>The residual case is the commission failing after the merchant has been paid. That leaves
     * the platform out of pocket for its own revenue rather than leaving customer money in the
     * wrong place — a much smaller problem, and one the reconciliation view shows as FAILED.
     *
     * <p>{@code REQUIRES_NEW}, and that is load-bearing rather than a preference. This is called
     * from the saga's after-commit callback, at which point the outer transaction has committed but
     * is not yet cleaned up — a plain {@code REQUIRED} would silently join that finished
     * transaction, and the {@code afterCommit} hook registered below would then be attached to a
     * commit phase that has already run and would never fire. The symptom is the worst one
     * available: the customer is debited and the credits sit at PENDING forever.
     */
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.REQUIRES_NEW)
    public void releaseNextLeg(UUID orderId) {
        List<AccountingTransaction> legs = transactions.findByOrderIdOrderByCreatedAt(orderId);

        // Every payee leg an order can carry, in the order they must be released. An order need not
        // have all of them: an errand pays a rider and no merchant, a catalog order carried by a
        // company pays a merchant and a carrier, and one carried by the platform's own fleet now
        // pays a merchant AND a rider. Missing legs are skipped by the null check below, exactly as
        // a zero-commission order's missing commission leg is. Leaving RIDER_CREDIT out of this
        // list would debit the customer for an errand and then never pay anybody.
        for (Leg next : List.of(Leg.MERCHANT_CREDIT, Leg.RIDER_CREDIT, Leg.PROVIDER_CREDIT,
                Leg.PLATFORM_COMMISSION)) {
            AccountingTransaction leg = legs.stream()
                    .filter(t -> t.getLeg() == next)
                    .findFirst()
                    .orElse(null);

            if (leg == null) {
                // A zero-commission order has no commission leg at all; move on.
                continue;
            }
            if (leg.getStatus() == AccountingTransaction.Status.PENDING) {
                publishAfterCommit(leg);
                return;
            }
            if (leg.getStatus() != AccountingTransaction.Status.POSTED) {
                // Failed or abandoned: the saga is unwinding, not progressing.
                return;
            }
        }
    }

    /**
     * Emits the posting only once the row is committed.
     *
     * <p>Ordering matters for the same reason it does in the notification layer, but the stakes are
     * higher: publishing first and then rolling back would have the bank move money for a
     * transaction this service has no record of, which is unreconcilable by definition.
     */
    private void publishAfterCommit(AccountingTransaction leg) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            postings.request(leg);
            return;
        }
        afterCommit(() -> postings.request(leg));
    }

    /**
     * Asks the bank for the first leg that actually needs it.
     *
     * <p>On a card order that is the customer debit, and the credits behind it wait — the platform
     * must never pay a merchant out of money it failed to collect.
     *
     * <p>On a cash order the collection needs no bank at all, so the first real posting is the
     * payee credit and the sequence starts there. The collection is already terminal, so nothing is
     * skipped: it was discharged at the door.
     *
     * <p>Deliberately NOT implemented by calling {@code releaseNextLeg} from here. That method is
     * {@code REQUIRES_NEW} to escape a transaction that has already committed, and a call from
     * inside this class goes straight past the Spring proxy that provides it — so the new
     * transaction never starts, the after-commit hook attaches to a commit that already happened,
     * and it never fires. The symptom is the worst available and exactly what a test caught here:
     * the cash is collected and both credits sit at PENDING forever.
     */
    private void openWithTheBank(List<AccountingTransaction> legs) {
        // LEDGER_ONLY: there is no bank and no Core Banking connector deployed. Every leg is marked
        // discharged outside any bank as it is written, so nothing is published and the saga has
        // nothing left to wait for.
        //
        // The alternative — leaving the legs PENDING with no consumer on the postings queue — is
        // the failure this guard exists to prevent: the order delivers, the customer pays cash, and
        // every credit sits PENDING forever while the reconciliation screen reports a platform that
        // has settled nobody.
        //
        // The whole bank path below is intact and switched by one property, because the intent is
        // to move back to it once there is a banking agreement.
        if (settlementMode == SettlementMode.LEDGER_ONLY) {
            legs.forEach(AccountingTransaction::recordWithoutBank);
            transactions.saveAll(legs);
            return;
        }

        legs.stream()
                .filter(AccountingTransaction::isPostingRequired)
                .findFirst()
                .ifPresent(this::publishAfterCommit);
    }

    /** Runs once the surrounding transaction has committed, or immediately if there is not one. */
    private void afterCommit(Runnable action) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            action.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                action.run();
            }
        });
    }
}

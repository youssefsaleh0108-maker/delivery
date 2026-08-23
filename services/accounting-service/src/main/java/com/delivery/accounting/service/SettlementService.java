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
    private final BankPostingPublisher postings;
    private final SettlementMode settlementMode;
    private final BigDecimal commissionPercentage;
    private final BigDecimal deliveryCommissionPercentage;
    private final String platformAccount;
    private final String currency;

    public SettlementService(AccountingTransactionRepository transactions,
                             CashFloatRepository floatEntries,
                             BankPostingPublisher postings,
                             @Value("${delivery.ordering.commission-percentage:12.5}")
                             BigDecimal commissionPercentage,
                             // The platform's take on a delivery it did not perform. Lower than the
                             // goods commission on purpose: finding a carrier work is worth less
                             // than selling a merchant a customer.
                             @Value("${delivery.ordering.delivery-commission-percentage:10}")
                             BigDecimal deliveryCommissionPercentage,
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
        this.postings = postings;
        this.settlementMode = settlementMode;
        this.commissionPercentage = commissionPercentage;
        this.deliveryCommissionPercentage = deliveryCommissionPercentage;
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
     * <p>The platform leg therefore carries commission <em>plus</em> the delivery fee, so the three
     * legs still sum to the total exactly.
     *
     * @param total          what the customer pays: goods plus delivery
     * @param merchantBase   the goods subtotal; commission is a percentage of this
     * @param customerAccount where the money comes from
     * @param merchantAccount where the merchant's share goes
     * @return the legs created, empty if this order was already settled
     */
    /**
     * Which fees the platform absorbed on this order, as decided when it was placed.
     *
     * @param deliveryFee     what delivery COSTS — what the carrier is owed, whoever paid it
     * @param customerWaived  the customer was not charged the delivery fee; the platform absorbs it
     * @param merchantWaived  no commission is taken; the merchant keeps the whole goods amount
     * @param carrierWaived   no platform cut; the carrier keeps the whole delivery fee
     */
    public record Waivers(BigDecimal deliveryFee, boolean customerWaived, boolean merchantWaived,
                          boolean carrierWaived) {

        /**
         * No offers, and no explicit fee — the shape of every event published before waivers
         * existed. The fee is then derived from the total exactly as it always was.
         */
        public static Waivers none() {
            return new Waivers(null, false, false, false);
        }
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

    @Transactional
    public List<AccountingTransaction> settle(UUID orderId, BigDecimal total,
                                              BigDecimal merchantBase,
                                              String customerAccount, String merchantAccount,
                                              String carrierAccount,
                                              CashHolder cashHolder, String correlationId,
                                              Waivers waivers) {

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
        // Clamped: a base above the total would produce a merchant share the customer never paid
        // for, and a negative one would invert the legs.
        if (goods.signum() < 0 || goods.compareTo(amount) > 0) {
            log.warn("Order {} has a merchant base of {} against a total of {}; using the total",
                    orderId, goods, amount);
            goods = amount;
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
        BigDecimal deliveryFee = waivers.deliveryFee() != null
                ? waivers.deliveryFee().setScale(2, RoundingMode.HALF_UP)
                : amount.subtract(goods);

        // When the platform's own riders carried the order there is no carrier account and the fee
        // stays with the platform, exactly as it did before delivery could be bought from anybody
        // else. When somebody else carried it, the fee is theirs less the platform's cut for
        // finding them the work — the delivery fee is not platform revenue, it is what delivery
        // costs, and only the take rate on it ever was.
        BigDecimal carrierShare = BigDecimal.ZERO;
        if (carrierAccount != null && deliveryFee.signum() > 0) {
            BigDecimal deliveryCut = waivers.carrierWaived()
                    ? BigDecimal.ZERO
                    : deliveryFee.multiply(deliveryCommissionPercentage)
                            .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
            carrierShare = deliveryFee.subtract(deliveryCut);
        }

        // Everything the customer paid that neither the merchant nor the carrier receives. Derived
        // by subtraction so the legs sum to the total exactly whatever the rounding did.
        //
        // This goes NEGATIVE when the platform gave away more than it took — most obviously a free
        // delivery whose fee exceeds the commission on a small basket. That is the offer working as
        // intended, not a fault: the platform is buying the order. It is also precisely what the
        // budget in FeeWaiverService exists to bound, and why the leg below is only posted when
        // there is something positive to post.
        BigDecimal platformShare = amount.subtract(merchantShare).subtract(carrierShare);

        List<AccountingTransaction> legs = new ArrayList<>();
        legs.add(collectionLeg(orderId, amount, customerAccount, cashHolder, correlationId));
        legs.add(new AccountingTransaction(orderId, Leg.MERCHANT_CREDIT, merchantAccount,
                merchantShare, currency, Direction.CREDIT, correlationId));

        if (carrierShare.signum() > 0) {
            legs.add(new AccountingTransaction(orderId, Leg.PROVIDER_CREDIT, carrierAccount,
                    carrierShare, currency, Direction.CREDIT, correlationId));
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
                        + "= merchant {} + carrier {} + platform {}",
                orderId, amount, goods, deliveryFee, merchantShare, carrierShare, platformShare);

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
    @Transactional
    public List<AccountingTransaction> settleErrand(UUID orderId, BigDecimal total,
                                                    BigDecimal goodsCost,
                                                    String customerAccount, String riderAccount,
                                                    CashHolder cashHolder, String correlationId) {

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

        openWithTheBank(legs);
        return legs;
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

        // Both payee legs are listed, and an order only ever has one of them: a catalog order pays
        // a merchant, an errand pays a rider. The missing one is skipped by the null check below,
        // exactly as a zero-commission order's missing commission leg is. Leaving RIDER_CREDIT out
        // of this list would debit the customer for an errand and then never pay anybody.
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

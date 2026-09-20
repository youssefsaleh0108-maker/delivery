package com.delivery.transfer.service;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.client.OrderManagerClient;
import com.delivery.transfer.connector.MoneyTransferConnector;
import com.delivery.transfer.domain.Money;
import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitPlanRepository;
import com.delivery.transfer.domain.SplitShare;
import com.delivery.transfer.domain.TransferMethod;

/**
 * The group-split manager: create, answer, cover, place.
 *
 * <p>Commitment-first by design: the plan collects every share's commitment and only then is the
 * order worth placing. What "commitment" means per kind of participant: an app user promises cash
 * at the door (or, on dev, a wallet payment the simulator stands in for); a guest IS a door-cash
 * promise; a flake's share is covered by the host with one tap. The host's own share is committed
 * from birth — they are the one placing the order, and it is paid however the order is.
 *
 * <p>None of that is money. A share is PAID only when a real provider carried its money to the
 * platform, and no provider can take a share's money yet — so on a cash order the rider collects
 * every share at the door, which is exactly what the ledger books (RECON-01).
 */
@Service
public class SplitService {

    /** The wallet methods a share could travel by, if something could carry it. */
    private static final List<SplitShare.Method> WALLETS =
            List.of(SplitShare.Method.WHISH, SplitShare.Method.OMT, SplitShare.Method.BOB);

    /** The frame's promise: friends have 15 minutes to pay after the invite. */
    private static final Duration WINDOW = Duration.ofMinutes(15);

    /** What a reminder actually buys: five more minutes on the clock. */
    private static final Duration REMINDER_EXTENSION = Duration.ofMinutes(5);

    private final SplitPlanRepository plans;
    private final TransferService transfers;

    public SplitService(SplitPlanRepository plans, TransferService transfers) {
        this.plans = plans;
        this.transfers = transfers;
    }

    public record NewShare(String username, String name, BigDecimal amountUsd, Integer itemsCount) {
    }

    /**
     * Opens a plan: the host's own slice plus one share per friend.
     *
     * <p>Amounts are cents before anything is summed, because the columns hold cents: summed at
     * whatever precision the client sent, the host's remainder and the stored shares could miss the
     * total by a rounding.
     */
    @Transactional
    public SplitPlan create(String hostRef, String hostUsername, String hostName,
                            String storeName, SplitPlan.Mode mode, BigDecimal totalUsd,
                            List<NewShare> shares) {
        BigDecimal total = Money.usd(totalUsd);
        if (total == null || total.signum() <= 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "totalUsd must be positive");
        }
        // The host cannot owe themselves a second slice. A line naming the host is part of the
        // host's own slice, so it is left out BEFORE the others are summed. Summed first, as it
        // was, its amount came off the host's slice and was then dropped with the line: the shares
        // no longer made the total, and the rider's checklist came up short by exactly that much.
        List<NewShare> others = shares == null ? List.of() : shares.stream()
                .filter(s -> !hostUsername.equals(emptyToNull(s.username())))
                .toList();
        if (others.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "a split needs at least one share besides the host");
        }
        BigDecimal othersTotal = BigDecimal.ZERO;
        for (NewShare s : others) {
            BigDecimal amount = Money.usd(s.amountUsd());
            if (amount == null || amount.signum() < 0) {
                throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "a share's amount cannot be negative");
            }
            othersTotal = othersTotal.add(amount);
        }
        if (othersTotal.compareTo(total) > 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "shares exceed the total");
        }

        SplitPlan plan = new SplitPlan(hostRef, hostUsername, hostName, storeName, mode,
                total, transfers.rate(), Instant.now().plus(WINDOW));
        // The host's own slice: whatever the other shares leave of the total. Committed from
        // birth, because the host is the one placing the order — and paid however the order is,
        // which on a cash order means at the door like everybody else's. Never "paid" here.
        SplitShare hostShare = new SplitShare(hostUsername, hostName,
                total.subtract(othersTotal), null);
        hostShare.commitWithOrder();
        plan.addShare(hostShare);

        for (NewShare s : others) {
            plan.addShare(new SplitShare(emptyToNull(s.username()), s.name(),
                    Money.usd(s.amountUsd()), s.itemsCount()));
        }
        plan.recompute();
        return plans.save(plan);
    }

    /** One way an invitee may answer their share, and whether it is only a stand-in. */
    public record ShareMethod(SplitShare.Method method, boolean simulated) {
    }

    /**
     * The ways an invitee can commit their share right now: cash at the door always, and a wallet
     * only where the dev simulator stands in for it — labelled as the simulation it is.
     *
     * <p>A real wallet provider is not offered: nothing can take a share's money yet (a connector
     * carries a transfer against an order, and a share has no order until the plan is placed), so
     * offering one would ask a friend to pay by a route that ends in nothing. With no simulator —
     * every environment but dev — only cash at the door is offered.
     */
    public List<ShareMethod> shareMethods() {
        List<ShareMethod> methods = new ArrayList<>();
        for (SplitShare.Method wallet : WALLETS) {
            transfers.connectorFor(TransferMethod.valueOf(wallet.name()))
                    .filter(MoneyTransferConnector::simulated)
                    .ifPresent(simulator -> methods.add(new ShareMethod(wallet, true)));
        }
        methods.add(new ShareMethod(SplitShare.Method.CASH_AT_DOOR, false));
        return methods;
    }

    private static String emptyToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    @Transactional(readOnly = true)
    public List<SplitPlan> mine(String hostRef) {
        List<SplitPlan> result = plans.findByHostRefOrderByCreatedAtDesc(
                hostRef, PageRequest.of(0, 20));
        Instant now = Instant.now();
        result.forEach(p -> p.expireIfDue(now));
        return result;
    }

    @Transactional
    public List<SplitPlan> requestsFor(String username) {
        List<SplitPlan> result = plans.findOpenRequestsFor(username);
        Instant now = Instant.now();
        result.forEach(p -> p.expireIfDue(now));
        return result.stream()
                .filter(p -> p.getStatus() == SplitPlan.Status.COLLECTING)
                .toList();
    }

    /**
     * A plan its host or an invitee reads. Anybody else is told there is no such split — the same
     * 404 as for an id nobody made — rather than a 403 that would confirm it exists.
     */
    @Transactional
    public SplitPlan read(UUID id, String callerRef, String callerUsername) {
        SplitPlan plan = plans.findById(id)
                .filter(p -> isMember(p, callerRef, callerUsername))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No such split"));
        plan.expireIfDue(Instant.now());
        return plan;
    }

    /** The host, or somebody the host invited by username. */
    private static boolean isMember(SplitPlan plan, String callerRef, String callerUsername) {
        return plan.getHostRef().equals(callerRef)
                || plan.getShares().stream()
                        .anyMatch(s -> callerUsername != null
                                && callerUsername.equals(s.getPayeeUsername()));
    }

    /**
     * An invitee answers their own share: commits to it by a method, or declines.
     *
     * <p>It used to mark the share PAID whatever the method, and nothing moved: a "Whish" share was
     * a row saying paid, the rider's checklist listed it under "Already paid digitally", and the
     * ledger still booked the whole order as cash collected at the door (RECON-01). Now cash at the
     * door is a promise, a wallet is accepted only where the dev simulator stands in for it — and
     * then as a labelled simulation, still owed at the door — and a wallet nothing can carry is
     * refused, as {@code POST /api/transfers} refuses it.
     */
    @Transactional
    public SplitPlan answer(UUID id, String callerRef, String callerUsername,
                            boolean accept, SplitShare.Method method) {
        SplitPlan plan = read(id, callerRef, callerUsername);
        if (plan.getStatus() != SplitPlan.Status.COLLECTING) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "This split is no longer collecting");
        }
        SplitShare share = plan.getShares().stream()
                .filter(s -> callerUsername.equals(s.getPayeeUsername())
                        && s.getStatus() == SplitShare.Status.PENDING)
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "No pending share of yours on this split"));
        if (!accept) {
            share.decline();
        } else if (method == null || method == SplitShare.Method.HOST_ORDER) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "Pick a payment method");
        } else if (WALLETS.contains(method)) {
            share.commitSimulated(standIn(method));
        } else {
            // CASH_AT_DOOR, or CASH_ON_DELIVERY from a client that sends the transfer name: both
            // are notes handed to the rider, and the checklist has one word for that.
            share.commitCashAtDoor();
        }
        plan.recompute();
        return plan;
    }

    /**
     * The only way a wallet share is accepted today: the dev simulator standing in for it.
     *
     * <p>A real provider is refused rather than trusted, because no flow exists that takes a share's
     * money through it — accepting one would record a payment that never happened, which is the bug.
     */
    private SplitShare.Method standIn(SplitShare.Method wallet) {
        MoneyTransferConnector connector = transfers.connectorFor(
                        TransferMethod.valueOf(wallet.name()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "No provider currently carries " + wallet));
        if (!connector.simulated()) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "A share cannot be paid by " + wallet + " yet; choose cash at the door");
        }
        return wallet;
    }

    /** The host absorbs everything still pending or declined — the "Cover the Rest" button. */
    @Transactional
    public SplitPlan cover(UUID id, String hostRef) {
        SplitPlan plan = requireHost(id, hostRef);
        plan.getShares().stream()
                .filter(s -> s.getStatus() == SplitShare.Status.PENDING
                        || s.getStatus() == SplitShare.Status.DECLINED)
                .forEach(SplitShare::coverByHost);
        plan.recompute();
        return plan;
    }

    @Transactional
    public SplitPlan remind(UUID id, String hostRef) {
        SplitPlan plan = requireHost(id, hostRef);
        plan.extend(Instant.now().plus(REMINDER_EXTENSION));
        return plan;
    }

    @Transactional
    public SplitPlan cancel(UUID id, String hostRef) {
        SplitPlan plan = requireHost(id, hostRef);
        plan.cancel();
        return plan;
    }

    /**
     * The order exists now; the plan closes over it, at the order's own total.
     *
     * <p>Order Manager is asked first, with the host's token: the plan may only close over the
     * host's own order, and the rider will collect that order's total, so the shares are re-priced
     * to add up to it (the host's slice takes the difference — EXPRESS, a zone fee, a code). One
     * order holds one plan: a second would leave the rider two checklists for one door.
     */
    @Transactional
    public SplitPlan attachOrder(UUID id, String hostRef, UUID orderId) {
        SplitPlan plan = requireHost(id, hostRef);
        if (plan.getStatus() != SplitPlan.Status.READY
                && plan.getStatus() != SplitPlan.Status.COLLECTING) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "This split cannot take an order any more");
        }
        OrderManagerClient.OrderSummary order = transfers.order(orderId);
        if (!hostRef.equals(order.customerId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your order");
        }
        BigDecimal orderTotal = Money.usd(order.totalAmount());
        if (orderTotal == null) {
            throw new OrderManagerClient.OrderUnavailableException(
                    "The order could not be confirmed; please try again");
        }
        plans.findByOrderId(orderId)
                .filter(other -> !other.getId().equals(plan.getId()))
                .ifPresent(other -> {
                    throw new ResponseStatusException(HttpStatus.CONFLICT,
                            "That order already has a split");
                });
        if (plan.othersTotal().compareTo(orderTotal) > 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "The friends' shares come to more than the order's total of " + orderTotal);
        }
        plan.closeOver(orderId, orderTotal);
        return plan;
    }

    /** Who is reading an order's plan, which decides how much of it they are shown. */
    public enum Reader {
        /** The host or an invitee: the plan is theirs. */
        MEMBER,
        /** Support, reading any plan. */
        BACKOFFICE,
        /** The rider carrying the order: amounts and whom to collect them from, nothing more. */
        RIDER
    }

    /**
     * An order's plan as one reader may see it. {@code cashOrder} is only known, and only matters,
     * for the {@link Reader#RIDER}: it says whether the door collects the shares.
     */
    public record OrderPlan(SplitPlan plan, Reader reader, boolean cashOrder) {
    }

    /**
     * The plan behind an order — the rider's cash checklist, and the members' summary.
     *
     * <p>It answered anybody who held an order id, and riders see the id of every order on the job
     * board: a rider on another order got 404 for the order and 200 for its plan, with the host's
     * name and username, each friend's, and what each of them pays (RECON-02). Now it answers only
     * the host, an invitee, back office, and the rider Order Manager names on the order — asked
     * with the caller's own token, so its visibility rule decides. Everybody else gets the 404 an
     * order with no plan gets, so the answer does not even say that a plan exists.
     *
     * <p>Not transactional on purpose: the lookup is the repository's own read, the shares come
     * with it (eager), and a rider's check then waits on Order Manager — which it must not do while
     * holding one of this service's five pooled connections.
     */
    public OrderPlan forOrder(UUID orderId, String callerRef, String callerUsername,
                              boolean backoffice) {
        SplitPlan plan = plans.findByOrderId(orderId).orElseThrow(SplitService::noPlan);
        if (backoffice) {
            return new OrderPlan(plan, Reader.BACKOFFICE, false);
        }
        if (isMember(plan, callerRef, callerUsername)) {
            return new OrderPlan(plan, Reader.MEMBER, false);
        }
        OrderManagerClient.OrderSummary order = carriedBy(orderId, callerRef);
        if (order == null) {
            throw noPlan();
        }
        return new OrderPlan(plan, Reader.RIDER, order.cash());
    }

    /**
     * The order, when Order Manager names the caller as its rider; null otherwise — including when
     * it will not show the caller the order at all, or cannot be reached. Refusing is the safe
     * failure here: the rider's payout card still says what the order collects.
     */
    private OrderManagerClient.OrderSummary carriedBy(UUID orderId, String callerRef) {
        try {
            OrderManagerClient.OrderSummary order = transfers.order(orderId);
            return order != null && callerRef.equals(order.riderId()) ? order : null;
        } catch (OrderManagerClient.OrderUnavailableException e) {
            return null;
        }
    }

    private static ResponseStatusException noPlan() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "No split behind that order");
    }

    /**
     * A plan only its host may act on. Anybody else — an invitee included — is told there is no
     * such split, as {@link #read} tells a stranger.
     */
    private SplitPlan requireHost(UUID id, String hostRef) {
        SplitPlan plan = plans.findById(id)
                .filter(p -> p.getHostRef().equals(hostRef))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No such split"));
        plan.expireIfDue(Instant.now());
        return plan;
    }
}

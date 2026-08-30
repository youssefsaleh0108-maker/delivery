package com.delivery.transfer.service;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitPlanRepository;
import com.delivery.transfer.domain.SplitShare;

/**
 * The group-split manager: create, answer, cover, place.
 *
 * <p>Money-first by design: the plan collects every share's commitment and only then is the order
 * worth placing. What "commitment" means per kind of participant: an app user pays through a
 * wallet method or promises cash at the door; a guest IS a door-cash promise; a flake's share is
 * covered by the host with one tap. The host's own share is committed from birth — they are the
 * one placing the order.
 */
@Service
public class SplitService {

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

    @Transactional
    public SplitPlan create(String hostRef, String hostUsername, String hostName,
                            String storeName, SplitPlan.Mode mode, BigDecimal totalUsd,
                            List<NewShare> shares) {
        if (totalUsd == null || totalUsd.signum() <= 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "totalUsd must be positive");
        }
        if (shares == null || shares.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "a split needs at least one share besides the host");
        }
        SplitPlan plan = new SplitPlan(hostRef, hostUsername, hostName, storeName, mode,
                totalUsd, transfers.rate(), Instant.now().plus(WINDOW));

        // The host's own slice: whatever the other shares leave of the total. Committed from
        // birth — the host is the one whose order this is.
        BigDecimal others = shares.stream()
                .map(NewShare::amountUsd)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
        if (others.compareTo(totalUsd) > 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "shares exceed the total");
        }
        SplitShare hostShare = new SplitShare(hostUsername, hostName,
                totalUsd.subtract(others), null);
        hostShare.pay(SplitShare.Method.HOST_ORDER);
        plan.addShare(hostShare);

        for (NewShare s : shares) {
            if (hostUsername.equals(s.username())) {
                continue; // the host cannot owe themselves a second slice
            }
            plan.addShare(new SplitShare(
                    emptyToNull(s.username()), s.name(), s.amountUsd(), s.itemsCount()));
        }
        plan.recompute();
        return plans.save(plan);
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

    @Transactional
    public SplitPlan read(UUID id, String callerRef, String callerUsername) {
        SplitPlan plan = plans.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No such split"));
        boolean host = plan.getHostRef().equals(callerRef);
        boolean invited = plan.getShares().stream()
                .anyMatch(s -> callerUsername.equals(s.getPayeeUsername()));
        if (!host && !invited) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your split");
        }
        plan.expireIfDue(Instant.now());
        return plan;
    }

    /** An invitee answers their own share: pays it through a method, or declines. */
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
        if (accept) {
            if (method == null || method == SplitShare.Method.HOST_ORDER) {
                throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "Pick a payment method");
            }
            share.pay(method);
        } else {
            share.decline();
        }
        plan.recompute();
        return plan;
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

    /** The order exists now; the plan closes over it. */
    @Transactional
    public SplitPlan attachOrder(UUID id, String hostRef, UUID orderId) {
        SplitPlan plan = requireHost(id, hostRef);
        if (plan.getStatus() != SplitPlan.Status.READY
                && plan.getStatus() != SplitPlan.Status.COLLECTING) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "This split cannot take an order any more");
        }
        plan.placed(orderId);
        return plan;
    }

    /** The rider's cash checklist: the plan behind an order, shares and all. */
    @Transactional(readOnly = true)
    public SplitPlan forOrder(UUID orderId) {
        return plans.findByOrderId(orderId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No split behind that order"));
    }

    private SplitPlan requireHost(UUID id, String hostRef) {
        SplitPlan plan = plans.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No such split"));
        if (!plan.getHostRef().equals(hostRef)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your split");
        }
        plan.expireIfDue(Instant.now());
        return plan;
    }
}

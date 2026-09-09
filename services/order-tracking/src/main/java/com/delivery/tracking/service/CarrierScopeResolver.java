package com.delivery.tracking.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.client.CarrierDirectoryClient;
import com.delivery.tracking.domain.CarrierMembership;
import com.delivery.tracking.domain.CarrierMembershipRepository;

/**
 * Whose fleet a caller may see.
 *
 * <p>Every carrier-scoped read in this service — the roster, a rider's live position, the hours
 * columns — turns on one question, and until this class existed the answer came from
 * {@code carrier_membership} alone. That table's only writer infers a rider's fleet from an order
 * that named both. Office staff carry no orders, so no order ever named them, so they never got a
 * row: <strong>every carrier account on the platform was told "you are not a member of any
 * delivery company", from provisioning onwards, on every one of those endpoints.</strong> The
 * console could not see the fleet it exists to run.
 *
 * <p>So on a miss this asks Order Manager, which owns the membership, with the caller's own token,
 * and keeps the answer. The row it writes is a cache of somebody else's fact, and it is treated
 * as one:
 *
 * <ul>
 *   <li>It is <strong>re-validated on a window</strong> ({@code carrier-scope.ttl}). A read cannot
 *       report a departure that happens after it, so a row that stands forever means access
 *       outliving employment — bounded here by how long a stale row is allowed to serve.
 *   <li>When the directory stops placing the caller in a company, the row is
 *       <strong>deleted</strong>. That is what a departure looks like from here, and leaving the
 *       row would keep a former dispatcher watching riders they no longer work with.
 *   <li>An <strong>outage is not a departure</strong>. A directory that cannot be reached leaves
 *       any existing row serving, and refuses only when there is nothing to fall back on — the
 *       poll fails rather than the fleet silently emptying.
 * </ul>
 *
 * <p>Rider rows are never touched. They come from order events and this only ever asks about the
 * caller, whose token is the only one it holds.
 */
@Component
public class CarrierScopeResolver {

    private static final Logger log = LoggerFactory.getLogger(CarrierScopeResolver.class);

    private final CarrierMembershipRepository memberships;
    private final CarrierDirectoryClient directory;
    private final Duration ttl;

    public CarrierScopeResolver(
            CarrierMembershipRepository memberships,
            CarrierDirectoryClient directory,
            @Value("${delivery.tracking.carrier-scope.ttl:15m}") Duration ttl) {
        this.memberships = memberships;
        this.directory = directory;
        this.ttl = ttl;
    }

    /**
     * The fleet this caller belongs to, resolving it from the directory if we do not know yet.
     *
     * <p>Empty means the caller is staff of no delivery company — a platform-employed rider, a
     * customer, or a carrier account that was never attached to one.
     *
     * <p>{@code REQUIRES_NEW} because every caller is inside a read-only transaction: the reads
     * that need this are reads, and the row this writes is a cache, so it commits on its own and
     * does not enlist the caller's transaction in a write it did not ask for.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<UUID> scopeFor(String callerId) {
        Optional<CarrierMembership> known = memberships.findById(callerId);

        if (known.isPresent()) {
            CarrierMembership row = known.get();
            // Only a cached directory answer is re-checked. An ORDER_EVENT row is an inference we
            // could not improve on by asking about somebody else's token, and a MEMBERSHIP row is
            // maintained by the events that own it.
            boolean due = row.getSource() == CarrierMembership.Source.DIRECTORY
                    && row.staleAsOf(Instant.now().minus(ttl));
            if (!due) {
                return Optional.of(row.getCarrierId());
            }
            return revalidate(row);
        }

        return tokenOf(callerId)
                .flatMap(token -> lookUp(callerId, token, null));
    }

    /**
     * The fleet this caller belongs to, or a refusal.
     *
     * @throws PresenceService.NoCarrierException when the caller is staff of no delivery company
     */
    public UUID requireScopeFor(String callerId) {
        return scopeFor(callerId).orElseThrow(() -> new PresenceService.NoCarrierException(
                "You are not a member of any delivery company"));
    }

    /**
     * Re-checks a cached row that has aged past the window.
     *
     * <p>The old value keeps serving whenever the directory cannot be reached — an outage must not
     * empty a console — and the row is removed only on a definite answer that the caller is in no
     * company.
     */
    private Optional<UUID> revalidate(CarrierMembership row) {
        Optional<String> token = tokenOf(row.getUserId());
        if (token.isEmpty()) {
            // Nothing to re-check with. Serving what we have beats refusing a caller we already
            // know: the row is what every other read on this request will use anyway.
            return Optional.of(row.getCarrierId());
        }
        try {
            return lookUp(row.getUserId(), token.get(), row);
        } catch (CarrierDirectoryClient.DirectoryUnavailableException e) {
            log.warn("Could not re-check {}'s delivery company; serving the cached one",
                    row.getUserId());
            return Optional.of(row.getCarrierId());
        }
    }

    /**
     * Asks the directory and records what it said.
     *
     * @param existing the row already held for this caller, or null when there is none
     */
    private Optional<UUID> lookUp(String callerId, String token, CarrierMembership existing) {
        Optional<UUID> answer = directory.companyFor(token);

        if (answer.isEmpty()) {
            if (existing != null) {
                // A departure. The row is the only thing granting sight of that fleet, so it goes.
                log.info("{} is no longer staff of any delivery company; dropping the membership",
                        callerId);
                memberships.delete(existing);
            }
            return Optional.empty();
        }

        UUID company = answer.get();
        if (existing == null) {
            memberships.save(new CarrierMembership(callerId, company,
                    CarrierMembership.Kind.STAFF, CarrierMembership.Source.DIRECTORY));
        } else if (!existing.apply(company, CarrierMembership.Kind.STAFF,
                CarrierMembership.Source.DIRECTORY)) {
            // Unchanged, but confirmed just now — which is what the window is measured from.
            existing.confirmed();
        }
        return Optional.of(company);
    }

    /**
     * The caller's own bearer token, and only ever theirs.
     *
     * <p>The directory answers "which company am I staff of", so it can only be asked about the
     * holder of the token in hand. Anything else — a rider named in a path, a caller resolved on a
     * background thread — has no token here and simply is not looked up, which is why this returns
     * an Optional rather than reaching for a service credential that would answer for anybody.
     */
    private Optional<String> tokenOf(String callerId) {
        // The CARRIER role first, and it is not belt-and-braces. locationOf asks this question
        // about EVERY caller — including the customer watching their own delivery — and without
        // the role check each of those became a cross-service call that Order Manager answers 403
        // to, on a screen a customer refreshes every few seconds. Holding the role does not mean a
        // caller belongs to a company; it means asking is a question worth asking.
        if (!CurrentUser.hasRole("CARRIER")) {
            return Optional.empty();
        }
        return CurrentUser.jwt()
                .filter(jwt -> callerId.equals(jwt.getSubject()))
                .map(Jwt::getTokenValue);
    }
}

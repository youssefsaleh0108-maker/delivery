package com.delivery.onboarding.service;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Comparator;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.domain.AutoApprovalAudit;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecision;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.AutoApprovalSource;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * Which kinds of applicant are let in without a human deciding.
 *
 * <p>The platform was built the other way round — every application waits for a reviewer — and this
 * turns that off per kind. It exists because growth and review are in tension: a rider who applies
 * on Friday evening and is approved on Monday morning has probably signed up with somebody else by
 * Monday morning.
 *
 * <p><strong>What is given up is real and worth stating.</strong> With auto-approval on, the only
 * thing standing between a stranger and a live merchant or rider account is a verified email
 * address. Nobody reads the licence plate; nobody looks at the commercial registration. The papers
 * are still collected and still visible in the backoffice — they are simply no longer a gate. That
 * is a deliberate trade, not an oversight, and it is why this is a recorded decision rather than a
 * deleted branch: the day it needs reversing, it reverses.
 *
 * <p>Per kind, because the risks are not equal. A rider who turns out to be nobody wastes a
 * delivery; a merchant who turns out to be nobody takes a customer's money for food that never
 * existed; a carrier is a company, signing for a fleet and a payout account. Defaults reflect that
 * order, and the safest thing this class can do is refuse to guess: an unknown kind is never
 * automatic.
 *
 * <p><strong>The switch used to be an environment variable, and reversing it took a restart.</strong>
 * That was the honest description of a deploy-time flag, and it was the wrong shape for this
 * decision twice over. Reversing in a hurry meant a pipeline; and the record of who decided that
 * nobody would read merchant applications for six weeks lived in a container spec and somebody's
 * memory. The position now lives in {@code auto_approval_settings}, every change is appended to
 * {@code auto_approval_audit} with the actor and both values, and the backoffice moves it through
 * {@code /api/onboarding/admin/auto-approval}.
 *
 * <p><strong>The @Value settings did not go away — they became the seed.</strong> A kind with no
 * recorded decision is answered by the deployed default, so an environment that has never touched
 * the portal behaves exactly as it did before this table existed. What changes on the first portal
 * decision for a kind is that the deployment default stops mattering <em>for that kind</em>, which
 * is what {@link AutoApprovalSource} reports to the screen so the operator can see which of the two
 * is answering.
 *
 * <p><strong>Nothing is cached, on purpose.</strong> The obvious optimisation — hold the three rows
 * in a field, refresh on write — is wrong here in a way that is easy to miss: it works perfectly on
 * the instance that took the PUT and leaves every other replica serving the old position until it
 * restarts, which is the exact failure this table was built to remove. The read happens once per
 * submitted application, against a primary key on a table of at most three rows, so the cache would
 * buy nothing worth that. If one is ever added, it needs an invalidation that crosses instances.
 *
 * <p>Reading and writing live in one class rather than a policy plus a settings service, because
 * the fallback rule — no row means the configured default — is the thing that must not drift. A
 * separate writer would eventually record its own idea of the default and disagree with the reader
 * about what was in force.
 */
@Component
public class AutoApprovalPolicy {

    private static final Logger log = LoggerFactory.getLogger(AutoApprovalPolicy.class);

    /**
     * Who the audit trail names when nobody decided.
     *
     * <p>Not a person, not blank, and not a reviewer's name borrowed for the purpose. When somebody
     * asks in a year's time who let this merchant onto the platform, the honest answer has to be
     * available, and "the policy did, at this instant" is that answer.
     */
    public static final String AUTOMATIC_REVIEWER = "system:auto-approval";

    /** One kind's position, and whether it is a portal decision or the deployment default. */
    public record KindDecision(boolean automatic, AutoApprovalSource source) {
    }

    /**
     * The whole picture the backoffice screen renders.
     *
     * <p>{@code lastChangedBy} and {@code lastChangedAt} describe the most recent portal decision
     * across all three kinds, and are null together exactly when there has never been one. They are
     * deliberately not per kind: the screen asks "when did somebody last touch this page", and a
     * per-kind timestamp for a kind still answering from CONFIG would have to be invented.
     */
    public record Settings(Map<Kind, KindDecision> byKind, String lastChangedBy,
                           Instant lastChangedAt) {
    }

    /** The deployed defaults, by kind — the seed, consulted only where no decision was recorded. */
    private final Map<Kind, Boolean> configured;

    private final AutoApprovalDecisionRepository decisions;
    private final AutoApprovalAuditRepository audit;

    public AutoApprovalPolicy(
            @Value("${delivery.onboarding.auto-approve.rider:false}") boolean rider,
            @Value("${delivery.onboarding.auto-approve.merchant:false}") boolean merchant,
            @Value("${delivery.onboarding.auto-approve.carrier:false}") boolean carrier,
            AutoApprovalDecisionRepository decisions,
            AutoApprovalAuditRepository audit) {

        Map<Kind, Boolean> defaults = new EnumMap<>(Kind.class);
        defaults.put(Kind.RIDER, rider);
        defaults.put(Kind.MERCHANT, merchant);
        defaults.put(Kind.CARRIER, carrier);
        this.configured = Map.copyOf(defaults);

        this.decisions = decisions;
        this.audit = audit;
    }

    /**
     * Whether an application of this kind is approved on submission.
     *
     * <p>Null is false. A kind the platform gains later is manual until somebody says otherwise,
     * which is the direction a default should fail in — and note that it stays manual whichever way
     * the fallback goes, because a kind that is not in {@link #configured} has no deployed default
     * to inherit either.
     *
     * <p>Read straight through to the store, so a change made in the backoffice governs the very
     * next application submitted, on every instance, with no restart and no cache to invalidate.
     */
    public boolean isAutomatic(Kind kind) {
        if (kind == null) {
            return false;
        }
        return decisions.findById(kind)
                .map(AutoApprovalDecision::isAutomatic)
                .orElseGet(() -> configuredDefault(kind));
    }

    /** For the startup line and for the backoffice to show what is currently in force. */
    public Set<Kind> automaticKinds() {
        Map<Kind, AutoApprovalDecision> recorded = recorded();
        Set<Kind> kinds = EnumSet.noneOf(Kind.class);
        for (Kind kind : Kind.values()) {
            if (inForce(recorded, kind).automatic()) {
                kinds.add(kind);
            }
        }
        return Set.copyOf(kinds);
    }

    /** Every kind's position and where it came from, plus who last changed anything and when. */
    @Transactional(readOnly = true)
    public Settings settings() {
        return settingsFrom(recorded());
    }

    /**
     * Records the backoffice's decision for all three kinds, auditing each one that moves.
     *
     * <p>A kind whose recorded position already matches what was asked for is left alone and leaves
     * no audit row — a trail padded with no-ops is one nobody reads. A kind with <em>no</em>
     * recorded position is written even when the requested value equals the deployment default,
     * because that is not a no-op: it pins the kind to a decision somebody signed for, and a later
     * change to the environment variable will no longer move it. The audit row for that case has
     * the same old and new value and {@code oldSource = CONFIG}, which reads exactly as what
     * happened.
     *
     * <p><strong>The consequence is that the first PUT moves all three kinds to PORTAL</strong>,
     * not only the one the operator dragged. That is deliberate and it is the safe direction: this
     * is a whole-page PUT, so the caller looked at three positions and sent three back, and the
     * deployment must not be able to change one of them underneath a person who just approved what
     * the screen said. It does mean an environment variable stops being consulted the first time
     * anybody opens this screen and saves, which is what {@code source} exists to make visible.
     *
     * <p>The audit row is written in the same transaction as the position it describes, so a
     * history with a gap in it is not possible.
     */
    @Transactional
    public Settings update(boolean rider, boolean merchant, boolean carrier, String changedBy) {
        Map<Kind, Boolean> requested = new EnumMap<>(Kind.class);
        requested.put(Kind.RIDER, rider);
        requested.put(Kind.MERCHANT, merchant);
        requested.put(Kind.CARRIER, carrier);

        Map<Kind, AutoApprovalDecision> recorded = recorded();
        // Seconds, not nanoseconds. Postgres stores microseconds, so an untruncated Instant means
        // the timestamp this method returns differs from the one the next GET reads back; and the
        // API's contract is an ISO-8601 second, which is all the precision a switch a human toggles
        // can honestly claim.
        Instant now = Instant.now().truncatedTo(ChronoUnit.SECONDS);

        for (Map.Entry<Kind, Boolean> entry : requested.entrySet()) {
            Kind kind = entry.getKey();
            boolean wanted = entry.getValue();

            AutoApprovalDecision existing = recorded.get(kind);
            KindDecision before = inForce(recorded, kind);

            // Nothing asked for, nothing recorded — and the "nothing recorded" half matters far
            // more than it looks.
            //
            // The PUT carries all three kinds because the screen shows all three, so an operator
            // who came to switch carriers off also sends back the rider and merchant values they
            // were merely shown. Recording those as portal decisions would quietly take two kinds
            // nobody touched out of the deployment's hands: a later AUTO_APPROVE_MERCHANT=false,
            // shipped in a hurry precisely because something is going wrong, would stop doing
            // anything, and the only remaining way to halt approvals would be a portal that needs
            // a reachable backoffice and a working Keycloak login.
            //
            // So the test is against what is IN FORCE, not against what happens to be in the
            // table. A kind whose position did not move stays answerable to whoever was answerable
            // for it before — which is the same reason V43 seeds no rows at deploy time.
            if (before.automatic() == wanted) {
                continue;
            }

            if (existing == null) {
                recorded.put(kind, decisions.save(
                        new AutoApprovalDecision(kind, wanted, changedBy, now)));
            } else {
                existing.change(wanted, changedBy, now);
                decisions.save(existing);
            }
            audit.save(new AutoApprovalAudit(kind, before.automatic(), before.source(),
                    wanted, changedBy, now));

            if (wanted) {
                // WARN for the same reason the startup line is WARN: this is the platform telling
                // its operator that nobody is reading these applications any more.
                log.warn("{} switched auto-approval ON for {}: applications of this kind are now "
                        + "approved on submission with no human review", changedBy, kind);
            } else {
                log.info("{} switched auto-approval OFF for {}", changedBy, kind);
            }
        }
        return settingsFrom(recorded);
    }

    // ---------------------------------------------------------------- assembling

    private Settings settingsFrom(Map<Kind, AutoApprovalDecision> recorded) {
        Map<Kind, KindDecision> byKind = new EnumMap<>(Kind.class);
        for (Kind kind : Kind.values()) {
            byKind.put(kind, inForce(recorded, kind));
        }
        // The newest recorded row is the last time anybody touched the page. Null when the table is
        // empty, which the contract renders as a null lastChangedBy/lastChangedAt rather than as an
        // invented actor — nobody has changed it, and the screen should say so.
        AutoApprovalDecision newest = recorded.values().stream()
                .max(Comparator.comparing(AutoApprovalDecision::getChangedAt))
                .orElse(null);
        return new Settings(Map.copyOf(byKind),
                newest == null ? null : newest.getChangedBy(),
                newest == null ? null : newest.getChangedAt());
    }

    /** The one fallback rule, in one place: a recorded decision, or else the deployed default. */
    private KindDecision inForce(Map<Kind, AutoApprovalDecision> recorded, Kind kind) {
        AutoApprovalDecision decision = recorded.get(kind);
        return decision == null
                ? new KindDecision(configuredDefault(kind), AutoApprovalSource.CONFIG)
                : new KindDecision(decision.isAutomatic(), AutoApprovalSource.PORTAL);
    }

    /** False for a kind with no configured default, which is how an unknown kind stays manual. */
    private boolean configuredDefault(Kind kind) {
        return configured.getOrDefault(kind, false);
    }

    private Map<Kind, AutoApprovalDecision> recorded() {
        Map<Kind, AutoApprovalDecision> byKind = new EnumMap<>(Kind.class);
        for (AutoApprovalDecision decision : decisions.findAll()) {
            byKind.put(decision.getKind(), decision);
        }
        return byKind;
    }
}

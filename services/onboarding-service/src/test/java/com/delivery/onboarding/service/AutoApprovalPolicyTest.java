package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.AutoApprovalAudit;
import com.delivery.onboarding.domain.AutoApprovalAuditRepository;
import com.delivery.onboarding.domain.AutoApprovalDecision;
import com.delivery.onboarding.domain.AutoApprovalDecisionRepository;
import com.delivery.onboarding.domain.AutoApprovalSource;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Who gets onto the platform without a human deciding.
 *
 * <p>Worth pinning because the failure is silent and expensive in one direction only. A policy that
 * wrongly says "manual" leaves an applicant waiting, and somebody complains. A policy that wrongly
 * says "automatic" puts a stranger on the platform as a live merchant, and nobody notices until
 * money has moved — so every default here is asserted, not assumed.
 *
 * <p>Since the decision became a stored one, two further properties carry the same weight and are
 * pinned below. A kind nobody has decided must still answer with the deployed default, or applying
 * the migration would quietly change what a running environment does. And a decision somebody did
 * make must survive a restart <em>and</em> beat a conflicting environment variable, or the portal
 * would be a switch the next deploy silently flips back.
 */
class AutoApprovalPolicyTest {

    private static final String ACTOR = "keycloak-sub-backoffice";

    /**
     * The store, as a map the fake repositories below read and write.
     *
     * <p>Declared as fields rather than built in {@code @BeforeEach} because the nested classes
     * construct their policy in a field initialiser, which JUnit runs before any callback.
     */
    private final Map<Kind, AutoApprovalDecision> stored = new EnumMap<>(Kind.class);
    private final List<AutoApprovalAudit> trail = new ArrayList<>();

    private final AutoApprovalDecisionRepository decisions = inMemoryDecisions(stored);
    private final AutoApprovalAuditRepository audit = recordingAudit(trail);

    /** A policy over the shared store, with these three as the deployment's configured defaults. */
    private AutoApprovalPolicy policy(boolean rider, boolean merchant, boolean carrier) {
        return new AutoApprovalPolicy(rider, merchant, carrier, decisions, audit);
    }

    private static AutoApprovalDecisionRepository inMemoryDecisions(
            Map<Kind, AutoApprovalDecision> store) {
        AutoApprovalDecisionRepository repository = mock(AutoApprovalDecisionRepository.class);
        when(repository.findById(any())).thenAnswer(
                call -> Optional.ofNullable(store.get(call.<Kind>getArgument(0))));
        when(repository.findAll()).thenAnswer(call -> List.copyOf(store.values()));
        when(repository.save(any(AutoApprovalDecision.class))).thenAnswer(call -> {
            AutoApprovalDecision saved = call.getArgument(0);
            store.put(saved.getKind(), saved);
            return saved;
        });
        return repository;
    }

    private static AutoApprovalAuditRepository recordingAudit(List<AutoApprovalAudit> trail) {
        AutoApprovalAuditRepository repository = mock(AutoApprovalAuditRepository.class);
        when(repository.save(any(AutoApprovalAudit.class))).thenAnswer(call -> {
            AutoApprovalAudit row = call.getArgument(0);
            trail.add(row);
            return row;
        });
        return repository;
    }

    private List<AutoApprovalAudit> auditRowsFor(Kind kind) {
        return trail.stream().filter(row -> row.getKind() == kind).toList();
    }

    private AutoApprovalAudit onlyRowFor(Kind kind) {
        List<AutoApprovalAudit> rows = auditRowsFor(kind);
        assertThat(rows).as("audit rows for %s", kind).hasSize(1);
        return rows.get(0);
    }

    @Nested
    @DisplayName("with nothing configured")
    class Defaults {

        private final AutoApprovalPolicy policy = policy(false, false, false);

        @Test
        @DisplayName("nobody is automatic — the platform reviews by default")
        void everythingIsManual() {
            for (Kind kind : Kind.values()) {
                assertThat(policy.isAutomatic(kind))
                        .as("%s must be manual unless switched on", kind)
                        .isFalse();
            }
            assertThat(policy.automaticKinds()).isEmpty();
        }
    }

    @Nested
    @DisplayName("switched on per kind")
    class PerKind {

        @Test
        @DisplayName("riders and merchants automatic leaves carriers manual")
        void onlyWhatWasAskedFor() {
            AutoApprovalPolicy policy = policy(true, true, false);

            assertThat(policy.isAutomatic(Kind.RIDER)).isTrue();
            assertThat(policy.isAutomatic(Kind.MERCHANT)).isTrue();
            // A carrier signs for a fleet and a payout account. Turning riders on must never carry
            // it along.
            assertThat(policy.isAutomatic(Kind.CARRIER)).isFalse();
        }

        @Test
        @DisplayName("each kind is independent")
        void independent() {
            assertThat(policy(true, false, false).automaticKinds())
                    .containsExactly(Kind.RIDER);
            assertThat(policy(false, true, false).automaticKinds())
                    .containsExactly(Kind.MERCHANT);
            assertThat(policy(false, false, true).automaticKinds())
                    .containsExactly(Kind.CARRIER);
        }
    }

    @Nested
    @DisplayName("with nothing decided in the portal")
    class FallingBackToConfiguration {

        /**
         * The property that makes the migration safe to apply to a live environment: an empty
         * settings table has to behave exactly like the environment variable did on its own.
         */
        @Test
        @DisplayName("the deployed default answers, and reports itself as CONFIG")
        void theConfiguredDefaultIsInForceAndSaysSo() {
            AutoApprovalPolicy policy = policy(true, false, false);

            AutoApprovalPolicy.Settings settings = policy.settings();
            assertThat(settings.byKind().get(Kind.RIDER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(true, AutoApprovalSource.CONFIG));
            assertThat(settings.byKind().get(Kind.MERCHANT))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(false, AutoApprovalSource.CONFIG));
            assertThat(settings.byKind().get(Kind.CARRIER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(false, AutoApprovalSource.CONFIG));

            assertThat(policy.isAutomatic(Kind.RIDER)).isTrue();
        }

        /** Nobody changed it, so the screen must say nobody — not invent an actor or a date. */
        @Test
        @DisplayName("there is no last-changed-by and no last-changed-at")
        void nobodyHasChangedAnything() {
            AutoApprovalPolicy.Settings settings = policy(true, true, true).settings();

            assertThat(settings.lastChangedBy()).isNull();
            assertThat(settings.lastChangedAt()).isNull();
        }
    }

    @Nested
    @DisplayName("decided in the portal")
    class RecordedDecisions {

        @Test
        @DisplayName("each kind is togglable on its own")
        void eachKindMovesAlone() {
            AutoApprovalPolicy policy = policy(false, false, false);

            policy.update(true, false, false, ACTOR);
            assertThat(policy.automaticKinds()).containsExactly(Kind.RIDER);

            policy.update(true, true, false, ACTOR);
            assertThat(policy.automaticKinds())
                    .containsExactlyInAnyOrder(Kind.RIDER, Kind.MERCHANT);

            // And turning one off leaves the other where it was.
            policy.update(false, true, false, ACTOR);
            assertThat(policy.automaticKinds()).containsExactly(Kind.MERCHANT);
        }

        /**
         * The PUT carries all three kinds because the screen shows all three — but only the kinds
         * whose position actually moved become portal decisions.
         *
         * <p>The opposite reading is tempting and was how this worked first: somebody sent three
         * values, so record three. What it costs is the emergency lever. An operator who opens the
         * page to switch carriers off would also freeze rider and merchant into the table, and a
         * later {@code AUTO_APPROVE_MERCHANT=false} — shipped in a hurry, precisely because
         * something is wrong — would stop doing anything at all.
         */
        @Test
        @DisplayName("a write records only the kinds that moved")
        void aWriteRecordsOnlyWhatMoved() {
            AutoApprovalPolicy policy = policy(false, false, false);

            AutoApprovalPolicy.Settings settings = policy.update(true, false, false, ACTOR);

            assertThat(settings.byKind().get(Kind.RIDER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(true, AutoApprovalSource.PORTAL));
            // Asked for as false, which is what the configuration already said. Nothing moved, so
            // nothing is recorded and these two stay the deployment's to change.
            assertThat(settings.byKind().get(Kind.MERCHANT))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(false, AutoApprovalSource.CONFIG));
            assertThat(settings.byKind().get(Kind.CARRIER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(false, AutoApprovalSource.CONFIG));
            assertThat(settings.lastChangedBy()).isEqualTo(ACTOR);
            assertThat(settings.lastChangedAt()).isNotNull();
        }

        /**
         * A restart must not undo a decision that was actually made, and the environment variable
         * must not win it back. The second policy is a fresh instance over the same store with the
         * OPPOSITE configured defaults — both "the service restarted" and "somebody changed the
         * deploy".
         */
        @Test
        @DisplayName("a recorded decision survives a reload and beats a conflicting default")
        void survivesAReloadAndOutranksTheEnvironment() {
            policy(false, false, false).update(true, false, false, ACTOR);

            AutoApprovalPolicy afterRestart = policy(false, true, true);

            assertThat(afterRestart.isAutomatic(Kind.RIDER)).isTrue();
            assertThat(afterRestart.settings().byKind().get(Kind.RIDER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(true, AutoApprovalSource.PORTAL));
            // MERCHANT and CARRIER never moved, so no row was written for them and the newly
            // configured true reaches both. That is the half that keeps a deploy able to change
            // its mind about a kind nobody has touched in the portal.
            assertThat(afterRestart.isAutomatic(Kind.MERCHANT)).isTrue();
            assertThat(afterRestart.isAutomatic(Kind.CARRIER)).isTrue();
            assertThat(afterRestart.automaticKinds())
                    .containsExactlyInAnyOrder(Kind.RIDER, Kind.MERCHANT, Kind.CARRIER);
        }

        /**
         * The property the fix above exists for, stated as the incident it prevents.
         *
         * <p>The deployed box runs with rider and merchant automatic. An operator opens Settings to
         * switch carriers off — and touches nothing else. Later, something goes wrong with merchant
         * signups and a deploy ships {@code AUTO_APPROVE_MERCHANT=false}. That must actually stop
         * merchant approvals.
         */
        @Test
        @DisplayName("switching one kind off leaves the emergency lever working for the others")
        void anUntouchedKindStillAnswersToTheDeployment() {
            // rider=true, merchant=true, carrier=true in the environment; the operator turns
            // carriers off and sends the other two back exactly as the screen showed them.
            policy(true, true, true).update(true, true, false, ACTOR);

            AutoApprovalPolicy afterIncidentDeploy = policy(true, false, true);

            assertThat(afterIncidentDeploy.isAutomatic(Kind.MERCHANT))
                    .as("a deploy must still be able to stop merchant approvals")
                    .isFalse();
            assertThat(afterIncidentDeploy.isAutomatic(Kind.RIDER)).isTrue();
            // The one thing that WAS decided in the portal holds, even though the environment
            // still says carriers are automatic.
            assertThat(afterIncidentDeploy.isAutomatic(Kind.CARRIER)).isFalse();
        }

        /**
         * The other half of that: a kind with no row is still the environment's, even next to kinds
         * that have one. Only reachable through a store written before a kind existed — but it is
         * exactly what the migration leaves behind for a kind added later, and the fallback has to
         * keep working per kind rather than all-or-nothing.
         */
        @Test
        @DisplayName("PORTAL and CONFIG can be in force side by side")
        void aPartlyDecidedStoreFallsBackPerKind() {
            stored.put(Kind.RIDER, new AutoApprovalDecision(Kind.RIDER, false, ACTOR,
                    Instant.parse("2026-08-29T10:11:12Z")));

            AutoApprovalPolicy policy = policy(true, true, false);

            assertThat(policy.settings().byKind().get(Kind.RIDER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(false, AutoApprovalSource.PORTAL));
            assertThat(policy.settings().byKind().get(Kind.MERCHANT))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(true, AutoApprovalSource.CONFIG));
            assertThat(policy.automaticKinds()).containsExactly(Kind.MERCHANT);
        }

        /**
         * The reason nothing is cached. Another replica took the write; this one must not keep
         * approving on the old position until somebody restarts it.
         */
        @Test
        @DisplayName("a change made elsewhere is in force here with no restart")
        void noInstanceServesAStalePosition() {
            AutoApprovalPolicy servingSubmissions = policy(false, false, false);
            assertThat(servingSubmissions.isAutomatic(Kind.RIDER)).isFalse();

            policy(false, false, false).update(true, false, false, ACTOR);

            assertThat(servingSubmissions.isAutomatic(Kind.RIDER)).isTrue();
        }

        @Test
        @DisplayName("the audit row records the old value, the new value and who")
        void theTrailAnswersWhoAndFromWhat() {
            policy(false, false, false).update(true, false, false, ACTOR);

            AutoApprovalAudit row = onlyRowFor(Kind.RIDER);
            assertThat(row.isOldAutomatic()).isFalse();
            assertThat(row.isNewAutomatic()).isTrue();
            assertThat(row.getChangedBy()).isEqualTo(ACTOR);
            assertThat(row.getChangedAt()).isNotNull();
            // The old value came from the deployment, not from an earlier decision, and the row
            // has to say which — otherwise "was it already on?" is unanswerable.
            assertThat(row.getOldSource()).isEqualTo(AutoApprovalSource.CONFIG);
        }

        /**
         * Sending back a value that did not move records nothing, and the kind stays the
         * deployment's.
         *
         * <p>The opposite was true first, on the reading that submitting a value is a decision
         * about it. It was wrong for a reason that only shows up in an incident: the PUT always
         * carries all three kinds, so "I confirmed it" and "I never touched it" arrive as the same
         * request, and treating both as decisions quietly disarms the environment variable for
         * kinds nobody looked at. An audit row that says a person chose something they did not
         * choose is also worse than no row.
         */
        @Test
        @DisplayName("confirming the configured value records nothing and leaves it CONFIG")
        void pinningTheDefaultIsNotADecision() {
            AutoApprovalPolicy policy = policy(true, false, false);

            policy.update(true, false, false, ACTOR);

            assertThat(auditRowsFor(Kind.RIDER))
                    .as("nothing moved, so nothing is recorded")
                    .isEmpty();
            assertThat(policy.settings().byKind().get(Kind.RIDER))
                    .isEqualTo(new AutoApprovalPolicy.KindDecision(true, AutoApprovalSource.CONFIG));
        }

        /** A second change records where it actually came from: the earlier decision, not the env. */
        @Test
        @DisplayName("a later change records the previous decision as its old value")
        void theSecondChangeSaysPortal() {
            AutoApprovalPolicy policy = policy(false, false, false);

            policy.update(true, false, false, ACTOR);
            policy.update(false, false, false, "keycloak-sub-someone-else");

            List<AutoApprovalAudit> riderRows =
                    trail.stream().filter(row -> row.getKind() == Kind.RIDER).toList();
            assertThat(riderRows).hasSize(2);
            AutoApprovalAudit second = riderRows.get(1);
            assertThat(second.isOldAutomatic()).isTrue();
            assertThat(second.isNewAutomatic()).isFalse();
            assertThat(second.getOldSource()).isEqualTo(AutoApprovalSource.PORTAL);
            assertThat(second.getChangedBy()).isEqualTo("keycloak-sub-someone-else");
        }

        /** An audit trail padded with no-ops is one nobody reads. */
        @Test
        @DisplayName("re-sending the same decision writes nothing")
        void anUnchangedPutLeavesNoRow() {
            AutoApprovalPolicy policy = policy(false, false, false);

            policy.update(true, true, true, ACTOR);
            int afterFirst = trail.size();
            policy.update(true, true, true, "keycloak-sub-someone-else");

            assertThat(trail).hasSize(afterFirst);
            // And the page still reports the person who actually decided it.
            assertThat(policy.settings().lastChangedBy()).isEqualTo(ACTOR);
        }
    }

    @Nested
    @DisplayName("edges")
    class Edges {

        @Test
        @DisplayName("a null kind is never automatic")
        void nullIsManual() {
            assertThat(policy(true, true, true).isAutomatic(null)).isFalse();
        }

        /**
         * Still false with every kind switched on in the store, and without the store even being
         * asked — a null kind is a caller bug, and the answer must not depend on what is recorded.
         */
        @Test
        @DisplayName("a null kind is not looked up at all, whatever has been decided")
        void nullIsRefusedBeforeTheStoreIsConsulted() {
            AutoApprovalPolicy policy = policy(true, true, true);
            policy.update(true, true, true, ACTOR);
            verify(decisions, never()).findById(null);

            assertThat(policy.isAutomatic(null)).isFalse();
            verify(decisions, never()).findById(null);
        }

        @Test
        @DisplayName("the reported set cannot be edited from outside")
        void setIsACopy() {
            AutoApprovalPolicy policy = policy(true, false, false);
            var kinds = policy.automaticKinds();
            org.junit.jupiter.api.Assertions.assertThrows(UnsupportedOperationException.class,
                    () -> kinds.add(Kind.CARRIER));
            assertThat(policy.isAutomatic(Kind.CARRIER)).isFalse();
        }

        @Test
        @DisplayName("the automatic reviewer is not a person's name")
        void reviewerIsMarkedAsSystem() {
            // The audit trail has to be able to answer "who approved this" honestly a year later.
            assertThat(AutoApprovalPolicy.AUTOMATIC_REVIEWER)
                    .isNotBlank()
                    .startsWith("system:");
        }

        /** Written by the service, not defaulted by the database, so the PUT can return it. */
        @Test
        @DisplayName("the change is stamped at whole seconds, the precision the contract states")
        void timestampsRoundTripThroughPostgres() {
            AutoApprovalPolicy.Settings settings =
                    policy(false, false, false).update(true, false, false, ACTOR);

            Instant at = settings.lastChangedAt();
            assertThat(at).isNotNull();
            assertThat(at.getNano()).isZero();
        }
    }
}

package com.delivery.onboarding.api;

import java.time.Instant;
import java.util.Map;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.annotation.JsonFormat;

import com.delivery.onboarding.domain.AutoApprovalSource;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.AutoApprovalPolicy;
import com.delivery.platform.security.CurrentUser;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;

/**
 * The backoffice screen for auto-approval: read what is in force, and change it.
 *
 * <p>BACKOFFICE-only at the class level rather than per method, the way
 * {@code ConnectorSettingsController} is annotated, because there is no reading half of this that
 * a narrower role should get: the page's contents are "which kinds of stranger are currently
 * getting onto the platform unreviewed", and that is not a fact to hand out more widely than the
 * ability to change it. Deliberately absent from {@code delivery.security.permit-all} — every one
 * of these requests carries a token or is refused before it reaches this class.
 *
 * <p>The actor written to the audit comes from {@link CurrentUser#requireId()} — the {@code sub}
 * claim on the validated token, the same source every other backoffice endpoint in this service
 * uses for an actor column. It is never taken from the body: a settings page that let the caller
 * name the person who made the change would produce an audit trail worth nothing.
 */
@RestController
@RequestMapping("/api/onboarding/admin/auto-approval")
@PreAuthorize("hasRole('BACKOFFICE')")
public class AutoApprovalSettingsController {

    private final AutoApprovalPolicy policy;

    public AutoApprovalSettingsController(AutoApprovalPolicy policy) {
        this.policy = policy;
    }

    // ---------------------------------------------------------------- shapes

    /**
     * All three kinds, every time — this is a PUT of the whole page, not a PATCH.
     *
     * <p>Boxed {@link Boolean} with {@code @NotNull} rather than a primitive, and the difference
     * matters more than it looks. A primitive {@code boolean} field that the body omits arrives as
     * {@code false}, so a request that forgot to mention merchants would silently switch merchant
     * auto-approval off and report success. Boxed, the omission is null and the request is refused
     * with 400 before anything is written.
     */
    public record UpdateRequest(
            @NotNull Boolean rider,
            @NotNull Boolean merchant,
            @NotNull Boolean carrier) {
    }

    /** One kind as the contract renders it: the position, and which of the two decided it. */
    public record KindView(boolean automatic, String source) {

        static KindView of(AutoApprovalPolicy.KindDecision decision) {
            return new KindView(decision.automatic(), decision.source().name());
        }
    }

    /**
     * The response both endpoints return, in the order the contract states it.
     *
     * <p>{@code lastChangedBy} and {@code lastChangedAt} are null together on a deployment where
     * nobody has ever used this screen — the portal shows "never changed" rather than a made-up
     * actor for a position that is still the environment's.
     */
    public record AutoApprovalView(KindView rider, KindView merchant, KindView carrier,
                                   String lastChangedBy,
                                   /*
                                    * Pinned to a string rather than left to the ambient Jackson
                                    * configuration. Boot's default happens to render an Instant as
                                    * ISO-8601, but that default is one property away from becoming
                                    * an epoch decimal for every date in the service, and the two
                                    * clients that parse this field would break together and
                                    * silently. The contract says a string; this says it too.
                                    */
                                   @JsonFormat(shape = JsonFormat.Shape.STRING)
                                   Instant lastChangedAt) {

        static AutoApprovalView of(AutoApprovalPolicy.Settings settings) {
            Map<Kind, AutoApprovalPolicy.KindDecision> byKind = settings.byKind();
            return new AutoApprovalView(
                    KindView.of(byKind.get(Kind.RIDER)),
                    KindView.of(byKind.get(Kind.MERCHANT)),
                    KindView.of(byKind.get(Kind.CARRIER)),
                    settings.lastChangedBy(),
                    settings.lastChangedAt());
        }
    }

    // ---------------------------------------------------------------- endpoints

    /**
     * What is in force right now, per kind, with {@link AutoApprovalSource} beside each so the
     * screen can distinguish "nobody has decided this and the deployment is answering" from
     * "somebody set it".
     */
    @GetMapping
    public AutoApprovalView read() {
        return AutoApprovalView.of(policy.settings());
    }

    /**
     * Records the decision for all three kinds and answers with the position that resulted.
     *
     * <p>Takes effect on the next application submitted, on every instance, with no restart: the
     * policy reads this store at submission time rather than holding a copy. A kind set to what it
     * already was leaves no audit row; see {@link AutoApprovalPolicy#update}.
     */
    @PutMapping
    public AutoApprovalView update(@Valid @RequestBody UpdateRequest request) {
        return AutoApprovalView.of(policy.update(
                request.rider(), request.merchant(), request.carrier(), CurrentUser.requireId()));
    }
}

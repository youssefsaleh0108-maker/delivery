package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Predicate;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.service.OnboardingService.ApplicationRuleException;

/**
 * An account that already exists asking for a role: to shop, to ride, or to sell.
 *
 * <p>Every other way onto the platform starts with no account. The open application form proves
 * an address with a one-time code, records the application, and only at the end creates the
 * Keycloak account with a passcode. Signing in with Google turns that round: Keycloak creates the
 * account the moment Google vouches for the person, and the question "are you a customer, a rider
 * or a seller?" is answered afterwards, by somebody who is already signed in.
 *
 * <p><strong>The rule this class exists to keep</strong> is that arriving through Google must not
 * be a way around the review. So the partner path here is not a new path at all, only a new front
 * door onto the existing one:
 *
 * <ul>
 *   <li>the application is the same record, in the same queue, walked by the same process
 *       ({@link OnboardingService#startReview});
 *   <li>the account gets exactly what an applicant account gets at the end of the open form — the
 *       live role so every screen works, and APPLICANT beside it so the committing endpoints
 *       (publishing goods, claiming a delivery) refuse until somebody decides;
 *   <li>auto-approval is consulted in exactly one way, through {@link AutoApprovalPolicy}, and acts
 *       through the reviewer's own {@link OnboardingService#approve(UUID, String, boolean)}, so the
 *       APPLICANT revoke, the partner record and the decision notice all happen the way they do for
 *       everybody else.
 * </ul>
 *
 * <p>Everything acts on the caller's own token subject. Nothing here accepts an account id from a
 * request body, so there is no id to tamper with — the same shape as every {@code /mine} endpoint.
 */
@Service
public class AccountApplicationService {

    private static final Logger log = LoggerFactory.getLogger(AccountApplicationService.class);

    /** The realm role that grants nothing and makes every committing endpoint refuse. */
    static final String APPLICANT = "APPLICANT";

    /** The shopper's role. Nothing on the customer path here can grant anything else. */
    static final String CUSTOMER = "CUSTOMER";

    private final OnboardingApplicationRepository applications;
    private final ApplicationIntake intake;
    private final OnboardingService onboarding;
    private final KeycloakAdminClient keycloak;
    private final AutoApprovalPolicy autoApproval;

    public AccountApplicationService(OnboardingApplicationRepository applications,
                                     ApplicationIntake intake,
                                     OnboardingService onboarding,
                                     KeycloakAdminClient keycloak,
                                     AutoApprovalPolicy autoApproval) {
        this.applications = applications;
        this.intake = intake;
        this.onboarding = onboarding;
        this.keycloak = keycloak;
        this.autoApproval = autoApproval;
    }

    /**
     * Who is asking, as their validated token describes them.
     *
     * <p>Built by the controller from the token and nothing else. {@code holdsRole} is the token's
     * own answer rather than a set copied out of it, so the service asks the same question every
     * {@code @PreAuthorize} on the platform asks.
     *
     * @param userRef       the Keycloak {@code sub} — the only account anything here acts on
     * @param email         the {@code email} claim, which is the address the application is sent to
     * @param emailVerified the {@code email_verified} claim. True for a Google account because the
     *                      realm's Google provider is {@code trustEmail}: Google has already proved
     *                      the address, which is the proof the open form gets from a one-time code
     */
    public record Caller(String userRef, String email, boolean emailVerified,
                         Predicate<String> holdsRole) {
    }

    /**
     * What the wizard collected. The same answers the open form sends, minus the email and its
     * proof, which come from the account.
     *
     * @param businessName ignored for a rider, whose "business" is simply who they are — the open
     *                     form sends their name in both fields for the same reason
     */
    public record Answers(Kind kind, String businessName, String contactName,
                          String contactPhone, String phoneVerificationToken, String notes,
                          Map<String, Object> details, UUID targetProviderId) {
    }

    /**
     * @param created false when the caller already had this application and it was handed back —
     *                the idempotent answer to a second tap, a retry, or a returning user
     */
    public record Result(OnboardingApplication application, boolean created) {
    }

    /**
     * A refusal this path knows by name, so the app can put it in the reader's own words.
     *
     * <p>The message stays English — it is what the logs read, and what any client that shows it
     * as it comes will show. The {@link #code()} is what the app translates. The Google path is
     * used in Arabic as much as in English, and before the code existed an Arabic-speaking
     * applicant who was refused read the reason in English.
     *
     * <p>The codes are part of the API: the app matches on these exact strings, and a code it does
     * not know falls back to the message. Rename one and the app quietly goes back to English.
     */
    public static class AccountRuleException extends ApplicationRuleException {

        /** Riding and selling only; a delivery company applies through its own form. */
        public static final String KIND_NOT_OFFERED = "kind-not-offered";

        /** The account already holds a live partner role, of any kind, and has nothing to resume. */
        public static final String ALREADY_PARTNER = "already-partner";

        /** The account already has an application of another kind. One account carries one. */
        public static final String OTHER_APPLICATION = "other-application";

        /** The token's address is missing, or its identity provider did not vouch for it. */
        public static final String EMAIL_UNVERIFIED = "email-unverified";

        public static final String NAME_MISSING = "name-missing";

        public static final String SHOP_NAME_MISSING = "shop-name-missing";

        private final String code;

        public AccountRuleException(String code, String message) {
            super(message);
            this.code = code;
        }

        public String code() {
            return code;
        }
    }

    // ---------------------------------------------------------------- the partner path

    /**
     * Applies to ride or to sell on behalf of the signed-in caller's own account.
     *
     * <p><strong>Idempotent.</strong> One account carries one application (the database says so, on
     * {@code applicant_user_ref}), so a caller who already has one gets it back rather than a second
     * row. While it is undecided the access it should carry is re-asserted, which is what lets a
     * retry finish a first attempt that recorded the application and then lost Keycloak half way.
     * Asking for the other kind is refused with a reason rather than silently ignored.
     *
     * <p><strong>Not a way to get a role back, nor to lose one.</strong> An account that already
     * holds a live partner role — of any kind, not only the one asked for — is refused, and a
     * partner whose record sits on the provisioned column — approved before applicants chose a
     * passcode, and possibly suspended since — is found by that column and handed their existing
     * application. Neither can apply again to be granted a role the platform took away, and no
     * working partner is handed an APPLICANT that would stop them trading.
     *
     * @throws ApplicationRuleException for anything the caller can act on: the wrong kind, a
     *         missing shop name, an address nobody proved, a second application of another kind
     * @throws KeycloakAdminClient.ProvisioningException when the record is in but the account's
     *         roles could not be set — retrying finishes the job
     */
    public Result apply(Caller caller, Answers answers) {
        Kind kind = answers.kind();
        if (kind != Kind.RIDER && kind != Kind.MERCHANT) {
            // Riding and selling are the two things the app's role question offers. A delivery
            // company signs for a fleet and a payout account, and applies through the company form
            // with its own documents — a Google sign-in is not the place to start that.
            throw new AccountRuleException(AccountRuleException.KIND_NOT_OFFERED,
                    "Only riding and selling can be applied for from a signed-in account");
        }

        Optional<OnboardingApplication> existing = existingFor(caller.userRef());
        if (existing.isPresent()) {
            return resume(caller.userRef(), existing.get(), kind);
        }

        Optional<Kind> trading = tradingAs(caller);
        if (trading.isPresent()) {
            // Any live partner role, not only the one asked for. APPLICANT is realm-wide: granted to
            // a shop that asked to ride, it stops that shop publishing exactly as it would stop a
            // rider claiming — and a rejection never takes APPLICANT off again, so a declined second
            // application would leave a working partner blocked for good. Accounts that trade with
            // no onboarding row are real: the realm's seeded users, and anybody given a role by
            // hand. One account carries one partner role, which is also what resume() says.
            throw new AccountRuleException(AccountRuleException.ALREADY_PARTNER,
                    alreadyTradesAs(trading.get()));
        }

        String email = caller.email() == null ? "" : caller.email().trim();
        if (email.isEmpty() || !caller.emailVerified()) {
            // The address is where the decision is sent. The open form will not take an
            // application without a proved one, and neither will this.
            throw new AccountRuleException(AccountRuleException.EMAIL_UNVERIFIED,
                    "Your account's email address has not been verified, so we cannot take an "
                            + "application on it yet");
        }

        String contactName = answers.contactName() == null ? "" : answers.contactName().trim();
        if (contactName.isEmpty()) {
            throw new AccountRuleException(AccountRuleException.NAME_MISSING, "Tell us your name");
        }
        String businessName = kind == Kind.RIDER
                ? contactName
                : answers.businessName() == null ? "" : answers.businessName().trim();
        if (businessName.isEmpty()) {
            throw new AccountRuleException(AccountRuleException.SHOP_NAME_MISSING,
                    "Tell us the name of your shop");
        }

        OnboardingApplication application;
        try {
            // details is applicant-supplied and holds bank details — into the record and nowhere
            // else, exactly as on the open path.
            application = intake.recordForAccount(caller.userRef(), kind, businessName,
                    contactName, email, Instant.now(), answers.contactPhone(),
                    answers.phoneVerificationToken(), answers.notes(), answers.details(),
                    answers.targetProviderId());
        } catch (IllegalArgumentException e) {
            // The domain's own refusals — a shop naming a delivery company, say.
            throw new ApplicationRuleException(e.getMessage());
        } catch (ApplicationRuleException e) {
            // Two taps racing each other: the other one won the insert. Its application is this
            // caller's application, so hand it back rather than an error about it.
            Optional<OnboardingApplication> raced = applications.findByApplicantUserRef(caller.userRef());
            if (raced.isPresent() && raced.get().getKind() == kind) {
                return new Result(raced.get(), false);
            }
            throw e;
        }

        onboarding.startReview(application);
        grantApplicantAccess(caller.userRef(), kind);
        log.info("Account {} applied as {} (application {})",
                caller.userRef(), kind, application.getReference());

        return new Result(autoApproveIfAutomatic(application), true);
    }

    /**
     * The caller's application, from either column that can hold their account.
     *
     * <p>The applicant column first: it is the newer path and the one this class writes.
     */
    private Optional<OnboardingApplication> existingFor(String userRef) {
        Optional<OnboardingApplication> asApplicant = applications.findByApplicantUserRef(userRef);
        if (asApplicant.isPresent()) {
            return asApplicant;
        }
        return applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(userRef);
    }

    /**
     * The partner kind whose live role the caller already holds, if any — asked of the token.
     *
     * <p>Every kind, not just the one being applied for: see the guard in {@link #apply}.
     */
    private static Optional<Kind> tradingAs(Caller caller) {
        for (Kind held : Kind.values()) {
            if (caller.holdsRole().test(held.liveRole())) {
                return Optional.of(held);
            }
        }
        return Optional.empty();
    }

    private static String alreadyTradesAs(Kind held) {
        return switch (held) {
            case RIDER -> "This account already rides with YouDrop";
            case MERCHANT -> "This account already sells on YouDrop";
            case CARRIER -> "This account already runs a delivery company on YouDrop";
        };
    }

    /**
     * A caller who already has an application. Idempotent for the same kind, refused for another.
     *
     * <p>A decided application is returned exactly as it is, with no role touched. Re-asserting
     * APPLICANT on an approved partner would take away what approval gave them, and on a rejected
     * one it would change nothing worth changing.
     */
    private Result resume(String userRef, OnboardingApplication existing, Kind asked) {
        if (existing.getKind() != asked) {
            throw new AccountRuleException(AccountRuleException.OTHER_APPLICATION,
                    existing.getKind() == Kind.RIDER
                            ? "This account already has an application to ride with YouDrop"
                            : existing.getKind() == Kind.MERCHANT
                                    ? "This account already has an application to sell on YouDrop"
                                    : "This account already has an application as a delivery "
                                            + "company");
        }
        if (existing.isDecided()) {
            return new Result(existing, false);
        }
        grantApplicantAccess(userRef, existing.getKind());
        return new Result(autoApproveIfAutomatic(existing), false);
    }

    /**
     * Gives the account what an applicant account holds: APPLICANT, then the live role.
     *
     * <p><strong>The order is the safety property, not a detail.</strong> The live role on its own
     * is full committing power — publish, claim, carry. APPLICANT beside it is what the committing
     * endpoints refuse on. Granting APPLICANT first means that a failure between the two calls
     * leaves an account holding APPLICANT and nothing else, which can do nothing; the other order
     * would leave, for as long as nobody noticed, a rider nobody approved.
     *
     * <p>Both grants are idempotent in Keycloak, which is what lets {@link #resume} call this again.
     */
    private void grantApplicantAccess(String userRef, Kind kind) {
        try {
            keycloak.grantRealmRole(userRef, APPLICANT);
            keycloak.grantRealmRole(userRef, kind.liveRole());
        } catch (KeycloakAdminClient.ProvisioningException e) {
            throw e;
        } catch (RuntimeException e) {
            // A transport failure from the admin API. The application is recorded and the retry
            // finishes this, so say that rather than surfacing a stack of HTTP detail.
            log.error("Could not set the applicant roles on account {}", userRef, e);
            throw new KeycloakAdminClient.ProvisioningException(
                    "Your application is in, but we could not finish setting up your account. "
                            + "Please try again.");
        }
    }

    /**
     * Approves through the reviewer's own path when the policy says nobody needs to look.
     *
     * <p>The same decision {@code OnboardingService.createApplicantAccount} makes at the end of the
     * open form, taken at the equivalent moment: once the account exists and holds APPLICANT. It
     * goes through the service's proxy, so the approval gets its own transaction and a failure
     * inside it rolls back that approval alone — the application then simply stays in the queue,
     * which is the honest outcome, and the account keeps APPLICANT.
     */
    private OnboardingApplication autoApproveIfAutomatic(OnboardingApplication application) {
        if (application.isDecided() || !autoApproval.isAutomatic(application.getKind())) {
            return application;
        }
        try {
            OnboardingApplication approved = onboarding.approve(
                    application.getId(), AutoApprovalPolicy.AUTOMATIC_REVIEWER, true);
            log.info("Application {} auto-approved for a signed-in account ({} is automatic)",
                    approved.getReference(), application.getKind());
            return approved;
        } catch (RuntimeException e) {
            log.error("Auto-approval failed for {}; it stays in the review queue",
                    application.getReference(), e);
            return application;
        }
    }

    // ---------------------------------------------------------------- the customer path

    /**
     * Makes the caller's own account a customer.
     *
     * <p>Not reviewed, for the reason customer sign-up is not: nobody waits for approval to order
     * dinner. What it shares with sign-up is the one condition sign-up enforces — an address
     * somebody proved — because CUSTOMER is also what the transfer and split endpoints check, and
     * money should not move on an account whose address nobody vouched for.
     *
     * <p>Idempotent: granting a role an account already holds changes nothing in Keycloak. It
     * grants CUSTOMER and nothing else, whatever the caller already holds.
     */
    public void becomeCustomer(Caller caller) {
        String email = caller.email() == null ? "" : caller.email().trim();
        if (email.isEmpty() || !caller.emailVerified()) {
            throw new AccountRuleException(AccountRuleException.EMAIL_UNVERIFIED,
                    "Your account's email address has not been verified, so it cannot shop yet");
        }
        if (caller.holdsRole().test(CUSTOMER)) {
            return;
        }
        try {
            keycloak.grantRealmRole(caller.userRef(), CUSTOMER);
        } catch (KeycloakAdminClient.ProvisioningException e) {
            throw e;
        } catch (RuntimeException e) {
            log.error("Could not grant CUSTOMER to account {}", caller.userRef(), e);
            throw new KeycloakAdminClient.ProvisioningException(
                    "We could not finish setting up your account just now. Please try again.");
        }
        log.info("Account {} is now a customer", caller.userRef());
    }
}

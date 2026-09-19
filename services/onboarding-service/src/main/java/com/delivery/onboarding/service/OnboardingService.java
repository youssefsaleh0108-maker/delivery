package com.delivery.onboarding.service;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.camunda.bpm.engine.task.Task;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;
import com.delivery.onboarding.domain.PartnerEditEntry;
import com.delivery.onboarding.domain.PartnerEditEntryRepository;
import com.delivery.onboarding.service.AccountApplicationService.AccountRuleException;

/**
 * Applications to join, and the decisions made on them.
 *
 * <p>The engine owns the sequence; this owns the record. Keeping them apart matters because the
 * record is what a reviewer, an auditor and the applicant all read, and none of them should have to
 * query a workflow engine to find out what happened.
 */
@Service
public class OnboardingService {

    private static final String PROCESS_KEY = "partner-onboarding";

    /** What an undecided applicant's account holds beside the role applied for, and loses on approval. */
    private static final String APPLICANT = "APPLICANT";

    private static final Logger log = LoggerFactory.getLogger(OnboardingService.class);

    private final OnboardingApplicationRepository applications;
    private final ApplicationIntake intake;
    private final VerificationService verifications;
    private final ServiceProviderAnswers services;
    private final RuntimeService runtime;
    private final TaskService tasks;
    private final KeycloakAdminClient keycloak;
    private final ApplicantDocumentService documents;
    private final AutoApprovalPolicy autoApproval;

    /**
     * Backoffice's corrections to a record, read for one thing here: whether the contact email is
     * still the address the applicant proved (see {@link #onTheProvedAddress}).
     */
    private final PartnerEditEntryRepository edits;

    /**
     * Where an automatic approval runs: a transaction of its own, begun after the applicant's sign-in
     * committed. See {@link #autoApproveIfAutomatic} for why it is a template here.
     */
    private final TransactionTemplate approvals;

    public OnboardingService(OnboardingApplicationRepository applications,
                             ApplicationIntake intake,
                             VerificationService verifications,
                             ServiceProviderAnswers services,
                             RuntimeService runtime, TaskService tasks,
                             KeycloakAdminClient keycloak,
                             ApplicantDocumentService documents,
                             AutoApprovalPolicy autoApproval,
                             PlatformTransactionManager transactionManager,
                             PartnerEditEntryRepository edits) {
        this.applications = applications;
        this.intake = intake;
        this.verifications = verifications;
        this.services = services;
        this.runtime = runtime;
        this.tasks = tasks;
        this.keycloak = keycloak;
        this.documents = documents;
        this.autoApproval = autoApproval;
        this.edits = edits;
        this.approvals = new TransactionTemplate(transactionManager);
        this.approvals.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);

        if (!autoApproval.automaticKinds().isEmpty()) {
            // At WARN, on purpose. This is the platform telling its operator that nobody is reading
            // applications for these kinds — a thing worth noticing in a log somebody skims, and
            // worth being able to point at when the question is asked later.
            //
            // It is the state at boot and nothing more. Backoffice can move this at runtime now
            // (see AutoApprovalPolicy), so a later change logs its own WARN there and this line
            // must not be read as the whole story — auto_approval_audit is.
            log.warn("Auto-approval is ON for {}: these applications are approved on submission "
                    + "with no human review", autoApproval.automaticKinds());
        }
    }

    /** Thrown when an application cannot be accepted or decided as asked. */
    public static class ApplicationRuleException extends RuntimeException {
        public ApplicationRuleException(String message) {
            super(message);
        }
    }

    /**
     * Thrown when a carrier reaches for a company that is not theirs.
     *
     * <p>Separate from the rule exception because it answers 403 rather than 422: this is not an
     * application in the wrong state, it is somebody asking about a business they do not run.
     */
    public static class NotYourCompanyException extends RuntimeException {
        public NotYourCompanyException(String message) {
            super(message);
        }
    }

    /**
     * Thrown when a signed-in caller has no application of their own.
     *
     * <p>404 rather than 422, because the applicant-facing endpoints address the application as
     * {@code /applications/mine} — a caller with none is asking about a resource that is not there,
     * not making a request that broke a rule. It also covers the approved merchant whose
     * application was cleaned up: there is nothing here for them, and the app should be showing
     * them their shop.
     */
    public static class NoApplicationException extends RuntimeException {
        public NoApplicationException(String message) {
            super(message);
        }
    }

    /**
     * Thrown when an applicant's sign-in could not be made for a reason on the platform's side:
     * Keycloak unreachable, refusing this service's own token, or failing half way; the record not
     * saving.
     *
     * <p>503 with {@link #CODE}, never the bare 500 it used to be — which the app, having no words for
     * it, showed as "That did not go through". Nothing the applicant typed is wrong, and the same call
     * a minute later is the whole remedy, which {@link #createApplicantAccount} makes safe.
     */
    public static class SignInUnavailableException extends RuntimeException {

        /** Part of the API: the app matches on this exact string. */
        public static final String CODE = "sign-in-unavailable";

        public SignInUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * What the applicant showed at the passcode step to prove the application is theirs.
     *
     * <p>The account-setup ticket the submission answered with, or — once that is lost or expired — a
     * code answered on the application's address in the last half hour. Either is spent with the
     * sign-in it sets up ({@link ApplicationIntake#attachApplicantAccount}).
     *
     * @param emailToken the email proof when that is what was shown; null for the ticket
     */
    public record SignInProof(String emailToken) {

        static final SignInProof TICKET = new SignInProof(null);

        /** Never the token: a record's generated toString would put it in any log that printed one. */
        @Override
        public String toString() {
            return emailToken == null ? "SignInProof[ticket]" : "SignInProof[email code]";
        }
    }

    // ---------------------------------------------------------------- applying

    /**
     * Records an application and starts its review.
     *
     * <p>Deliberately NOT transactional. The write commits first, in {@link ApplicationIntake}, and
     * only then is the engine asked to start a review — so a process that fails to start leaves a
     * recorded application a reviewer can decide by hand, which is what the applicant's reference
     * has to keep meaning. Holding both in one transaction looked like it did that and did the
     * opposite: the engine's failure marks the transaction rollback-only, and catching it merely
     * moves the error to commit time, where it takes the application with it.
     *
     * <p>Not transactional for a second reason as well: an application to offer services is checked
     * against Product Service here, before the intake's transaction takes a connection from the pool
     * (see {@link ApplicationIntake} for what holding one across that wait could do). This door is
     * open to anybody, so before Product Service hears about a services application its proofs are
     * looked at without being spent ({@code requireProofs}): a made-up token is refused on one read
     * of this service's own table and costs no call to another service. Nothing is spent until the
     * intake, together with the insert, after every check has passed.
     *
     * <p>A rider applying to a delivery company is checked the same way, against Order Manager: the
     * company has to be hiring, and its region is what the application records in place of any area
     * the app sent (see {@link CompanyRiderAnswers}). The proofs are looked at first for the same
     * reason, so a made-up application costs Order Manager nothing either.
     *
     * @return the application and its account-setup ticket, which the submitter alone is answered
     *         with — the passcode step asks for it ({@link #createApplicantAccount})
     */
    public ApplicationIntake.Recorded submit(OnboardingApplication.Kind kind, String businessName,
                                             String contactName, String contactEmail,
                                             String emailVerificationToken, String contactPhone,
                                             String phoneVerificationToken, String notes,
                                             Map<String, Object> details,
                                             UUID targetProviderId) {

        if (ServiceProviderAnswers.isServices(details)
                || CompanyRiderAnswers.namesACompany(kind, targetProviderId)) {
            requireProofs(contactEmail, emailVerificationToken, contactPhone, phoneVerificationToken);
        }
        // details is applicant-supplied and holds bank details — it goes into the record and
        // nowhere else: not into a log line, not into a process variable.
        ServiceProviderAnswers.Checked checked = services.checked(kind, details, targetProviderId);

        ApplicationIntake.Recorded recorded;
        try {
            recorded = intake.record(
                    kind, businessName, contactName, contactEmail, emailVerificationToken,
                    contactPhone, phoneVerificationToken, notes, checked, targetProviderId);
        } catch (IllegalArgumentException e) {
            // "Choose the delivery company you want to ride for" is something the applicant can act
            // on; an unhandled 500 is not.
            throw new ApplicationRuleException(e.getMessage());
        }
        OnboardingApplication application = recorded.application();

        startReview(application);

        // By id, never by reference, here and on every line below. The reference no longer opens
        // anything that acts — the passcode step asks for the ticket — but it still ties a line to
        // a person for anybody holding a support email, which a log has no reason to. The ticket
        // itself never reaches a log at all.
        log.info("Application {} submitted: {} as {}",
                application.getId(), application.getBusinessName(), kind);
        return recorded;
    }

    /**
     * A services application's proofs, looked at without spending them — before Product Service is
     * asked anything about it.
     *
     * <p>Only for a services application, the one whose checks leave this service. Any other
     * application is judged on its own fields alone before the intake, where spending the proof says
     * precisely what is wrong with one. The reason given here is plainer, "verify again", because
     * what matters is that a caller with no valid proof is answered from this service's own table.
     *
     * <p>A blank token is refused without a lookup: it proves nothing.
     */
    private void requireProofs(String contactEmail, String emailToken,
                               String contactPhone, String phoneToken) {
        if (!proved(emailToken, Channel.EMAIL, contactEmail)) {
            throw new VerificationService.VerificationException(
                    "That email has not been verified. Please verify it again.");
        }
        if (contactPhone != null && !contactPhone.isBlank()
                && !proved(phoneToken, Channel.PHONE, contactPhone)) {
            throw new VerificationService.VerificationException(
                    "That phone number has not been verified. Please verify it again.");
        }
    }

    private boolean proved(String token, Channel channel, String destination) {
        return token != null && !token.isBlank()
                && verifications.isVerified(token, channel, destination);
    }

    /**
     * Starts the review process for an application whose row is already committed.
     *
     * <p>Tolerant, for the reason {@link #submit} gives: the write has already committed, so a
     * process that fails to start leaves a recorded application a reviewer can decide by hand.
     *
     * <p>Public, and its own method, so that the signed-in path —
     * {@link AccountApplicationService}, where somebody who already has an account applies to ride
     * or sell — starts a review in exactly the way the open form does. A second copy of this block
     * would be a second place for the process key or its variables to drift, and the first person
     * to notice would be a reviewer whose queue never showed the application's review task.
     */
    public void startReview(OnboardingApplication application) {
        try {
            String instanceId = runtime.startProcessInstanceByKey(
                    PROCESS_KEY,
                    application.getId().toString(),
                    Map.of("applicationId", application.getId().toString(),
                            "kind", application.getKind().name(),
                            "businessName", application.getBusinessName())).getId();
            intake.attachProcess(application.getId(), instanceId);
            application.startedAs(instanceId);
        } catch (Exception e) {
            // Left SUBMITTED with no process — and now genuinely left, because the row is already
            // committed. It still shows in the reviewer's queue and can be decided by hand: a lost
            // applicant is a worse outcome than a process nobody started.
            log.error("Application {} was recorded but its review process did not start",
                    application.getId(), e);
        }
    }

    /**
     * Approves an application the policy says nobody needs to look at.
     *
     * <p>Deliberately the SAME path a reviewer takes — {@link #approve(UUID, String, boolean)} —
     * rather than a shortcut that sets the status directly. Everything downstream of an approval
     * hangs off that method: the role grant, the APPLICANT revoke, the process completion, the
     * decision notification. A second way to approve would be a second place for all of it to be
     * forgotten, and the first person to notice would be an approved merchant who cannot publish.
     *
     * <p>Document issues are acknowledged, because with auto-approval on there has by definition
     * been no review — the papers usually have not even been uploaded yet, since the wizard sends
     * them after the account exists. That acknowledgement is not silent: what was outstanding is
     * written onto the application beside {@code system:auto-approval}, so the record says plainly
     * that nothing was checked and by what.
     *
     * <p><strong>In a transaction of its own, begun after the sign-in committed.</strong> The
     * approval's steps run inside it — the process's Keycloak role changes and, for a rider,
     * order-manager attaching them to their company — so when one fails this transaction rolls back
     * and nothing else does. It is opened with {@link #approvals} (REQUIRES_NEW) because
     * {@code approve} is on this same class: a call to it from here goes straight past the proxy that
     * applies its {@code @Transactional}, and would run with no transaction at all, the APPROVED row
     * committing on its own before a step failed. app-notification's ShopChatService opens its
     * transaction with a template for the same reason; the signed-in path gets the same effect by
     * calling {@code approve} on this bean from another one.
     *
     * <p>A failure leaves the application SUBMITTED, which is exactly right: it lands in the
     * reviewer's queue and a human can decide it. The applicant is not lost, their sign-in is made,
     * and the platform has not half-approved anybody. Nothing reaches the applicant — this never
     * throws.
     *
     * <p>What a rollback cannot undo is Keycloak. The process takes APPLICANT away as its last step
     * that can fail ({@code ReleaseApplicant}, after the rider is attached to their company), so an
     * approval failing at the attach or anywhere before leaves APPLICANT where it was. Only a failure
     * after the release — the decision's own commit — could leave an account able to act on an
     * application nobody approved, and {@link #keepApplicantWhileUndecided} puts it back.
     */
    private void autoApproveIfAutomatic(OnboardingApplication application) {
        try {
            if (application.isDecided() || !autoApproval.isAutomatic(application.getKind())) {
                return;
            }
            OnboardingApplication approved = approvals.execute(status -> approve(
                    application.getId(), AutoApprovalPolicy.AUTOMATIC_REVIEWER, true));
            log.info("Application {} auto-approved once its sign-in existed ({} is automatic)",
                    approved.getId(), application.getKind());
        } catch (RuntimeException e) {
            log.error("Auto-approval failed for {}; it stays in the review queue",
                    application.getId(), e);
            keepApplicantWhileUndecided(application);
        }
    }

    /**
     * Puts APPLICANT back on an account whose automatic approval failed, while nobody has decided its
     * application.
     *
     * <p>A backstop now, not the plan: the process releases APPLICANT only after every step that can
     * fail, so the only failure this still answers is one after the release, such as the commit. It
     * stays because Keycloak is outside every transaction, and a backstop that grants a role the
     * account already holds changes nothing.
     *
     * <p>Only while undecided, read again from the database: a reviewer who approved it meanwhile took
     * APPLICANT away on purpose, and putting it back would stop a partner who has just been let in.
     * Nobody is waiting on an answer from it, so a failure is logged — loudly, because that account
     * may be able to act before anybody approves it.
     */
    private void keepApplicantWhileUndecided(OnboardingApplication application) {
        String userRef = application.getApplicantUserRef();
        try {
            boolean undecided = applications.findById(application.getId())
                    .map(stored -> !stored.isDecided())
                    .orElse(false);
            if (userRef != null && undecided) {
                keycloak.grantRealmRole(userRef, APPLICANT);
            }
        } catch (RuntimeException e) {
            log.error("Application {} is back in the review queue, but APPLICANT could not be put back "
                    + "on account {}, which may be able to act before anybody approves it",
                    application.getId(), userRef, e);
        }
    }

    // ---------------------------------------------------------------- reviewing

    private static final List<OnboardingApplication.Status> OPEN = List.of(
            OnboardingApplication.Status.SUBMITTED, OnboardingApplication.Status.IN_REVIEW);

    /**
     * The platform's queue.
     *
     * <p>Rider applications are excluded: they are addressed to a delivery company, and showing
     * them here too would mean two reviewers on one decision, with the platform picking somebody
     * else's staff whenever it got there first.
     */
    @Transactional(readOnly = true)
    public List<OnboardingApplication> queue() {
        return applications.findByTargetProviderIdIsNullAndStatusInOrderByCreatedAtAsc(OPEN);
    }

    /** One company's own rider applications, open ones only. */
    @Transactional(readOnly = true)
    public List<OnboardingApplication> queueFor(UUID providerId) {
        return applications.findByTargetProviderIdAndStatusInOrderByCreatedAtAsc(providerId, OPEN);
    }

    /** The same company's full history, so a decision made last month is still answerable. */
    @Transactional(readOnly = true)
    public List<OnboardingApplication> allFor(UUID providerId) {
        return applications.findByTargetProviderIdOrderByCreatedAtAsc(providerId);
    }

    /**
     * Checks an application is this company's to decide, before they decide it.
     *
     * <p>The id in the path is supplied by the caller, so without this a carrier could approve a
     * rider who applied to a competitor — and, worse, attach them to their own fleet.
     */
    @Transactional(readOnly = true)
    public OnboardingApplication requireBelongsTo(UUID applicationId, UUID providerId) {
        OnboardingApplication application = applications.findById(applicationId)
                .orElseThrow(() -> new ApplicationRuleException("No such application"));
        if (application.getTargetProviderId() == null
                || !application.getTargetProviderId().equals(providerId)) {
            // Deliberately the same wording as a missing application: which riders applied to a
            // competitor is that competitor's business, not something to confirm by guessing ids.
            throw new ApplicationRuleException("No such application");
        }
        return application;
    }

    @Transactional(readOnly = true)
    public List<OnboardingApplication> all() {
        return applications.findAllByOrderByCreatedAtDesc();
    }

    @Transactional(readOnly = true)
    public Optional<OnboardingApplication> byReference(String reference) {
        return applications.findByReference(reference);
    }

    @Transactional(readOnly = true)
    public Optional<OnboardingApplication> byId(UUID id) {
        return applications.findById(id);
    }

    @Transactional
    public OnboardingApplication approve(UUID id, String reviewer) {
        return approve(id, reviewer, false);
    }

    /**
     * Approves an application, which is a separate decision from its documents.
     *
     * <p>The two are kept apart on purpose. A reviewer may have the commercial registration on the
     * desk in front of them, or know that a licence was refused for glare on the photograph and
     * that the applicant is perfectly acceptable — refusing the approval outright would leave them
     * only one way to record the decision they have actually made, which is to approve a document
     * they have not verified. That is a worse record than an approval that says what was
     * outstanding.
     *
     * <p>So it is possible, and it is not silent. With documents outstanding this refuses with 422
     * and names them, and only goes ahead when the caller says explicitly that they know — at which
     * point what was outstanding is written onto the application, permanently, next to who decided
     * it.
     *
     * @param acknowledgeDocumentIssues the reviewer has seen the outstanding documents and means to
     *                                  approve anyway
     */
    @Transactional
    public OnboardingApplication approve(UUID id, String reviewer, boolean acknowledgeDocumentIssues) {
        OnboardingApplication application = require(id);

        String outstanding = documents.outstandingSummary(id);
        if (outstanding != null && !acknowledgeDocumentIssues) {
            throw new DocumentIssuesOutstandingException(
                    "This application still has documents that were not approved (" + outstanding
                            + "). Approve them, or confirm you mean to approve regardless.",
                    outstanding);
        }

        application.approve(reviewer, outstanding);
        // Flushed here, before anything leaves this service. The row's version is checked by this
        // UPDATE, so a write that landed since the application was read (a sign-in being recorded,
        // another reviewer's decision) fails now, while nothing has happened yet. Left to the commit,
        // the check ran after the engine had granted roles in Keycloak, attached a rider to their
        // company in Order Manager, taken APPLICANT away and told the applicant — and the 409 then
        // left all of that done for an application nobody had decided. From here to the commit the
        // row stays locked, so no other write can get in between.
        applications.saveAndFlush(application);
        completeReview(application, true);

        if (outstanding == null) {
            log.info("{} approved application {}", reviewer, application.getId());
        } else {
            // WARN, and it names what was overridden. This is the line somebody goes looking for
            // when a KYC decision is questioned months later.
            log.warn("{} approved application {} over outstanding documents: {}",
                    reviewer, application.getId(), outstanding);
        }
        return application;
    }

    /**
     * Thrown when an approval would go past documents nobody accepted.
     *
     * <p>Its own type rather than a plain rule violation because the caller's next move is
     * different: this is not "you cannot", it is "say that you mean it", and the portal has to be
     * able to tell those apart to show a confirmation rather than an error.
     */
    public static class DocumentIssuesOutstandingException extends RuntimeException {

        private final String outstanding;

        public DocumentIssuesOutstandingException(String message, String outstanding) {
            super(message);
            this.outstanding = outstanding;
        }

        /** The machine-readable summary, e.g. {@code "NATIONAL_ID=REJECTED"}. */
        public String getOutstanding() {
            return outstanding;
        }
    }

    /**
     * Gives an applicant a way in while their application is being decided.
     *
     * <p>Creates the Keycloak account, records it against the application, and leaves the decision
     * untouched — the account holds APPLICANT beside the role applied for until somebody approves.
     *
     * <p><strong>The reference names the application; it does not prove it is yours.</strong> There
     * is no caller identity yet, and the reference used to stand in for one — "160 bits, handed to one
     * person". It was never only theirs: back office reads it on every application, a delivery
     * company on every rider applying to it (the company's listing and its portal print it), and it
     * rides in this very path, which access logs keep. So a company could set its own passcode on an
     * applicant's unfinished sign-in, or on the leftover account a failed attempt left stamped for the
     * application, and then approve the rider it had just signed in as.
     *
     * <p>So this takes a secret as well ({@link #requireProof}), and judges it before anything about
     * the application is answered and before Keycloak is asked anything: the account-setup ticket the
     * submission answered with, or a code answered on the application's address in the last half
     * hour. Neither is in a URL, and neither is logged. An app too old to send one is refused in words
     * that tell its user to update ({@code sign-in-proof-missing}); a ticket that is wrong, spent or
     * late, or a proof that is stale, is {@code sign-in-proof-rejected}, and the app asks for a code.
     *
     * <p>The address on the application was proved with a code at submission, and that is checked
     * rather than assumed, because backoffice can correct a contact email without any code
     * ({@link #onTheProvedAddress}): an application whose address changed since it was proved gets no
     * sign-in at all, and neither does one somebody already decided.
     *
     * <p><strong>Deliberately NOT transactional</strong>, for the reason {@link #submit} is not. The
     * sign-in is recorded by {@link ApplicationIntake#attachApplicantAccount}, which commits on its
     * own, and only then is auto-approval tried, in a transaction of its own. They used to share one:
     * an approval step that failed marked it rollback-only, the catch logged the failure, and the
     * commit threw UnexpectedRollbackException — so the applicant was told their sign-in could not be
     * set up, the record lost the account, and Keycloak kept it, and the next try met a 409 and failed
     * too. Nor is any transaction open while Keycloak is asked something, so a slow Keycloak holds no
     * pooled connection.
     *
     * <p><strong>Nothing here ends in an unexplained 500.</strong> An address that belongs to another
     * account is refused with {@code account-exists}; a sign-in already recorded, with
     * {@code sign-in-exists}, so the app sends the applicant to sign in. Anything on the platform's
     * side — Keycloak unreachable or refusing this service's token, the record not saving — is logged
     * here with its cause and answers {@code sign-in-unavailable}, and trying again is safe: an
     * account a failed attempt created is taken up by the next one ({@link #resumableAccount}), and
     * the ticket or proof is spent only by the attempt that records the sign-in.
     *
     * @param accountTicket the ticket the submission answered with, or null
     * @param emailProof    a proof from {@code POST /verifications/confirm} on the application's
     *                      address, or null — what an applicant whose ticket is gone sends instead
     */
    public void createApplicantAccount(String reference, String password, String accountTicket,
                                       String emailProof) {
        OnboardingApplication application = null;
        OnboardingApplication recorded;
        try {
            application = applications.findByReference(reference)
                    .orElseThrow(() -> new ApplicationRuleException("No application with that reference"));
            SignInProof proof = requireProof(application, accountTicket, emailProof);
            recorded = recordSignIn(application, password, proof);
        } catch (ApplicationRuleException e) {
            throw e;
        } catch (RuntimeException e) {
            // The id, never the reference — see submit.
            log.error("The sign-in for application {} could not be set up",
                    application == null ? "(not read)" : application.getId(), e);
            throw new SignInUnavailableException(
                    "Your sign-in could not be set up just now. Please try again in a minute.", e);
        }
        log.info("Applicant account created for application {}", recorded.getId());

        // Auto-approval fires HERE, not at submission, and the difference is the whole feature
        // working.
        //
        // Approving at submit time meant the decision landed before this account existed, so
        // ProvisionAccount took its no-applicant branch and created a partner account with a
        // password nobody had been told. The applicant then arrived at this method to choose the
        // passcode they had just typed, and Keycloak refused a second account on the same address —
        // leaving them approved, provisioned, and unable to sign in. Every status field said
        // success.
        //
        // Approving once the account exists takes the other branch: the role is granted to the
        // account they are already holding a passcode for, and APPLICANT is revoked. An application
        // whose applicant never chooses a passcode simply stays in the queue, which is the honest
        // outcome — there is nobody to approve yet.
        autoApproveIfAutomatic(recorded);
    }

    /**
     * The applicant's proof that this application is theirs: the first thing judged, before anything
     * about the application is answered and before Keycloak is asked anything.
     *
     * <p>A valid ticket is enough, and so is a fresh proof for the application's address when the
     * ticket is not; a caller holding neither has shown nothing but the reference, which is not a
     * secret. One answer about the application itself does come from here, to a ticket's holder only:
     * a ticket that is this application's and was spent by the sign-in the application now records is
     * the retry of an attempt whose answer was lost, or the second of two taps, and it is told
     * {@code sign-in-exists} — the same answer it gets when it arrives a moment earlier, before the
     * first attempt recorded anything.
     */
    private SignInProof requireProof(OnboardingApplication application, String accountTicket,
                                     String emailProof) {
        OnboardingApplication.TicketCheck ticket =
                application.checkAccountTicket(accountTicket, Instant.now());
        if (ticket == OnboardingApplication.TicketCheck.VALID) {
            return SignInProof.TICKET;
        }
        if (emailProof != null && !emailProof.isBlank()
                && verifications.isFreshlyVerified(emailProof, Channel.EMAIL,
                        application.getContactEmail(), OnboardingApplication.ACCOUNT_TICKET_LIFETIME)) {
            return new SignInProof(emailProof);
        }
        if (ticket == OnboardingApplication.TicketCheck.SPENT
                && application.getApplicantUserRef() != null) {
            throw signInExists();
        }
        boolean showedNothing = (accountTicket == null || accountTicket.isBlank())
                && (emailProof == null || emailProof.isBlank());
        throw showedNothing ? proofMissing() : proofRejected();
    }

    /**
     * Makes the applicant's account — or takes up the one an earlier attempt left — and records it
     * against their application. Returns the application as committed.
     *
     * <p>The refusals come first, in this order, and none of them touches Keycloak:
     * <ol>
     *   <li><strong>A sign-in already recorded</strong> is {@code sign-in-exists}. First because it is
     *       the answer to a retry whose earlier answer was lost — and that earlier attempt may have
     *       auto-approved the application since, which must not turn "sign in" into "decided".
     *   <li><strong>A decided application</strong> gets no sign-in: an approved partner has one, and a
     *       refused applicant has nothing left to wait on.
     *   <li><strong>An address changed since it was proved</strong> gets none either. Everything below
     *       stands on that proof — the account is made {@code emailVerified}, and an account already
     *       on the address may be taken up — so an address typed in by backoffice cannot carry it.
     * </ol>
     */
    private OnboardingApplication recordSignIn(OnboardingApplication application, String password,
                                               SignInProof proof) {
        if (application.getApplicantUserRef() != null) {
            throw signInExists();
        }
        if (application.isDecided()) {
            throw applicationDecided();
        }
        if (!onTheProvedAddress(application)) {
            throw new AccountRuleException(AccountRuleException.EMAIL_CHANGED,
                    "The email address on this application was changed after it was verified, so a "
                            + "sign-in cannot be set up for it. Please contact support.");
        }

        String userRef;
        try {
            // The same mapping approval and suspension use — see Kind.liveRole for why it is one
            // mapping. Granted now so they can explore what they applied for; APPLICANT rides
            // alongside it until somebody decides. Stamped with this application's id, which is how
            // a retry will know the account for its own if this attempt stops half way.
            userRef = keycloak.createApplicant(
                    application.getContactEmail(),
                    firstNameOf(application.getContactName()),
                    lastNameOf(application.getContactName()),
                    application.getKind().liveRole(),
                    password,
                    application.getId());
        } catch (KeycloakAdminClient.AccountExistsException e) {
            return takeUpAndRecord(application, password, proof);
        }

        // Made just now, with the live role: if the record does not take it, the role goes.
        return record(application, userRef, proof, true);
    }

    /**
     * Whether the application's contact email is still the address its applicant answered a code on.
     *
     * <p>Backoffice can correct a contact email with no code at all ({@code PartnerManagementService
     * .edit}), and every correction leaves a row in the edit trail — the only way the address
     * changes. So the first contactEmail row's old value is the address the application came in
     * with, the proved one; with no row, the address on file still is. Compared as Keycloak compares
     * addresses, ignoring case, so a correction that only changed the case is no change at all.
     */
    private boolean onTheProvedAddress(OnboardingApplication application) {
        return edits.findFirstByApplicationIdAndFieldOrderByCreatedAtAsc(
                        application.getId(), PartnerEditEntry.Field.contactEmail.name())
                .map(first -> first.getOldValue() != null
                        && first.getOldValue().trim().equalsIgnoreCase(application.getContactEmail().trim()))
                .orElse(true);
    }

    /**
     * Keycloak's 409, answered: takes up the account an earlier attempt at this sign-up left, and
     * records it — or refuses with {@code account-exists}, touching nothing.
     *
     * <p>Should the record then refuse the account after all — another application recorded it in
     * the meantime, this one got a different sign-in, or a reviewer decided it — the live role the
     * take-up granted is taken back before the refusal is passed on (see {@link #record}).
     */
    private OnboardingApplication takeUpAndRecord(OnboardingApplication application, String password,
                                                  SignInProof proof) {
        String userRef = resumableAccount(application).orElseThrow(OnboardingService::accountExists);
        boolean grantedLiveRole = takeUp(userRef, application, password);
        return record(application, userRef, proof, grantedLiveRole);
    }

    /**
     * Records the account against the application ({@link ApplicationIntake#attachApplicantAccount})
     * — or, when that does not happen, takes back the live role this attempt granted before the
     * failure is passed on.
     *
     * <p>An account holds its live role on the strength of the record naming it, so an account the
     * record did not take is left with APPLICANT alone, which grants nothing. The case that made this
     * matter is a reviewer's rejection landing while the passcode was being set: the account was made
     * with the live role, the attach found the application decided — or lost to the rejection's
     * commit on the row's version — and the rejected applicant was left holding the role. A failure
     * on the platform's side takes it back too; the retry that finishes the sign-in grants it again.
     *
     * <p>A conflict on the version is read again before it is answered. Two taps racing each other
     * both bring the same account, and the one that lost the write finds the account recorded by the
     * other: that is success, and the role stays. A decision is said as {@code application-decided};
     * anything else is worth another try, and answers {@code sign-in-unavailable}.
     *
     * @param grantedLiveRole whether this attempt gave the account the live role it did not hold
     */
    private OnboardingApplication record(OnboardingApplication application, String userRef,
                                         SignInProof proof, boolean grantedLiveRole) {
        RuntimeException failure;
        try {
            return intake.attachApplicantAccount(application.getId(), userRef, proof);
        } catch (OptimisticLockingFailureException conflict) {
            Optional<OnboardingApplication> now = applications.findById(application.getId());
            if (now.isPresent() && userRef.equals(now.get().getApplicantUserRef())) {
                return now.get();
            }
            failure = now.isPresent() && now.get().isDecided() ? applicationDecided() : conflict;
        } catch (RuntimeException notRecorded) {
            failure = notRecorded;
        }
        if (grantedLiveRole) {
            withdrawGrantedRole(userRef, application);
        }
        throw failure;
    }

    /** The refusal for an address that already has an account which is not this sign-up's own. */
    static AccountRuleException accountExists() {
        return new AccountRuleException(AccountRuleException.ACCOUNT_EXISTS,
                "An account already uses this email address. Sign in with it, or apply with a "
                        + "different email.");
    }

    /** The refusal for a second sign-in on one application; the app sends the applicant to sign in. */
    static AccountRuleException signInExists() {
        return new AccountRuleException(AccountRuleException.SIGN_IN_EXISTS,
                "That application already has a sign-in. Sign in with its email address and the "
                        + "passcode you chose.");
    }

    /** The refusal for an application somebody decided: a sign-in is no longer made for it. */
    static AccountRuleException applicationDecided() {
        return new AccountRuleException(AccountRuleException.APPLICATION_DECIDED,
                "This application has already been decided, so a sign-in can no longer be set up "
                        + "for it here.");
    }

    /**
     * The refusal for a passcode step that showed only the reference.
     *
     * <p>In practice an app from before the ticket, which shows this sentence as it comes — so the
     * sentence is the instruction that helps its user.
     */
    static AccountRuleException proofMissing() {
        return new AccountRuleException(AccountRuleException.SIGN_IN_PROOF_MISSING,
                "This version of the app can no longer finish setting up a sign-in. Please update "
                        + "the app and try again.");
    }

    /** The refusal for a ticket that is wrong, spent or late, or an email proof that is stale. */
    static AccountRuleException proofRejected() {
        return new AccountRuleException(AccountRuleException.SIGN_IN_PROOF_REJECTED,
                "That confirmation has expired or was already used. Confirm your email address "
                        + "again with a new code to finish setting up your sign-in.");
    }

    /**
     * The account an earlier, unfinished attempt at this same sign-up left in Keycloak — when that is
     * what holds this application's address.
     *
     * <p>Keycloak's 409 says only that some account has the address, and taking an account up sets
     * its passcode, so this must be certain the account is the one this sign-up made. What an account
     * holds cannot say so: an account whose rights come from groups or client roles shows no realm
     * role, and neither does an ordinary Google sign-in that has not chosen what it is yet. So all of
     * these must hold, and anything else is somebody's account, refused and left untouched:
     * <ul>
     *   <li><strong>It is stamped for this application</strong>, by id. Only {@link
     *       KeycloakAdminClient#createApplicant} writes the stamp — the user profile lets nobody but an
     *       admin see or edit it — and it writes it for the application it is making the account for.
     *       No stamp is anybody else's account; so is one made before the stamp existed, which
     *       backoffice removes or the applicant signs up again beside.
     *   <li><strong>Nobody has signed in to it through Google.</strong> An account linked to an
     *       identity provider is a sign-in somebody uses, whatever made it.
     *   <li><strong>No application names it</strong>, as applicant or as provisioned partner. An
     *       account an application already records belongs to that application.
     * </ul>
     * The address itself was checked before Keycloak was asked anything: it is still the one the
     * applicant proved ({@link #onTheProvedAddress}).
     *
     * <p>Except that the application recording it may be <em>this</em> one. That is a second tap, or a
     * retry, arriving after the first recorded the account it made — after this attempt read the
     * application and saw no sign-in. The sign-in is made, and made for this applicant: it is
     * {@code sign-in-exists}, which the app answers by signing in. It used to be read as somebody
     * else's account and refused with {@code account-exists}, which tells the applicant the address
     * is taken — by the sign-in they had just made.
     */
    private Optional<String> resumableAccount(OnboardingApplication application) {
        Optional<String> found = keycloak.findUserIdByEmail(application.getContactEmail());
        if (found.isEmpty()) {
            return Optional.empty();
        }
        String userRef = found.get();

        Optional<OnboardingApplication> recordedBy = applications.findByApplicantUserRef(userRef);
        if (recordedBy.isPresent() && recordedBy.get().getId().equals(application.getId())) {
            throw signInExists();
        }

        String refusal = null;
        if (!keycloak.applicationStampOf(userRef)
                .map(application.getId().toString()::equals).orElse(false)) {
            refusal = "it is not stamped for this application";
        } else if (keycloak.isLinkedToIdentityProvider(userRef)) {
            refusal = "it is linked to an identity provider";
        } else if (recordedBy.isPresent()
                || applications.findFirstByProvisionedUserRefOrderByCreatedAtDesc(userRef).isPresent()) {
            refusal = "an application already records it";
        }
        if (refusal != null) {
            log.info("Application {} met account {} on its address and left it alone: {}",
                    application.getId(), userRef, refusal);
            return Optional.empty();
        }
        return found;
    }

    /**
     * Finishes what the earlier attempt started on the account {@link #resumableAccount} found: the
     * two roles, APPLICANT first as at creation, then the passcode the applicant has just chosen — the
     * one they are about to sign in with, whatever the first attempt was given.
     *
     * @return whether it granted the live role, which the account did not hold before — what
     *         {@link #withdrawGrantedRole} takes back if the record then does not take the account
     */
    private boolean takeUp(String userRef, OnboardingApplication application, String password) {
        String liveRole = application.getKind().liveRole();
        boolean heldLiveRole = keycloak.realmRolesOf(userRef).contains(liveRole);
        keycloak.grantRealmRole(userRef, APPLICANT);
        keycloak.grantRealmRole(userRef, liveRole);
        keycloak.resetPassword(userRef, password);
        log.warn("Application {} took up account {}, which an earlier attempt at its sign-up created "
                + "and never recorded", application.getId(), userRef);
        return !heldLiveRole;
    }

    /**
     * Takes back the live role this attempt granted — by making the account, or by taking it up —
     * once the record did not take the account it was for.
     *
     * <p>The record refuses when another application got to the account first, this one got a
     * different sign-in, or somebody decided the application meanwhile; it fails when the platform
     * does. Either way this application's role has no business on an account nothing records.
     * APPLICANT stays, on purpose: it grants nothing, and an application that did record the account
     * may be relying on it — taking it off could leave that application's own live role with nothing
     * holding it back. Nobody is waiting on this, so a failure is logged, loudly, for somebody to
     * finish by hand.
     */
    private void withdrawGrantedRole(String userRef, OnboardingApplication application) {
        String liveRole = application.getKind().liveRole();
        try {
            keycloak.revokeRealmRole(userRef, liveRole);
            log.warn("Application {} could not record account {}; took back the {} this attempt "
                    + "granted", application.getId(), userRef, liveRole);
        } catch (RuntimeException e) {
            log.error("Application {} could not record account {}, and the {} this attempt granted "
                    + "could not be taken back: remove it from that account by hand",
                    application.getId(), userRef, liveRole, e);
        }
    }

    /** What a signed-in applicant is shown about their own application. */
    @Transactional(readOnly = true)
    public Optional<OnboardingApplication> forApplicant(String userRef) {
        return applications.findByApplicantUserRef(userRef);
    }

    /**
     * Splits a name somebody typed into one box. Crude on purpose: Keycloak wants two fields and
     * the form asks for one, so this is a presentation guess rather than a fact.
     */
    private static String firstNameOf(String contactName) {
        String trimmed = contactName == null ? "" : contactName.trim();
        int space = trimmed.indexOf(' ');
        return space < 0 ? trimmed : trimmed.substring(0, space);
    }

    private static String lastNameOf(String contactName) {
        String trimmed = contactName == null ? "" : contactName.trim();
        int space = trimmed.indexOf(' ');
        return space < 0 ? "" : trimmed.substring(space + 1).trim();
    }

    /**
     * Declines an application, and takes back the role its applicant was exploring with.
     *
     * <p>An applicant's account holds the role applied for from the moment they chose a passcode, so
     * they can look around while they wait (APPLICANT beside it stops them acting). A no ends the
     * waiting, so the live role goes; APPLICANT stays, granting nothing and still letting them read
     * their application and why it was declined.
     *
     * <p>Inside the transaction and before the engine tells them, on purpose — the pattern
     * suspension follows. If Keycloak refuses, the rejection rolls back and is never announced, so the
     * record cannot claim a decision whose access change did not happen; the reviewer tries again.
     *
     * <p>The decision is written to the database first, and flushed, so that somebody else's write
     * since the application was read fails before Keycloak or the engine is asked anything. Both
     * decisions work this way; see {@link #approve(UUID, String, boolean)}.
     */
    @Transactional
    public OnboardingApplication reject(UUID id, String reviewer, String reason) {
        OnboardingApplication application = require(id);
        try {
            application.reject(reviewer, reason);
        } catch (IllegalArgumentException e) {
            throw new ApplicationRuleException(e.getMessage());
        }
        // Flushed before Keycloak or the engine hears of it, for the reason approve gives: a
        // version conflict has to surface while nothing has been done, not at the commit, after
        // the role was taken and the applicant told.
        applications.saveAndFlush(application);
        withdrawLiveRoleOnRejection(application);
        completeReview(application, false);
        log.info("{} declined application {}: {}", reviewer, application.getId(), reason);
        return application;
    }

    /**
     * Removes the live role from a declined applicant's account, if the account holds it.
     *
     * <p>Only the applicant's own account: an undecided application has no provisioned one, and
     * whoever applied without choosing a passcode has no account to change.
     */
    private void withdrawLiveRoleOnRejection(OnboardingApplication application) {
        String userRef = application.getApplicantUserRef();
        if (userRef == null) {
            return;
        }
        String liveRole = application.getKind().liveRole();
        if (keycloak.realmRolesOf(userRef).contains(liveRole)) {
            keycloak.revokeRealmRole(userRef, liveRole);
        }
    }

    /**
     * Hands the decision to the engine, which does the rest.
     *
     * <p>Tolerates a missing task rather than failing the decision. An application whose process
     * never started still has to be decidable — the decision is the thing that matters, and the
     * provisioning it would have triggered is recoverable by hand in a way a stuck reviewer is not.
     */
    private void completeReview(OnboardingApplication application, boolean approved) {
        if (application.getProcessInstanceId() == null) {
            log.warn("Application {} has no process; the decision is recorded but nothing will be "
                    + "provisioned automatically", application.getId());
            return;
        }
        Task task = tasks.createTaskQuery()
                .processInstanceId(application.getProcessInstanceId())
                .taskDefinitionKey("review")
                .singleResult();
        if (task == null) {
            log.warn("Application {} has no review task waiting; it may already have been decided",
                    application.getId());
            return;
        }
        tasks.complete(task.getId(), Map.of("approved", approved));
    }

    private OnboardingApplication require(UUID id) {
        OnboardingApplication application = applications.findById(id)
                .orElseThrow(() -> new ApplicationRuleException("No such application"));
        if (application.isDecided()) {
            throw new ApplicationRuleException(
                    "This application was already " + application.getStatus().name().toLowerCase());
        }
        return application;
    }
}

package com.delivery.onboarding.service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.camunda.bpm.engine.task.Task;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.domain.OnboardingApplicationRepository;

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

    private static final Logger log = LoggerFactory.getLogger(OnboardingService.class);

    private final OnboardingApplicationRepository applications;
    private final ApplicationIntake intake;
    private final RuntimeService runtime;
    private final TaskService tasks;
    private final KeycloakAdminClient keycloak;
    private final ApplicantDocumentService documents;

    public OnboardingService(OnboardingApplicationRepository applications,
                             ApplicationIntake intake,
                             RuntimeService runtime, TaskService tasks,
                             KeycloakAdminClient keycloak,
                             ApplicantDocumentService documents) {
        this.applications = applications;
        this.intake = intake;
        this.runtime = runtime;
        this.tasks = tasks;
        this.keycloak = keycloak;
        this.documents = documents;
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
     */
    public OnboardingApplication submit(OnboardingApplication.Kind kind, String businessName,
                                        String contactName, String contactEmail,
                                        String emailVerificationToken, String contactPhone,
                                        String phoneVerificationToken, String notes,
                                        Map<String, Object> details,
                                        UUID targetProviderId) {

        OnboardingApplication application;
        try {
            // details is applicant-supplied and holds bank details — it goes into the record and
            // nowhere else: not into a log line, not into a process variable.
            application = intake.record(
                    kind, businessName, contactName, contactEmail, emailVerificationToken,
                    contactPhone, phoneVerificationToken, notes, details, targetProviderId);
        } catch (IllegalArgumentException e) {
            // "Choose the delivery company you want to ride for" is something the applicant can act
            // on; an unhandled 500 is not.
            throw new ApplicationRuleException(e.getMessage());
        }

        try {
            String instanceId = runtime.startProcessInstanceByKey(
                    PROCESS_KEY,
                    application.getId().toString(),
                    Map.of("applicationId", application.getId().toString(),
                            "kind", kind.name(),
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

        log.info("Application {} submitted: {} as {}",
                application.getReference(), application.getBusinessName(), kind);
        return application;
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
        applications.save(application);
        completeReview(application, true);

        if (outstanding == null) {
            log.info("{} approved application {}", reviewer, application.getReference());
        } else {
            // WARN, and it names what was overridden. This is the line somebody goes looking for
            // when a KYC decision is questioned months later.
            log.warn("{} approved application {} over outstanding documents: {}",
                    reviewer, application.getReference(), outstanding);
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
     * untouched — the account holds APPLICANT and nothing else until somebody approves.
     *
     * <p>Keyed on the reference rather than on a token, for the same reason the status lookup is:
     * there is no caller identity yet. The reference is 160 bits, was handed to one person, and the
     * address on the application was already proved with a code, so this cannot mint an account on
     * an address the applicant does not control.
     */
    @Transactional
    public void createApplicantAccount(String reference, String password) {
        OnboardingApplication application = applications.findByReference(reference)
                .orElseThrow(() -> new ApplicationRuleException("No application with that reference"));

        if (application.getApplicantUserRef() != null) {
            throw new ApplicationRuleException("That application already has a sign-in");
        }

        // The same mapping approval and suspension use — see Kind.liveRole for why it is one
        // mapping. Granted now so they can explore what they applied for; APPLICANT rides
        // alongside it until somebody decides.
        String role = application.getKind().liveRole();

        String userRef = keycloak.createApplicant(
                application.getContactEmail(),
                firstNameOf(application.getContactName()),
                lastNameOf(application.getContactName()),
                role,
                password);

        application.applicantAccountCreated(userRef);
        applications.save(application);
        log.info("Applicant account created for application {}", application.getReference());
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

    @Transactional
    public OnboardingApplication reject(UUID id, String reviewer, String reason) {
        OnboardingApplication application = require(id);
        try {
            application.reject(reviewer, reason);
        } catch (IllegalArgumentException e) {
            throw new ApplicationRuleException(e.getMessage());
        }
        applications.save(application);
        completeReview(application, false);
        log.info("{} declined application {}: {}", reviewer, application.getReference(), reason);
        return application;
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
                    + "provisioned automatically", application.getReference());
            return;
        }
        Task task = tasks.createTaskQuery()
                .processInstanceId(application.getProcessInstanceId())
                .taskDefinitionKey("review")
                .singleResult();
        if (task == null) {
            log.warn("Application {} has no review task waiting; it may already have been decided",
                    application.getReference());
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

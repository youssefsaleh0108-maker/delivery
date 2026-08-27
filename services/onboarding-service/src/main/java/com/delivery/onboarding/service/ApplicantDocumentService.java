package com.delivery.onboarding.service;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.domain.ApplicantDocument;
import com.delivery.onboarding.domain.ApplicantDocumentRepository;
import com.delivery.onboarding.domain.DocumentKind;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;

/**
 * Identity and vehicle documents: upload, replacement, and a reviewer's verdict on each.
 *
 * <p>The upload is the same three-step flow the catalog uses for product images (see
 * {@code ProductImageService}), and it is worth being explicit that this is a deliberate reuse
 * rather than a coincidence:
 *
 * <ol>
 *   <li>The applicant asks for a presigned PUT. Their ownership of the application is checked
 *       <em>here</em>, before any URL exists.</li>
 *   <li>The client PUTs the bytes <strong>straight to MinIO</strong>. A scan of a licence never
 *       passes through this service, so a queue of applicants uploading photographs does not
 *       consume request threads or the Gateway's body limit.</li>
 *   <li>The client confirms. Only then is the object verified to exist and size-checked, and only
 *       then does a document row appear for a reviewer.</li>
 * </ol>
 *
 * <p>Step 3 is what makes the flow trustworthy: without it an application could carry a document
 * row for bytes nobody ever uploaded, and a reviewer would open a broken link and have to guess
 * whether the applicant was at fault.
 *
 * <p><strong>Why the merchant-kyc bucket must stay unrouted, and why every read is a short-lived
 * presigned URL.</strong> The objects in it are national ids, driving licences and vehicle papers —
 * scans of the exact documents used to open accounts and take out credit in somebody's name. The
 * product-images bucket is publicly readable because a plain CDN URL for a photograph of a burger
 * is harmless and cacheable; the same arrangement here would mean that anybody who obtains a URL,
 * for any reason and forever — a proxy log, a browser history, a screenshot in a support ticket, a
 * referrer header, a shared link in a chat — holds a copy of somebody's identity papers, with no
 * way to revoke it short of deleting the object. Presigning instead makes the URL a capability with
 * an expiry rather than a permanent address: it is minted per reviewer, per document, per few
 * minutes, after {@code @PreAuthorize} and the ownership checks below have already run, and it is
 * useless to anybody who finds it afterwards. That property depends entirely on the bucket having
 * no anonymous read policy and no Gateway route — if either is ever added, every check in this file
 * becomes decorative. {@link FilePurpose#MERCHANT_KYC} is what binds these objects to that bucket,
 * which is why the purpose is chosen here and never passed in.
 */
@Service
public class ApplicantDocumentService {

    private static final Logger log = LoggerFactory.getLogger(ApplicantDocumentService.class);

    private final ApplicantDocumentRepository documents;
    private final StorageService storage;
    private final FileMetadataRepository files;
    private final Set<String> allowedContentTypes;

    public ApplicantDocumentService(ApplicantDocumentRepository documents,
                                    StorageService storage,
                                    FileMetadataRepository files,
                                    @Value("${delivery.onboarding.documents.allowed-content-types:"
                                            + "image/jpeg,image/png,image/webp,application/pdf}")
                                    Set<String> allowedContentTypes) {
        this.documents = documents;
        this.storage = storage;
        this.files = files;
        this.allowedContentTypes = allowedContentTypes;
    }

    /**
     * Thrown when a document cannot be uploaded or decided as asked. Answers 422 — the caller can
     * act on the message.
     */
    public static class DocumentRuleException extends RuntimeException {
        public DocumentRuleException(String message) {
            super(message);
        }
    }

    // ---------------------------------------------------------------- the applicant

    /**
     * Step 1: a one-shot URL to PUT one document to.
     *
     * @param application the applicant's own, already resolved from their token by the caller —
     *                    never from an id in the URL, which is the whole reason no endpoint here
     *                    takes one
     */
    @Transactional
    public PresignedUpload presign(OnboardingApplication application, String uploaderUserRef,
                                   DocumentKind kind, String contentType) {
        requireOpenForUpload(application);

        if (!kind.appliesTo(application.getKind())) {
            // Refused before a URL exists rather than at confirm time. A rider asking to upload a
            // commercial registration is confused or probing; either way there is no reason to hand
            // them write access to an object in the KYC bucket while working out which.
            throw new DocumentRuleException("A " + application.getKind().name().toLowerCase()
                    + " application does not ask for a " + kind.name().toLowerCase());
        }

        if (!allowedContentTypes.contains(contentType)) {
            // Checked here as well as inside StorageService, which has its own list. Two lists is a
            // wart — the platform's is named for images and is shared by every purpose — but the
            // one that produces a message an applicant can act on ("we take photos and PDFs")
            // rather than a storage exception has to be this one.
            throw new DocumentRuleException(
                    "Documents must be a photo or a PDF, not " + contentType);
        }

        // Namespaced by application id so the bucket stays browsable and an orphan sweep is
        // straightforward. The filename itself is server-generated inside StorageService — a
        // client-chosen key would let one applicant overwrite another's document by guessing a path.
        return storage.presignUpload(uploaderUserRef, FilePurpose.MERCHANT_KYC,
                contentType, "applications/" + application.getId());
    }

    /**
     * Step 3: the bytes landed, so record the document and put it in front of a reviewer.
     *
     * <p>The ownership check runs twice, deliberately, exactly as it does for product images:
     * {@code confirmUpload} verifies the <em>file</em> belongs to the caller, and
     * {@link #requireOpenForUpload} verifies the <em>application</em> does. Dropping the second
     * would let somebody staple their own document onto another applicant's file.
     *
     * <p>An upload of a kind that already has a live document supersedes it rather than replacing
     * it in place — that is what "replace their own documents while the application is pending"
     * means here, and it keeps the previously reviewed version on the record.
     */
    @Transactional
    public ApplicantDocument confirm(OnboardingApplication application, String uploaderUserRef,
                                     UUID fileId, DocumentKind kind) {
        requireOpenForUpload(application);

        if (!kind.appliesTo(application.getKind())) {
            throw new DocumentRuleException("A " + application.getKind().name().toLowerCase()
                    + " application does not ask for a " + kind.name().toLowerCase());
        }

        FileMetadata metadata = storage.confirmUpload(fileId, uploaderUserRef);

        // The object key is server-generated and prefixed with the application it was presigned
        // for. Checking it here closes the one remaining gap: a caller who presigned against their
        // own application and then confirmed the same file against a second application they also
        // own would otherwise land one applicant's scan under another's paperwork.
        String expectedPrefix = "applications/" + application.getId() + "/";
        if (!metadata.getObjectKey().startsWith(expectedPrefix)) {
            throw new DocumentRuleException("That upload was not started for this application");
        }

        documents.findByApplicationIdAndKindAndSupersededAtIsNull(application.getId(), kind)
                .ifPresent(ApplicantDocument::supersede);
        // Flushed before the insert so the partial unique index on (application_id, kind) sees the
        // supersede. Without it Hibernate is free to order the INSERT first and the upload is
        // refused by the constraint it is meant to satisfy.
        documents.flush();

        ApplicantDocument document = new ApplicantDocument(application.getId(), kind,
                metadata.getId(), metadata.getObjectKey(), metadata.getContentType());
        documents.save(document);

        // The kind and the application, never the object key or anything from the file itself.
        log.info("Document {} uploaded for application {}", kind, application.getReference());
        return document;
    }

    /** The applicant's own documents: what they uploaded and how each one fared. */
    @Transactional(readOnly = true)
    public List<ApplicantDocument> liveFor(UUID applicationId) {
        return documents.findByApplicationIdAndSupersededAtIsNullOrderByKindAsc(applicationId);
    }

    /** Everything ever uploaded, superseded rows included. Reviewer-facing only. */
    @Transactional(readOnly = true)
    public List<ApplicantDocument> historyFor(UUID applicationId) {
        return documents.findByApplicationIdOrderByUploadedAtDesc(applicationId);
    }

    /** The live documents for several applications at once, so a queue is not N+1 queries deep. */
    @Transactional(readOnly = true)
    public List<ApplicantDocument> liveForAll(List<UUID> applicationIds) {
        return applicationIds.isEmpty()
                ? List.of()
                : documents.findByApplicationIdInAndSupersededAtIsNull(applicationIds);
    }

    // ---------------------------------------------------------------- the reviewer

    /**
     * A URL a reviewer can actually open the document with.
     *
     * <p>Minted at the moment of asking and valid for minutes — see the class comment. Returns
     * empty rather than throwing when the upload was never confirmed: a PENDING file row is an
     * abandoned upload, which is a normal thing for an applicant to do, and the reviewer's panel
     * should say "not uploaded" rather than fail to render.
     */
    @Transactional(readOnly = true)
    public Optional<String> viewUrl(ApplicantDocument document) {
        return files.findById(document.getFileId())
                .filter(metadata -> metadata.getStatus() == FileMetadata.Status.UPLOADED)
                .map(storage::readUrl);
    }

    /**
     * One document of one application, looked up by both ids at once.
     *
     * <p>Both come from the caller's URL, so the scoping is in the query: fetching by id and
     * comparing the application afterwards is the same check until the day somebody forgets it.
     */
    @Transactional(readOnly = true)
    public ApplicantDocument require(UUID applicationId, UUID documentId) {
        return documents.findByIdAndApplicationId(documentId, applicationId)
                .orElseThrow(() -> new DocumentRuleException("No such document"));
    }

    @Transactional
    public ApplicantDocument approve(UUID applicationId, UUID documentId,
                                     String reviewer, String note) {
        ApplicantDocument document = require(applicationId, documentId);
        requireLive(document);
        try {
            document.approve(reviewer, note);
        } catch (IllegalStateException e) {
            throw new DocumentRuleException(e.getMessage());
        }
        documents.save(document);
        log.info("{} approved the {} on application {}", reviewer, document.getKind(), applicationId);
        return document;
    }

    @Transactional
    public ApplicantDocument reject(UUID applicationId, UUID documentId,
                                    String reviewer, String reason, String note) {
        ApplicantDocument document = require(applicationId, documentId);
        requireLive(document);
        try {
            document.reject(reviewer, reason, note);
        } catch (IllegalStateException | IllegalArgumentException e) {
            throw new DocumentRuleException(e.getMessage());
        }
        documents.save(document);
        // The reason is not logged: a reviewer's wording about somebody's identity papers belongs
        // on the record a reviewer reads, not in an operational log stream.
        log.info("{} rejected the {} on application {}", reviewer, document.getKind(), applicationId);
        return document;
    }

    /**
     * Which documents would hold this application up, as a stable summary.
     *
     * <p>Built from enum names only — nothing applicant-supplied — because it is stored on the
     * application when a reviewer approves over the top of it.
     */
    @Transactional(readOnly = true)
    public String outstandingSummary(UUID applicationId) {
        String summary = liveFor(applicationId).stream()
                .filter(ApplicantDocument::isOutstanding)
                .map(document -> document.getKind().name() + "=" + document.getStatus().name())
                .reduce((a, b) -> a + ", " + b)
                .orElse("");
        return summary.isEmpty() ? null : summary;
    }

    private void requireLive(ApplicantDocument document) {
        if (!document.isLive()) {
            throw new DocumentRuleException(
                    "That document was replaced by a newer upload; decide the current one");
        }
    }

    /**
     * An applicant may add to their file only while somebody is still deciding it.
     *
     * <p>After a decision the documents are the evidence the decision was made on, and letting them
     * change afterwards would mean an approved application whose paperwork no longer matches what
     * anybody approved.
     */
    private void requireOpenForUpload(OnboardingApplication application) {
        if (application.isDecided()) {
            throw new DocumentRuleException(
                    "This application has already been decided, so its documents cannot change");
        }
    }
}

package com.delivery.onboarding.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ApplicantDocumentRepository extends JpaRepository<ApplicantDocument, UUID> {

    /**
     * Everything ever uploaded against one application, newest first — superseded rows included,
     * because the reviewer's history panel is the reason they are kept.
     */
    List<ApplicantDocument> findByApplicationIdOrderByUploadedAtDesc(UUID applicationId);

    /** What currently counts: one row per kind at most. */
    List<ApplicantDocument> findByApplicationIdAndSupersededAtIsNullOrderByKindAsc(UUID applicationId);

    /** The row a replacement upload has to push aside. */
    Optional<ApplicantDocument> findByApplicationIdAndKindAndSupersededAtIsNull(
            UUID applicationId, DocumentKind kind);

    /**
     * One document, scoped to its application in the query rather than fetched by id and checked
     * afterwards.
     *
     * <p>Both ids come from the caller's URL. Loading by id alone and comparing the application
     * afterwards is the same check on a good day and a data leak on the day somebody forgets it —
     * this way the query cannot return another applicant's document at all.
     */
    Optional<ApplicantDocument> findByIdAndApplicationId(UUID id, UUID applicationId);

    /** For the several-applications listings, so the queue is not N+1 lookups deep. */
    List<ApplicantDocument> findByApplicationIdInAndSupersededAtIsNull(List<UUID> applicationIds);
}

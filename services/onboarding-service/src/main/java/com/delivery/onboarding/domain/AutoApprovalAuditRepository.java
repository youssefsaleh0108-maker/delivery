package com.delivery.onboarding.domain;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/**
 * Writes to the append-only auto-approval history. Nothing here updates or deletes, and the entity
 * has no setters, so the only operation this table supports is one insert per change.
 *
 * <p>Deliberately no finders. The trail is written by every change and read by nobody in this
 * service yet: the backoffice contract is the current position and its two endpoints, and a history
 * panel is not part of it. Adding a derived query now would mean shipping a read path with no
 * caller and no test — the rows are there for the query that gets asked in a year, and for the
 * screen that will be specified when somebody wants it.
 */
public interface AutoApprovalAuditRepository extends JpaRepository<AutoApprovalAudit, UUID> {
}

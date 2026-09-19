package com.delivery.onboarding.domain;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PartnerEditEntryRepository extends JpaRepository<PartnerEditEntry, UUID> {

    /** One partner's edit history, newest first. Empty when nobody ever edited the record. */
    List<PartnerEditEntry> findByApplicationIdOrderByCreatedAtDesc(UUID applicationId);

    /**
     * The first change anybody made to one field of one record — whose old value is therefore what
     * the field held when the application came in. Empty when the field was never edited.
     *
     * <p>For the contact email that old value is the address the applicant answered a code on, which
     * is how the applicant's sign-up tells the proved address from one backoffice typed in later.
     *
     * @param field a {@link PartnerEditEntry.Field} name, as the rows store it
     */
    Optional<PartnerEditEntry> findFirstByApplicationIdAndFieldOrderByCreatedAtAsc(
            UUID applicationId, String field);
}

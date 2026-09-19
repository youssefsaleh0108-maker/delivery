package com.delivery.product.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.delivery.product.domain.PhotoSearchUse.Kind;

/**
 * The photo reader's use counts ({@code PhotoQuota}). Top-level, like every repository here: Spring's
 * scan ignores one declared as a nested interface, and a service built on it would fail only at
 * deploy.
 */
public interface PhotoSearchUseRepository extends JpaRepository<PhotoSearchUse, UUID> {

    /** The account lock's first key: its own name among every advisory lock in the database. */
    int ACCOUNT_PHOTO_LOCK = 38_001;

    /** The platform lock's first key. Its second is always {@link #PLATFORM_PHOTO_KEY}. */
    int PLATFORM_PHOTO_LOCK = 38_002;

    /** The one platform-wide counter this lock guards: customer photo searches. */
    int PLATFORM_PHOTO_KEY = 1;

    /**
     * Serialises this account's photo reads for the rest of the transaction, as
     * {@link CatalogScanRepository#lockMerchant} serialises a merchant's scan starts.
     *
     * <p>Without it, three photos sent at once by one account would each count the same uses and each
     * see room for one more. There is no account row in this service to lock, so it is a
     * transaction-scoped advisory lock on the account's id, released at commit or rollback and never
     * leaked by a request that dies. The two-key form, with a fixed first key naming this lock, so it
     * cannot collide with another advisory lock in the database (Flyway's single-key form is a separate
     * key space). {@code hashtext} folds the id into the second key: two accounts sharing a hash only
     * ever wait for each other, never get past each other. Selected FROM the function because it returns
     * void, which has no Java type to map to.
     */
    @Query(value = "SELECT 1 FROM pg_advisory_xact_lock(" + ACCOUNT_PHOTO_LOCK + ", hashtext(:accountId))",
            nativeQuery = true)
    int lockAccount(@Param("accountId") String accountId);

    /**
     * Serialises every customer photo search's count of the platform's day, taken after the account's
     * own lock and always in that order, so two locks never wait on each other in a circle.
     *
     * <p>The platform limit counts across accounts, which the account lock does not serialise: two
     * customers each seeing one search left would both take it. Held for the few milliseconds the
     * count and the insert take, by at most the platform's day of searches.
     */
    @Query(value = "SELECT 1 FROM pg_advisory_xact_lock(" + PLATFORM_PHOTO_LOCK + ", " + PLATFORM_PHOTO_KEY
            + ")", nativeQuery = true)
    int lockPlatform();

    /** This account's uses of this kind since {@code since}: what a per-account limit counts. */
    long countByAccountIdAndKindAndCreatedAtAfter(String accountId, Kind kind, Instant since);

    /** Every account's uses of this kind since {@code since}: what the platform limit counts. */
    long countByKindAndCreatedAtAfter(Kind kind, Instant since);

    /** The oldest of this account's uses the window still counts: when it leaves, one more is allowed. */
    Optional<PhotoSearchUse> findFirstByAccountIdAndKindAndCreatedAtAfterOrderByCreatedAtAsc(
            String accountId, Kind kind, Instant since);

    /** The oldest use of this kind the platform's window still counts. */
    Optional<PhotoSearchUse> findFirstByKindAndCreatedAtAfterOrderByCreatedAtAsc(Kind kind, Instant since);

    /** Forgets uses that no window counts any more. Returns how many went. */
    @Modifying
    @Query("DELETE FROM PhotoSearchUse u WHERE u.createdAt < :cutoff")
    int deleteOlderThan(@Param("cutoff") Instant cutoff);
}

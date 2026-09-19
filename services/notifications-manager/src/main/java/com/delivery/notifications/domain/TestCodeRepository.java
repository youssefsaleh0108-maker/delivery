package com.delivery.notifications.domain;

import java.time.Instant;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** The test code sink's rows. Written only by {@code TestCodeSink}; read by nothing in this service. */
public interface TestCodeRepository extends JpaRepository<TestCode, UUID> {

    /**
     * Drops what nobody will read again. A code lives ten minutes and a smoke test reads it within
     * seconds, so a day is generous; without this the table grows by one row per test address for
     * ever.
     */
    @Modifying
    @Query("delete from TestCode t where t.createdAt < :cutoff")
    int deleteOlderThan(@Param("cutoff") Instant cutoff);
}

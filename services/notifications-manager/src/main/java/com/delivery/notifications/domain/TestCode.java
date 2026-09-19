package com.delivery.notifications.domain;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A one-time code sent to an address on the reserved test domain, kept so a smoke test can read it.
 *
 * <p>The only place the platform keeps a code, and only for addresses nobody can own: see
 * {@code TestCodeSink} for the rules that decide what lands here, and V20 for why the table exists
 * at all. Nothing reads it but a person or script with database access.
 */
@Entity
@Table(name = "test_code_sink", schema = "notification")
public class TestCode {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    /** Always an address on the reserved test domain, lower-cased. */
    @Column(name = "recipient", nullable = false, length = 255)
    private String recipient;

    @Column(name = "purpose", nullable = false, length = 64)
    private String purpose;

    @Column(name = "code", nullable = false, length = 64)
    private String code;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected TestCode() {
        // for JPA
    }

    public TestCode(String recipient, String purpose, String code) {
        this.id = UUID.randomUUID();
        this.recipient = recipient;
        this.purpose = purpose;
        this.code = code;
        this.createdAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public String getRecipient() {
        return recipient;
    }

    public String getPurpose() {
        return purpose;
    }

    public String getCode() {
        return code;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}

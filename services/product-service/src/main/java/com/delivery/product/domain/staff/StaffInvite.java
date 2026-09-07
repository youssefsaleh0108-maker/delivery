package com.delivery.product.domain.staff;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A one-time code that lets somebody join a shop as staff.
 *
 * <p>This exists so that adding an employee never mints an identity. The owner creates a code, the
 * employee signs up through the ordinary customer path and redeems it with their own token, and the
 * membership binds to the {@code sub} that redeemed it. The alternative — the owner typing an email
 * and the platform creating a Keycloak user — would hand every merchant an account-creation
 * primitive and a spam vector, for no gain.
 */
@Entity
@Table(name = "staff_invites")
public class StaffInvite {

    /** Unambiguous alphabet: no O/0, I/1, so a code read aloud across a counter survives. */
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final int CODE_LENGTH = 8;
    public static final Duration LIFETIME = Duration.ofHours(24);

    @Id
    @Column(name = "code", nullable = false, length = 12, updatable = false)
    private String code;

    @Column(name = "store_id", nullable = false, updatable = false)
    private UUID storeId;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false, length = 16)
    private StaffRole role;

    @Column(name = "display_name", length = 120)
    private String displayName;

    /** Contact detail only — never an account trigger. */
    @Column(name = "email", length = 200)
    private String email;

    @Column(name = "phone", length = 32)
    private String phone;

    @Column(name = "created_by", nullable = false, length = 64, updatable = false)
    private String createdBy;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "accepted_by", length = 64)
    private String acceptedBy;

    @Column(name = "accepted_at")
    private Instant acceptedAt;

    protected StaffInvite() {
        // for JPA
    }

    public StaffInvite(UUID storeId, StaffRole role, String displayName, String email, String phone,
                       String createdBy) {
        this.code = newCode();
        this.storeId = storeId;
        this.role = role;
        this.displayName = displayName;
        this.email = email;
        this.phone = phone;
        this.createdBy = createdBy;
        this.expiresAt = Instant.now().plus(LIFETIME);
    }

    private static String newCode() {
        StringBuilder out = new StringBuilder(CODE_LENGTH);
        for (int i = 0; i < CODE_LENGTH; i++) {
            out.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
        }
        return out.toString();
    }

    public boolean isRedeemable(Instant now) {
        return acceptedAt == null && now.isBefore(expiresAt);
    }

    public void redeem(String userRef) {
        this.acceptedBy = userRef;
        this.acceptedAt = Instant.now();
    }

    public String getCode() {
        return code;
    }

    public UUID getStoreId() {
        return storeId;
    }

    public StaffRole getRole() {
        return role;
    }

    public String getDisplayName() {
        return displayName;
    }

    public String getEmail() {
        return email;
    }

    public String getPhone() {
        return phone;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public String getAcceptedBy() {
        return acceptedBy;
    }

    public Instant getAcceptedAt() {
        return acceptedAt;
    }
}

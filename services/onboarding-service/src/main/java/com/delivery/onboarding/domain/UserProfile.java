package com.delivery.onboarding.domain;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A person's own profile extras — today just the avatar.
 *
 * <p>Keyed by the Keycloak sub rather than any role-specific id: a selfie belongs to the
 * <em>person</em>, and the same face should follow an account that is a customer today and a
 * rider next month. The row is created lazily on the first upload — an account that never set a
 * picture has no row, and the API renders that as "no avatar" rather than inventing a record.
 */
@Entity
@Table(name = "user_profiles")
public class UserProfile {

    @Id
    @Column(name = "user_ref", nullable = false, updatable = false, length = 64)
    private String userRef;

    /** Object key in the private user-avatars bucket. Null until an upload is confirmed. */
    @Column(name = "avatar_object_key", length = 512)
    private String avatarObjectKey;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected UserProfile() {
        // for JPA
    }

    public UserProfile(String userRef) {
        this.userRef = userRef;
    }

    public void updateAvatar(String avatarObjectKey) {
        this.avatarObjectKey = avatarObjectKey;
        this.updatedAt = Instant.now();
    }

    public void clearAvatar() {
        this.avatarObjectKey = null;
        this.updatedAt = Instant.now();
    }

    public String getUserRef() {
        return userRef;
    }

    public String getAvatarObjectKey() {
        return avatarObjectKey;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}

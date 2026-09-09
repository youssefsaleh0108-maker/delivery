package com.delivery.onboarding.service;

import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.UserProfile;
import com.delivery.onboarding.domain.UserProfileRepository;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.StorageService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The account's own picture, and what "delete" has to mean for one.
 *
 * <p>An avatar is a photograph of a person, held in a private bucket and read through presigned
 * URLs that outlive the request that minted them. Clearing the profile's reference therefore is not
 * deletion: the object stays, its {@code file_metadata} row stays, and anyone still holding a URL
 * keeps getting the face. So the tests below assert the object goes, not merely that the screen
 * stops showing it.
 */
class UserAvatarServiceTest {

    private static final String USER = "keycloak-sub-sam";
    private static final String BUCKET = FilePurpose.USER_AVATAR.bucket();

    private UserProfileRepository profiles;
    private StorageService storage;
    private FileMetadataRepository files;
    private UserAvatarService service;

    @BeforeEach
    void setUp() {
        profiles = mock(UserProfileRepository.class);
        storage = mock(StorageService.class);
        files = mock(FileMetadataRepository.class);
        service = new UserAvatarService(profiles, storage, files);

        when(profiles.findById(anyString())).thenReturn(Optional.empty());
        when(profiles.save(any(UserProfile.class))).thenAnswer(call -> call.getArgument(0));
        when(files.findByBucketAndObjectKey(anyString(), anyString())).thenReturn(Optional.empty());
    }

    /** A profile already pointing at a confirmed picture, and the row that picture has. */
    private FileMetadata storedAvatar(String objectKey) {
        FileMetadata metadata = new FileMetadata(BUCKET, objectKey, USER, "image/jpeg",
                FilePurpose.USER_AVATAR);
        metadata.markUploaded(1024L);
        when(files.findByBucketAndObjectKey(BUCKET, objectKey)).thenReturn(Optional.of(metadata));

        UserProfile profile = new UserProfile(USER);
        profile.updateAvatar(objectKey);
        when(profiles.findById(USER)).thenReturn(Optional.of(profile));
        return metadata;
    }

    @Nested
    @DisplayName("removing the picture")
    class Removing {

        /**
         * The property the button promises. Without the storage call the bytes are still in the
         * bucket and a presigned URL issued a minute earlier still serves them, which is the same
         * as not having deleted anything.
         */
        @Test
        void the_object_and_its_metadata_row_go_with_the_reference() {
            FileMetadata metadata = storedAvatar("users/" + USER + "/a1.jpg");

            service.remove(USER);

            verify(storage).softDelete(metadata.getId(), USER);
        }

        @Test
        void the_profile_stops_pointing_at_it() {
            storedAvatar("users/" + USER + "/a1.jpg");

            service.remove(USER);

            assertThat(profiles.findById(USER).orElseThrow().getAvatarObjectKey()).isNull();
        }

        /** Nothing to delete, and no ownership check to fail: an account with no picture is normal. */
        @Test
        void an_account_with_no_picture_asks_storage_for_nothing() {
            when(profiles.findById(USER)).thenReturn(Optional.of(new UserProfile(USER)));

            service.remove(USER);

            verifyNoInteractions(storage);
        }

        @Test
        void an_account_with_no_profile_row_asks_storage_for_nothing() {
            service.remove(USER);

            verifyNoInteractions(storage);
        }

        /**
         * An upload that was never confirmed leaves a key with no usable row. The removal still has
         * to clear the reference rather than failing on the way to it — the account asked for the
         * picture to be gone, and it is.
         */
        @Test
        void a_key_whose_row_is_missing_still_clears_the_reference() {
            UserProfile profile = new UserProfile(USER);
            profile.updateAvatar("users/" + USER + "/never-confirmed.jpg");
            when(profiles.findById(USER)).thenReturn(Optional.of(profile));

            service.remove(USER);

            assertThat(profile.getAvatarObjectKey()).isNull();
            verify(storage, never()).softDelete(any(), anyString());
        }
    }

    @Nested
    @DisplayName("replacing the picture")
    class Replacing {

        private FileMetadata uploaded(String objectKey) {
            FileMetadata metadata = new FileMetadata(BUCKET, objectKey, USER, "image/jpeg",
                    FilePurpose.USER_AVATAR);
            metadata.markUploaded(2048L);
            when(storage.confirmUpload(metadata.getId(), USER)).thenReturn(metadata);
            return metadata;
        }

        /** Changing your photo is withdrawing the old one, so the old one has to actually go. */
        @Test
        void the_picture_it_replaces_is_discarded() {
            FileMetadata old = storedAvatar("users/" + USER + "/old.jpg");
            FileMetadata fresh = uploaded("users/" + USER + "/new.jpg");

            UserProfile profile = service.confirm(USER, fresh.getId());

            assertThat(profile.getAvatarObjectKey()).isEqualTo("users/" + USER + "/new.jpg");
            verify(storage).softDelete(old.getId(), USER);
        }

        /**
         * A retried confirm arrives as the same file id, and {@code confirmUpload} answers it
         * happily. Deleting on that path would remove the object the account is now pointing at.
         */
        @Test
        void confirming_the_same_upload_twice_keeps_the_object() {
            FileMetadata metadata = uploaded("users/" + USER + "/a1.jpg");
            storedAvatar("users/" + USER + "/a1.jpg");

            service.confirm(USER, metadata.getId());

            verify(storage, never()).softDelete(any(), anyString());
        }

        @Test
        void a_first_picture_replaces_nothing() {
            FileMetadata fresh = uploaded("users/" + USER + "/first.jpg");

            service.confirm(USER, fresh.getId());

            verify(storage, never()).softDelete(any(), anyString());
        }

        /**
         * The prefix check refuses somebody else's upload, and nothing is deleted on the way out —
         * a refused confirm must not cost the account the picture it already had.
         */
        @Test
        void an_upload_from_another_folder_is_refused_and_costs_nothing() {
            storedAvatar("users/" + USER + "/mine.jpg");
            FileMetadata theirs = uploaded("users/keycloak-sub-someone-else/theirs.jpg");

            UUID fileId = theirs.getId();
            assertThatThrownBy(() -> service.confirm(USER, fileId))
                    .isInstanceOf(ProviderProfileService.ProfileRuleException.class);

            verify(storage, never()).softDelete(any(), anyString());
        }
    }
}

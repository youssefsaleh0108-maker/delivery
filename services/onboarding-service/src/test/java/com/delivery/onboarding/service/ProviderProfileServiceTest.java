package com.delivery.onboarding.service;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.onboarding.domain.ProviderProfile;
import com.delivery.onboarding.domain.ProviderProfileRepository;
import com.delivery.onboarding.service.ProviderProfileService.ProfileRuleException;
import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FileMetadataRepository;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.StorageService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The carrier settings screen's fields, and the rules that keep them meaning something: hours that
 * open before they close on days that exist, regions that are names rather than paragraphs, and a
 * logo that goes through the same confirmed-upload flow as every other stored image.
 */
class ProviderProfileServiceTest {

    private static final UUID PROVIDER = UUID.randomUUID();
    private static final String STAFF = "keycloak-sub-staff";

    private ProviderProfileRepository profiles;
    private StorageService storage;
    private FileMetadataRepository files;
    private ProviderProfileService service;

    @BeforeEach
    void setUp() {
        profiles = mock(ProviderProfileRepository.class);
        storage = mock(StorageService.class);
        files = mock(FileMetadataRepository.class);
        service = new ProviderProfileService(profiles, storage, files);

        when(profiles.findById(any())).thenReturn(Optional.empty());
        when(profiles.save(any(ProviderProfile.class))).thenAnswer(call -> call.getArgument(0));
    }

    private static Map<String, Map<String, String>> monday(String open, String close) {
        return Map.of("MONDAY", Map.of("open", open, "close", close));
    }

    @Nested
    @DisplayName("saving the settings")
    class Saving {

        @Test
        void a_first_save_creates_the_profile_with_the_values_given() {
            ProviderProfile profile = service.save(PROVIDER, STAFF,
                    List.of("Beirut", "Jounieh"), monday("08:00", "22:00"));

            assertThat(profile.getProviderId()).isEqualTo(PROVIDER);
            assertThat(profile.getDispatchRegions()).containsExactly("Beirut", "Jounieh");
            assertThat(profile.getOperatingHours())
                    .containsEntry("MONDAY", Map.of("open", "08:00", "close", "22:00"));
            assertThat(profile.getUpdatedBy()).isEqualTo(STAFF);
            verify(profiles).save(profile);
        }

        @Test
        void a_second_save_replaces_the_settings_wholesale() {
            ProviderProfile existing = new ProviderProfile(PROVIDER);
            existing.updateSettings(List.of("Beirut"), monday("08:00", "22:00"), STAFF);
            when(profiles.findById(PROVIDER)).thenReturn(Optional.of(existing));

            ProviderProfile saved = service.save(PROVIDER, STAFF, List.of("Tripoli"), Map.of());

            assertThat(saved.getDispatchRegions()).containsExactly("Tripoli");
            // PUT semantics: the deleted day stays deleted rather than being merged back in.
            assertThat(saved.getOperatingHours()).isEmpty();
        }

        @Test
        void region_names_are_trimmed_before_they_are_stored() {
            ProviderProfile profile = service.save(PROVIDER, STAFF,
                    List.of("  Beirut  "), Map.of());

            assertThat(profile.getDispatchRegions()).containsExactly("Beirut");
        }

        @Test
        void day_names_are_normalised_so_two_spellings_are_one_key() {
            ProviderProfile profile = service.save(PROVIDER, STAFF, List.of(),
                    Map.of("monday", Map.of("open", "08:00", "close", "12:00")));

            assertThat(profile.getOperatingHours()).containsKey("MONDAY");
        }
    }

    @Nested
    @DisplayName("refusing settings that do not mean anything")
    class Refusing {

        @Test
        void a_blank_region_is_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of("Beirut", "  "),
                    Map.of()))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("blank");
        }

        @Test
        void more_regions_than_the_cap_are_refused() {
            List<String> tooMany = java.util.stream.IntStream
                    .rangeClosed(0, ProviderProfileService.MAX_REGIONS)
                    .mapToObj(i -> "Region " + i).toList();

            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, tooMany, Map.of()))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("At most");
        }

        @Test
        void a_region_longer_than_the_cap_is_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF,
                    List.of("x".repeat(ProviderProfileService.MAX_REGION_LENGTH + 1)), Map.of()))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("capped");
        }

        /** The form should show the carrier what they typed, not silently collapse it. */
        @Test
        void the_same_region_twice_is_refused_regardless_of_case() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF,
                    List.of("Beirut", "BEIRUT"), Map.of()))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("twice");
        }

        @Test
        void a_day_that_does_not_exist_is_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    Map.of("SOMEDAY", Map.of("open", "08:00", "close", "12:00"))))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("not a day of the week");
        }

        @Test
        void opening_at_or_after_closing_is_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    monday("22:00", "08:00")))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("open before it closes");
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    monday("08:00", "08:00")))
                    .isInstanceOf(ProfileRuleException.class);
        }

        @Test
        void times_that_are_not_a_24_hour_clock_are_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    monday("8am", "22:00")))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("HH:mm");
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    monday("25:00", "26:00")))
                    .isInstanceOf(ProfileRuleException.class);
        }

        @Test
        void a_day_missing_its_open_or_close_is_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    Map.of("MONDAY", Map.of("open", "08:00"))))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("exactly an open and a close");
        }

        @Test
        void a_day_carrying_extra_keys_is_refused() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(),
                    Map.of("MONDAY", Map.of("open", "08:00", "close", "12:00", "lunch", "13:00"))))
                    .isInstanceOf(ProfileRuleException.class);
        }

        @Test
        void nothing_is_written_when_validation_refuses() {
            assertThatThrownBy(() -> service.save(PROVIDER, STAFF, List.of(""), Map.of()))
                    .isInstanceOf(ProfileRuleException.class);

            verify(profiles, never()).save(any());
        }
    }

    @Nested
    @DisplayName("the logo")
    class Logo {

        @Test
        void a_presign_goes_to_the_public_bucket_under_the_providers_own_prefix() {
            service.presignLogo(PROVIDER, STAFF, "image/png");

            verify(storage).presignUpload(STAFF, FilePurpose.PRODUCT_IMAGE, "image/png",
                    "providers/" + PROVIDER);
        }

        /** The platform list allows PDF for KYC documents; a logo is an image, full stop. */
        @Test
        void a_pdf_logo_is_refused_before_any_url_exists() {
            assertThatThrownBy(() -> service.presignLogo(PROVIDER, STAFF, "application/pdf"))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("JPEG, PNG or WebP");

            verify(storage, never()).presignUpload(anyString(), any(), anyString(), anyString());
        }

        @Test
        void confirming_points_the_profile_at_the_uploaded_object() {
            FileMetadata metadata = new FileMetadata(FilePurpose.PRODUCT_IMAGE.bucket(),
                    "providers/" + PROVIDER + "/logo.png", STAFF, "image/png",
                    FilePurpose.PRODUCT_IMAGE);
            when(storage.confirmUpload(metadata.getId(), STAFF)).thenReturn(metadata);

            ProviderProfile profile = service.confirmLogo(PROVIDER, STAFF, metadata.getId());

            assertThat(profile.getLogoObjectKey())
                    .isEqualTo("providers/" + PROVIDER + "/logo.png");
            verify(profiles).save(profile);
        }

        /**
         * The two-sided check the document flow runs, for the same reason: staff of two companies
         * must not be able to confirm one company's upload onto the other.
         */
        @Test
        void an_upload_presigned_for_another_provider_is_refused() {
            FileMetadata metadata = new FileMetadata(FilePurpose.PRODUCT_IMAGE.bucket(),
                    "providers/" + UUID.randomUUID() + "/logo.png", STAFF, "image/png",
                    FilePurpose.PRODUCT_IMAGE);
            when(storage.confirmUpload(metadata.getId(), STAFF)).thenReturn(metadata);

            assertThatThrownBy(() -> service.confirmLogo(PROVIDER, STAFF, metadata.getId()))
                    .isInstanceOf(ProfileRuleException.class)
                    .hasMessageContaining("not started for this company");

            verify(profiles, never()).save(any());
        }

        @Test
        void the_logo_url_is_the_public_one_once_the_upload_is_confirmed() {
            ProviderProfile profile = new ProviderProfile(PROVIDER);
            profile.updateLogo("providers/" + PROVIDER + "/logo.png", STAFF);
            FileMetadata metadata = new FileMetadata(FilePurpose.PRODUCT_IMAGE.bucket(),
                    profile.getLogoObjectKey(), STAFF, "image/png", FilePurpose.PRODUCT_IMAGE);
            metadata.markUploaded(123);
            when(files.findByBucketAndObjectKey(FilePurpose.PRODUCT_IMAGE.bucket(),
                    profile.getLogoObjectKey())).thenReturn(Optional.of(metadata));
            when(storage.readUrl(metadata)).thenReturn("http://cdn/product-images/logo.png");

            assertThat(service.logoUrl(profile))
                    .contains("http://cdn/product-images/logo.png");
        }

        /** An abandoned upload renders as "no logo", not as a URL that would 404. */
        @Test
        void an_unconfirmed_upload_yields_no_url() {
            ProviderProfile profile = new ProviderProfile(PROVIDER);
            profile.updateLogo("providers/" + PROVIDER + "/logo.png", STAFF);
            FileMetadata pending = new FileMetadata(FilePurpose.PRODUCT_IMAGE.bucket(),
                    profile.getLogoObjectKey(), STAFF, "image/png", FilePurpose.PRODUCT_IMAGE);
            when(files.findByBucketAndObjectKey(anyString(), anyString()))
                    .thenReturn(Optional.of(pending));

            assertThat(service.logoUrl(profile)).isEmpty();
        }

        @Test
        void a_profile_without_a_logo_yields_no_url() {
            assertThat(service.logoUrl(new ProviderProfile(PROVIDER))).isEmpty();
        }
    }

    /** A company that never saved settings has no row, and the answer says so rather than inventing one. */
    @Test
    void a_company_that_never_saved_settings_reads_as_empty() {
        assertThat(service.forProvider(PROVIDER)).isEmpty();
    }
}

package com.delivery.notifications.service;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.notifications.domain.NotificationCategory;
import com.delivery.notifications.domain.NotificationPreference;
import com.delivery.notifications.domain.NotificationPreferenceRepository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * The defaults a user gets before they ever open the settings screen, and the one category no
 * setting can reach.
 *
 * <p>The defaults are the substance of this feature rather than its configuration. Transactional
 * messages arriving unless somebody says otherwise is what makes the platform usable; marketing
 * arriving only if somebody asks for it is what makes it defensible. Either could be flipped by a
 * one-word edit that nobody would notice in review, so both are asserted here by name.
 */
class NotificationPreferenceServiceTest {

    private static final String USER = "customer-sub";

    private NotificationPreferenceRepository stored;
    private NotificationPreferenceService preferences;

    @BeforeEach
    void setUp() {
        stored = mock(NotificationPreferenceRepository.class);
        preferences = new NotificationPreferenceService(stored);

        when(stored.findByRecipientId(anyString())).thenReturn(List.of());
        when(stored.findByRecipientIdAndCategoryAndChannel(anyString(), any(), anyString()))
                .thenReturn(Optional.empty());
        when(stored.save(any(NotificationPreference.class)))
                .thenAnswer(call -> call.getArgument(0));
    }

    @Nested
    @DisplayName("what a user gets before they change anything")
    class Defaults {

        /** Order progress is the reason somebody installed the app. */
        @Test
        void order_updates_arrive_without_being_asked_for() {
            assertThat(preferences.allows(USER, "order.status_changed", "PUSH")).isTrue();
        }

        @Test
        void chat_messages_arrive_without_being_asked_for() {
            assertThat(preferences.allows(USER, "chat.message_received", "PUSH")).isTrue();
        }

        /**
         * Consent to be marketed at is not implied by signing up to have food delivered. This is the
         * assertion that would fail if the default were ever quietly flipped.
         */
        @Test
        void promotions_do_not_arrive_until_the_user_asks_for_them() {
            assertThat(preferences.allows(USER, "marketing.weekend_offer", "PUSH")).isFalse();
            assertThat(NotificationCategory.PROMOTIONS.defaultEnabled()).isFalse();
        }

        /** A user with no rows should cost no rows: nothing is written just by asking. */
        @Test
        void asking_about_a_user_who_has_changed_nothing_writes_nothing() {
            preferences.allows(USER, "order.placed", "EMAIL");

            verify(stored, never()).save(any());
        }
    }

    @Nested
    @DisplayName("the category no setting can silence")
    class AlwaysDelivered {

        /**
         * A user who silenced marketing has not asked to stop being told their password changed.
         * The table is not consulted at all, so there is no row that could be wrong.
         */
        @Test
        void an_account_message_is_allowed_without_the_table_being_consulted() {
            assertThat(preferences.allows(USER, "account.password_changed", "EMAIL")).isTrue();

            verify(stored, never())
                    .findByRecipientIdAndCategoryAndChannel(anyString(), any(), anyString());
        }

        /**
         * A one-time code is account-critical too. It reaches people mid-signup who have no
         * preferences at all, and it is the message a signup dies without.
         */
        @Test
        void a_verification_code_is_treated_as_account_critical() {
            assertThat(preferences.allows(USER, "onboarding.verification", "SMS")).isTrue();
        }

        /**
         * Fail-safe means delivering. A new event type nobody classified sending one message the
         * user could have muted is visible and small; the same oversight silently swallowing a
         * security notice is neither.
         */
        @Test
        void an_event_type_nobody_classified_is_delivered_rather_than_dropped() {
            assertThat(preferences.allows(USER, "something.brand_new", "EMAIL")).isTrue();
        }

        /**
         * Refused rather than accepted and ignored: a stored "off" the dispatch path never reads
         * would leave the user believing they had silenced something that keeps arriving.
         */
        @Test
        void turning_off_an_account_category_is_refused_with_a_reason() {
            assertThatThrownBy(() -> preferences.apply(USER, List.of(
                    new NotificationPreferenceService.Change(
                            NotificationCategory.ACCOUNT, "EMAIL", false))))
                    .isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("cannot be turned off");

            verify(stored, never()).save(any());
        }
    }

    @Nested
    @DisplayName("honouring what the user chose")
    class Stored {

        @Test
        void a_stored_off_overrides_a_default_of_on() {
            when(stored.findByRecipientIdAndCategoryAndChannel(
                    USER, NotificationCategory.ORDER_UPDATES, "PUSH"))
                    .thenReturn(Optional.of(new NotificationPreference(
                            USER, NotificationCategory.ORDER_UPDATES, "PUSH", false)));

            assertThat(preferences.allows(USER, "order.status_changed", "PUSH")).isFalse();
        }

        @Test
        void a_stored_on_overrides_a_default_of_off() {
            when(stored.findByRecipientIdAndCategoryAndChannel(
                    USER, NotificationCategory.PROMOTIONS, "EMAIL"))
                    .thenReturn(Optional.of(new NotificationPreference(
                            USER, NotificationCategory.PROMOTIONS, "EMAIL", true)));

            assertThat(preferences.allows(USER, "marketing.weekend_offer", "EMAIL")).isTrue();
        }

        /**
         * "Stop pushing promotions to my lock screen" and "stop emailing me promotions" are separate
         * asks; a preference keyed by category alone would force a user who wants one to accept the
         * other.
         */
        @Test
        void silencing_one_channel_leaves_the_others_alone() {
            when(stored.findByRecipientIdAndCategoryAndChannel(
                    USER, NotificationCategory.ORDER_UPDATES, "SMS"))
                    .thenReturn(Optional.of(new NotificationPreference(
                            USER, NotificationCategory.ORDER_UPDATES, "SMS", false)));

            assertThat(preferences.allows(USER, "order.delivered", "SMS")).isFalse();
            assertThat(preferences.allows(USER, "order.delivered", "EMAIL")).isTrue();
        }
    }

    @Nested
    @DisplayName("the settings screen")
    class Grid {

        /** The client must never have to know what a default is, so nothing comes back sparse. */
        @Test
        void a_user_who_has_changed_nothing_still_gets_the_whole_grid() {
            List<NotificationPreferenceService.Setting> grid = preferences.settingsFor(USER);

            assertThat(grid).hasSize(NotificationCategory.values().length
                    * NotificationPreferenceService.CHANNELS.size());
            assertThat(grid).allSatisfy(setting -> assertThat(setting.userChosen()).isFalse());
        }

        /** So a client can render the row as fixed rather than as a toggle that does nothing. */
        @Test
        void an_account_row_comes_back_marked_locked_and_on() {
            assertThat(preferences.settingsFor(USER))
                    .filteredOn(setting -> setting.category().equals("ACCOUNT"))
                    .allSatisfy(setting -> {
                        assertThat(setting.locked()).isTrue();
                        assertThat(setting.enabled()).isTrue();
                    });
        }

        /**
         * Even with a stray row saying otherwise. The screen reports what dispatch will actually do,
         * not what the table happens to hold — the alternative is a screen promising something the
         * send path is guaranteed to ignore.
         */
        @Test
        void an_account_row_reads_as_on_even_if_a_stray_row_says_off() {
            when(stored.findByRecipientId(USER)).thenReturn(List.of(new NotificationPreference(
                    USER, NotificationCategory.ACCOUNT, "EMAIL", false)));

            assertThat(preferences.settingsFor(USER))
                    .filteredOn(setting -> setting.category().equals("ACCOUNT")
                            && setting.channel().equals("EMAIL"))
                    .singleElement()
                    .satisfies(setting -> assertThat(setting.enabled()).isTrue());
        }

        @Test
        void a_setting_the_user_changed_is_marked_as_theirs() {
            when(stored.findByRecipientId(USER)).thenReturn(List.of(new NotificationPreference(
                    USER, NotificationCategory.PROMOTIONS, "EMAIL", true)));

            assertThat(preferences.settingsFor(USER))
                    .filteredOn(setting -> setting.category().equals("PROMOTIONS")
                            && setting.channel().equals("EMAIL"))
                    .singleElement()
                    .satisfies(setting -> {
                        assertThat(setting.enabled()).isTrue();
                        assertThat(setting.userChosen()).isTrue();
                    });
        }
    }

    @Nested
    @DisplayName("saving a change")
    class Saving {

        @Test
        void a_user_with_no_row_yet_gets_one_written() {
            preferences.apply(USER, List.of(new NotificationPreferenceService.Change(
                    NotificationCategory.PROMOTIONS, "EMAIL", true)));

            verify(stored).save(any(NotificationPreference.class));
        }

        /**
         * Updated in place rather than replaced. For PROMOTIONS the timestamp is the evidence of
         * when consent was given — the question asked when somebody disputes having opted in — and a
         * delete-and-reinsert would reset it on every save.
         */
        @Test
        void changing_an_existing_setting_updates_the_row_rather_than_replacing_it() {
            NotificationPreference existing = new NotificationPreference(
                    USER, NotificationCategory.PROMOTIONS, "EMAIL", false);
            when(stored.findByRecipientIdAndCategoryAndChannel(
                    USER, NotificationCategory.PROMOTIONS, "EMAIL"))
                    .thenReturn(Optional.of(existing));

            preferences.apply(USER, List.of(new NotificationPreferenceService.Change(
                    NotificationCategory.PROMOTIONS, "EMAIL", true)));

            assertThat(existing.isEnabled()).isTrue();
            verify(stored, never()).delete(any());
        }
    }
}

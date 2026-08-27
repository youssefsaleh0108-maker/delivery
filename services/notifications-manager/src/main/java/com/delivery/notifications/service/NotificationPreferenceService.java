package com.delivery.notifications.service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.notifications.domain.NotificationCategory;
import com.delivery.notifications.domain.NotificationPreference;
import com.delivery.notifications.domain.NotificationPreferenceRepository;
import com.delivery.platform.notifications.NotificationCommand;

/**
 * Whether a given user wants a given kind of message on a given channel.
 *
 * <p>Two callers with opposite needs. Dispatch asks one yes-or-no question per notification and must
 * be cheap and unsurprising; the settings screen wants the complete grid including the answers
 * nobody has changed. Both are here so the merge between stored deviations and coded defaults
 * exists in exactly one place — the failure mode of having it in two is a screen showing a toggle
 * in a position the dispatch path does not agree with.
 */
@Service
public class NotificationPreferenceService {

    private static final Logger log = LoggerFactory.getLogger(NotificationPreferenceService.class);

    /**
     * The channels a preference can be expressed for.
     *
     * <p>Ordered as the settings screen reads them rather than alphabetically: the channels that
     * interrupt someone come first, because those are the ones a user opening this screen is
     * usually looking for.
     */
    public static final List<String> CHANNELS = List.of(
            NotificationCommand.CHANNEL_PUSH,
            NotificationCommand.CHANNEL_IN_APP,
            NotificationCommand.CHANNEL_EMAIL,
            NotificationCommand.CHANNEL_SMS);

    private final NotificationPreferenceRepository preferences;

    public NotificationPreferenceService(NotificationPreferenceRepository preferences) {
        this.preferences = preferences;
    }

    /**
     * The question dispatch asks: may this notification go out?
     *
     * <p>A category the user cannot silence short-circuits before the repository is touched. That is
     * not a performance tweak — it means there is no row, no cache and no query result anywhere in
     * this path that could make a security notice disappear. The guarantee is structural rather
     * than a matter of the data happening to be right.
     *
     * @param eventType the event the notification came from; its namespace decides the category
     * @param channel   SMS, EMAIL, PUSH or IN_APP
     */
    @Transactional(readOnly = true)
    public boolean allows(String recipientId, String eventType, String channel) {
        NotificationCategory category = NotificationCategory.forEventType(eventType);
        if (category.alwaysDelivered()) {
            return true;
        }
        if (recipientId == null || recipientId.isBlank() || channel == null) {
            // Nobody to hold a preference. Falling back to the default rather than refusing keeps
            // transactional mail flowing for a recipient we could not identify, while promotions —
            // default off — stay off. Each direction is the safe one for its own category.
            return category.defaultEnabled();
        }
        return preferences
                .findByRecipientIdAndCategoryAndChannel(recipientId, category, channel)
                .map(NotificationPreference::isEnabled)
                .orElseGet(category::defaultEnabled);
    }

    /**
     * The whole grid for one user, defaults filled in.
     *
     * <p>Returned complete rather than sparse so the settings screen never has to know what a
     * default is. A client applying defaults itself would be a second copy of
     * {@link NotificationCategory}'s rules, in a language where nobody would think to update it.
     */
    @Transactional(readOnly = true)
    public List<Setting> settingsFor(String recipientId) {
        Map<NotificationPreference.Key, NotificationPreference> stored = new HashMap<>();
        for (NotificationPreference preference : preferences.findByRecipientId(recipientId)) {
            stored.put(new NotificationPreference.Key(
                    preference.getRecipientId(), preference.getCategory(),
                    preference.getChannel()), preference);
        }

        List<Setting> grid = new ArrayList<>();
        for (NotificationCategory category : NotificationCategory.values()) {
            for (String channel : CHANNELS) {
                NotificationPreference preference = stored.get(
                        new NotificationPreference.Key(recipientId, category, channel));
                // A locked category reports enabled whatever the table says, because that is what
                // dispatch will actually do. Showing a stored "off" here would be the screen
                // promising something the send path is guaranteed to ignore.
                boolean enabled = category.alwaysDelivered()
                        || (preference == null ? category.defaultEnabled() : preference.isEnabled());
                grid.add(new Setting(category.name(), channel, enabled,
                        category.alwaysDelivered(), preference != null));
            }
        }
        return grid;
    }

    /**
     * Applies the user's changes.
     *
     * <p>Upsert by hand rather than delete-all-and-reinsert: the row carries {@code updated_at},
     * which for PROMOTIONS is the record of when consent was given, and rewriting every row on every
     * save would reset that timestamp for settings the user never touched.
     *
     * <p>A change to an {@link NotificationCategory#alwaysDelivered()} category is refused rather
     * than accepted and ignored. Accepting it would store a row saying "off" that the dispatch path
     * never reads, and the user would come away believing they had silenced something that will keep
     * arriving — worse than a plain error.
     *
     * @throws IllegalArgumentException if a change targets a category that cannot be silenced
     */
    @Transactional
    public void apply(String recipientId, List<Change> changes) {
        for (Change change : changes) {
            if (change.category().alwaysDelivered()) {
                throw new IllegalArgumentException(
                        "security and account notifications cannot be turned off");
            }
            NotificationPreference existing = preferences
                    .findByRecipientIdAndCategoryAndChannel(
                            recipientId, change.category(), change.channel())
                    .orElse(null);
            if (existing == null) {
                preferences.save(new NotificationPreference(
                        recipientId, change.category(), change.channel(), change.enabled()));
            } else {
                existing.set(change.enabled());
                preferences.save(existing);
            }
        }
        // The user id is a Keycloak sub, not a contact detail, so it is safe to name here — and
        // whose preferences changed is the first thing asked when somebody reports that a
        // notification stopped arriving.
        log.info("Updated {} notification preference(s) for {}", changes.size(), recipientId);
    }

    /**
     * One cell of the settings grid.
     *
     * @param locked     true when the category cannot be silenced, so the client shows the row as
     *                   fixed rather than as a toggle that quietly does nothing
     * @param userChosen true when this value came from the user rather than from the default, which
     *                   is what lets a client distinguish "you turned this off" from "it ships off"
     */
    public record Setting(String category, String channel, boolean enabled, boolean locked,
                          boolean userChosen) {
    }

    /** One requested change, already validated into typed form by the controller. */
    public record Change(NotificationCategory category, String channel, boolean enabled) {
    }
}

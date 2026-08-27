package com.delivery.notifications.domain;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import com.delivery.notifications.link.NotificationLinkTarget;

/**
 * A message body per event type, channel and locale.
 *
 * <p>Stored rather than compiled in so a wording change is a data change, not a release.
 */
@Entity
@Table(name = "notification_templates")
public class NotificationTemplate {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "event_type", nullable = false, length = 64)
    private String eventType;

    @Column(name = "channel", nullable = false, length = 16)
    private String channel;

    @Column(name = "locale", nullable = false, length = 8)
    private String locale;

    @Column(name = "subject_template", columnDefinition = "text")
    private String subjectTemplate;

    @Column(name = "body_template", nullable = false, columnDefinition = "text")
    private String bodyTemplate;

    /**
     * What kind of screen this message is about, or null to derive it from the notification.
     *
     * <p>Null is the ordinary case. An order notification points at its order, and the order id is
     * already on the log row — so recording ORDER on every order template as well would be storing
     * a fact the platform already holds, in a second place that can contradict it. This column is
     * for the messages the derivation cannot know about: a chat message points at a conversation
     * and an earnings notice at a statement, neither of which is the order that triggered it.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "link_target", length = 32)
    private NotificationLinkTarget linkTarget;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected NotificationTemplate() {
        // for JPA
    }

    public String renderSubject(Map<String, String> values) {
        return subjectTemplate == null ? null : substitute(subjectTemplate, values);
    }

    public String renderBody(Map<String, String> values) {
        return substitute(bodyTemplate, values);
    }

    /**
     * Replaces {{placeholders}}.
     *
     * <p>Plain string substitution rather than a template engine on purpose: the values come from
     * order data that customers control (product names, delivery notes), and a real engine would
     * evaluate expressions in them. There is nothing to inject into here — an unmatched placeholder
     * is left as-is so a broken template is visible in the message rather than throwing mid-send.
     */
    private static String substitute(String template, Map<String, String> values) {
        String result = template;
        for (Map.Entry<String, String> entry : values.entrySet()) {
            result = result.replace("{{" + entry.getKey() + "}}",
                    entry.getValue() == null ? "" : entry.getValue());
        }
        return result.trim();
    }

    public UUID getId() {
        return id;
    }

    public String getEventType() {
        return eventType;
    }

    public String getChannel() {
        return channel;
    }

    public String getLocale() {
        return locale;
    }

    /** Null when the link should be derived from the notification rather than declared here. */
    public NotificationLinkTarget getLinkTarget() {
        return linkTarget;
    }
}

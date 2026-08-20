package com.delivery.notifications.domain;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

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
}

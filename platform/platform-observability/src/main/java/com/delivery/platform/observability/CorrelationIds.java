package com.delivery.platform.observability;

import java.util.UUID;

import org.springframework.util.StringUtils;

/**
 * Turns whatever arrived in the {@code X-Correlation-Id} header into an id that is safe to carry.
 *
 * <p>The header is client-supplied and was previously trusted verbatim. Two things go wrong when it
 * is:
 *
 * <p><strong>It breaks writes.</strong> The id follows the request into {@code outbox_event.
 * correlation_id}, which is {@code varchar(64)}. An id longer than that fails the insert — and
 * because the outbox insert is deliberately part of the caller's business transaction, the failure
 * rolls back the order along with it. A client sending a 65-character header would get a 500 on
 * checkout, from a value that never mattered to the order.
 *
 * <p><strong>It forges logs.</strong> The id is written into the MDC and appears on every log line
 * for the request, so a newline in it lets a caller inject whole fabricated log entries — into the
 * one record used to reconstruct what happened during an incident.
 *
 * <p>The response is to bound and filter rather than reject: a malformed id is a header problem, not
 * a reason to refuse someone's order, so an unusable value is replaced with a fresh one and the
 * request proceeds traced.
 */
public final class CorrelationIds {

    /** Matches {@code outbox_event.correlation_id}. Longer ids fail the insert, not just the log. */
    public static final int MAX_LENGTH = 64;

    private CorrelationIds() {
    }

    /**
     * The id to use for a request, given whatever the caller sent.
     *
     * <p>Characters outside the conservative set below are dropped rather than escaped — this is an
     * opaque trace key, so there is nothing to preserve by keeping them, and dropping cannot produce
     * a value that is still dangerous somewhere downstream.
     */
    public static String sanitize(String candidate) {
        if (!StringUtils.hasText(candidate)) {
            return UUID.randomUUID().toString();
        }

        StringBuilder safe = new StringBuilder(Math.min(candidate.length(), MAX_LENGTH));
        for (int i = 0; i < candidate.length() && safe.length() < MAX_LENGTH; i++) {
            char c = candidate.charAt(i);
            if (isSafe(c)) {
                safe.append(c);
            }
        }

        // Everything was stripped: the caller sent something, but nothing usable survived.
        return safe.isEmpty() ? UUID.randomUUID().toString() : safe.toString();
    }

    private static boolean isSafe(char c) {
        return (c >= 'a' && c <= 'z')
                || (c >= 'A' && c <= 'Z')
                || (c >= '0' && c <= '9')
                || c == '-' || c == '_' || c == '.' || c == ':';
    }
}

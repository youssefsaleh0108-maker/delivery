package com.delivery.worker.sms;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.ChannelPreparer;
import com.delivery.platform.notifications.NotificationCommand;

/**
 * SMS-specific work: recipient validation and segmentation.
 *
 * <p>Both are channel concerns, not vendor concerns — an SMS segments the same way whether it goes
 * through MontyMobile or Twilio — which is why they live in the worker rather than being repeated
 * in each provider client.
 *
 * <p>Segmentation is the part with money attached. Vendors bill per segment, so a message that
 * quietly crosses 160 characters costs double, and one non-GSM character (a curly quote pasted into
 * a template, an emoji in a product name) drops the whole message to the 70-character UCS-2 limit
 * and can quadruple the bill. Counting it here means the cost is visible in the log and capped,
 * rather than discovered on an invoice.
 */
@Component
public class SmsPreparer implements ChannelPreparer {

    private static final Logger log = LoggerFactory.getLogger(SmsPreparer.class);

    /** E.164: a leading +, a non-zero country digit, then up to 14 more. */
    private static final Pattern E164 = Pattern.compile("^\\+[1-9]\\d{7,14}$");

    /** Sent as an escape plus the character, so each of these costs two units, not one. */
    private static final String GSM_EXTENDED = "^{}\\[~]|€";

    /** The GSM 03.38 basic set plus its extension characters. Anything else forces UCS-2. */
    private static final String GSM_ALPHABET =
            "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?"
            + "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
            + GSM_EXTENDED;

    private static final int GSM_SINGLE = 160;
    private static final int GSM_CONCATENATED = 153;
    private static final int UCS2_SINGLE = 70;
    private static final int UCS2_CONCATENATED = 67;

    private final int maxSegments;

    public SmsPreparer(@Value("${delivery.sms.max-segments:3}") int maxSegments) {
        this.maxSegments = maxSegments;
    }

    @Override
    public Prepared prepare(NotificationCommand command) {
        String recipient = command.recipient() == null ? "" : command.recipient().trim();

        if (!E164.matcher(recipient).matches()) {
            // Caught here rather than at the vendor: a malformed number rejected locally costs
            // nothing, while the same number sent to a paid provider costs a request and a retry
            // budget for a result that was never going to change.
            return Prepared.reject("recipient is not a valid E.164 number: " + recipient);
        }

        String body = command.body() == null ? "" : command.body().trim();
        if (body.isEmpty()) {
            return Prepared.reject("empty SMS body");
        }

        boolean unicode = !isGsmEncodable(body);
        int units = unicode ? body.length() : gsmLength(body);
        int segments = segmentCount(units, unicode);

        if (segments > maxSegments) {
            // A refusal, not a truncation. Silently cutting a message off mid-sentence produces a
            // notification that is worse than none, and the real fix is the template.
            return Prepared.reject("message needs " + segments + " segments, limit is " + maxSegments
                    + " (" + (unicode ? "UCS-2" : "GSM-7") + ", " + units + " units)");
        }

        if (unicode) {
            log.info("SMS {} contains non-GSM characters: {} chars becomes {} UCS-2 segments",
                    command.notificationId(), body.length(), segments);
        }

        Map<String, String> metadata = new HashMap<>(
                command.metadata() == null ? Map.of() : command.metadata());
        // Carried through to the connector and into the log, so per-message cost is attributable.
        metadata.put("segments", String.valueOf(segments));
        metadata.put("encoding", unicode ? "UCS-2" : "GSM-7");

        return Prepared.ready(new NotificationCommand(
                command.notificationId(),
                command.channel(),
                recipient,
                // Ignored by every SMS provider; dropped so nothing downstream is tempted to use it.
                null,
                body,
                metadata,
                command.correlationId(),
                command.createdAt()));
    }

    private static boolean isGsmEncodable(String body) {
        return body.chars().allMatch(c -> GSM_ALPHABET.indexOf(c) >= 0);
    }

    /**
     * Billable units, not characters.
     *
     * <p>The seven characters in the GSM extension table are sent as an escape plus the character,
     * so each costs two units. Counting them as one is how a 160-character template that happens to
     * contain a {@code €} turns into two billed segments nobody predicted.
     */
    private static int gsmLength(String body) {
        int length = 0;
        for (int i = 0; i < body.length(); i++) {
            length += GSM_EXTENDED.indexOf(body.charAt(i)) >= 0 ? 2 : 1;
        }
        return length;
    }

    private static int segmentCount(int units, boolean unicode) {
        int single = unicode ? UCS2_SINGLE : GSM_SINGLE;
        int concatenated = unicode ? UCS2_CONCATENATED : GSM_CONCATENATED;

        // A concatenated message spends part of each segment on the header, so the per-segment
        // capacity drops once there is more than one.
        return units <= single ? 1 : (int) Math.ceil((double) units / concatenated);
    }
}

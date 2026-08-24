package com.delivery.connector.email;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Wraps a plain-text notification in a branded HTML alternative.
 *
 * <p>Presentation lives here, at the channel edge, rather than in the services that compose the
 * text. Those put their words on the bus, where the payload is read by queue browsers, broker
 * traces and the notification log — none of which want markup — and every channel would otherwise
 * have to agree on the same formatting rules.
 *
 * <p><strong>Everything interpolated is escaped.</strong> That is not a detail, it is the reason
 * this was safe to add at all: bodies carry customer-controlled values — a product name, a delivery
 * note — and rendering those as markup would turn a product name into an injection point in every
 * customer's inbox. Nothing from the body ever reaches the output as anything but text.
 *
 * <p>The plain text is still sent alongside as the first alternative, so a client that will not
 * render HTML shows the message rather than nothing.
 */
@Component
public class EmailHtmlLayout {

    /**
     * A body whose first paragraph is only this gets that line shown as a code block.
     *
     * <p>Deliberately narrow: short, and digits or upper-case letters only. It is meant to catch a
     * one-time code standing on its own line and nothing else — a sentence, a name or a price will
     * not match, so no ordinary message is reformatted by accident.
     */
    private static final Pattern STANDALONE_CODE = Pattern.compile("^[0-9A-Z]{4,12}$");

    private final String brandName;
    private final String brandColour;

    public EmailHtmlLayout(
            @Value("${delivery.email.brand-name:MyDelivery}") String brandName,
            @Value("${delivery.email.brand-colour:#C41D4E}") String brandColour) {
        this.brandName = brandName;
        this.brandColour = brandColour;
    }

    /** Renders the branded HTML alternative for a plain-text body. */
    public String render(String subject, String body) {
        List<String> paragraphs = paragraphsOf(body == null ? "" : body);

        StringBuilder content = new StringBuilder();
        for (int i = 0; i < paragraphs.size(); i++) {
            String paragraph = paragraphs.get(i);
            if (i == 0 && STANDALONE_CODE.matcher(paragraph).matches()) {
                content.append(codeBlock(paragraph));
            } else {
                content.append(paragraphBlock(paragraph));
            }
        }

        return """
                <!doctype html>
                <html><head><meta charset="utf-8">
                <meta name="viewport" content="width=device-width,initial-scale=1">
                <title>%s</title></head>
                <body style="margin:0;padding:0;background:#F4F5F7;">
                  <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" \
                style="background:#F4F5F7;padding:24px 12px;">
                    <tr><td align="center">
                      <table role="presentation" width="100%%" cellpadding="0" cellspacing="0" \
                style="max-width:520px;background:#FFFFFF;border-radius:12px;overflow:hidden;\
                font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
                        <tr><td style="background:%s;padding:20px 28px;">
                          <span style="color:#FFFFFF;font-size:18px;font-weight:700;\
                letter-spacing:0.2px;">%s</span>
                        </td></tr>
                        <tr><td style="padding:28px;color:#1F2933;font-size:15px;line-height:1.55;">
                %s        </td></tr>
                        <tr><td style="padding:0 28px 26px;color:#8A94A6;font-size:12px;\
                line-height:1.5;border-top:1px solid #EDEFF3;padding-top:16px;">
                          This message was sent by %s. Please do not reply to it — the address is \
                not monitored.
                        </td></tr>
                      </table>
                    </td></tr>
                  </table>
                </body></html>
                """.formatted(
                escape(subject == null || subject.isBlank() ? brandName : subject),
                escape(brandColour),
                escape(brandName),
                content,
                escape(brandName));
    }

    private String codeBlock(String code) {
        return """
                          <div style="margin:0 0 18px;padding:16px;background:#F4F5F7;\
                border-radius:10px;text-align:center;font-size:30px;font-weight:700;\
                letter-spacing:6px;color:#1F2933;font-family:'SFMono-Regular',Consolas,monospace;">%s</div>
                """.formatted(escape(code));
    }

    private String paragraphBlock(String paragraph) {
        // Single newlines inside a paragraph become line breaks; the escape happens first, so the
        // <br> below is the only markup that can ever appear in the result.
        String withBreaks = escape(paragraph).replace("\n", "<br>");
        return """
                          <p style="margin:0 0 14px;">%s</p>
                """.formatted(withBreaks);
    }

    /** Splits on blank lines, trimming each block and dropping empty ones. */
    private static List<String> paragraphsOf(String body) {
        List<String> out = new ArrayList<>();
        for (String block : body.strip().split("\n\s*\n")) {
            String trimmed = block.strip();
            if (!trimmed.isEmpty()) {
                out.add(trimmed);
            }
        }
        return out;
    }

    /**
     * The whole safety property of this class.
     *
     * <p>Ampersand first: escaping it after the others would double-escape the entities they
     * produce, and {@code &lt;} would reach the inbox as literal text.
     */
    private static String escape(String value) {
        return value
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
}

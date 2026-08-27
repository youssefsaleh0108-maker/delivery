package com.delivery.appnotification.service;

/**
 * The one place chat text is allowed in from a person.
 *
 * <p>Every route into {@code chat_messages} goes through {@link #normalise}, so the guarantees below
 * hold for the whole feature rather than for whichever caller remembered to check.
 *
 * <p><strong>Too long is refused, never truncated</strong> — the opposite of what
 * {@code PushPreparer} does, and for a reason that is worth stating because the inconsistency looks
 * like an oversight otherwise. A push notification is a glance on a lock screen: a shortened title
 * still does its job. A chat message is a person speaking, and cutting one short changes what they
 * said — "leave it at the back door, not the front" truncated mid-sentence reverses the
 * instruction. A sender who is told their message was too long retypes it; a sender whose message
 * was silently shortened has no idea the rider read something else.
 *
 * <p><strong>Control characters are refused</strong> for two separate reasons. U+0000 cannot be
 * stored in a Postgres {@code text} column at all, so it would surface as a constraint violation
 * from deep inside a transaction rather than as a 422. The rest — bells, escapes, the C1 block —
 * are invisible: they let a sender pad a message so that the length shown to them and the length
 * that arrives disagree, and they render as garbage or as terminal escapes in whatever support tool
 * eventually reads the transcript. Newline and tab are the two a person actually types, so those
 * survive.
 *
 * <p>Note what is <em>not</em> done here: no HTML escaping, no stripping of angle brackets, no
 * "sanitising". The body is stored exactly as typed and only ever leaves this service as a JSON
 * string value, where Jackson escapes it — that is what makes a quote, a newline or a
 * {@code </script>} inert both in the STOMP frame and in the push payload. Escaping on the way in
 * would corrupt the message for a client that renders it as text (every one of ours does) and would
 * still not save a client that renders it as HTML.
 */
final class ChatMessageText {

    private ChatMessageText() {
    }

    /**
     * @param raw           what the sender typed
     * @param maxCodePoints the cap, counted in code points so an emoji costs one character rather
     *                      than two — a cap that counts UTF-16 units tells a customer their
     *                      perfectly ordinary message is twice as long as it looks
     * @return the text to store
     * @throws MessageRejectedException if it is empty, over the cap, or carries control characters
     */
    static String normalise(String raw, int maxCodePoints) {
        if (raw == null) {
            throw new MessageRejectedException("A message needs some text");
        }

        // CRLF from a desktop client and LF from a phone are the same message; normalising before
        // measuring means the cap does not depend on which keyboard sent it.
        String text = raw.replace("\r\n", "\n").replace('\r', '\n').strip();

        if (text.isEmpty()) {
            throw new MessageRejectedException("A message needs some text");
        }

        int offending = text.codePoints()
                .filter(ChatMessageText::isDisallowedControl)
                .findFirst()
                .orElse(-1);
        if (offending >= 0) {
            // The character itself is not echoed back. It is untrusted input, and a response that
            // repeats it hands the sender a way to get their bytes into someone else's error
            // renderer.
            throw new MessageRejectedException("A message cannot contain control characters");
        }

        int length = text.codePointCount(0, text.length());
        if (length > maxCodePoints) {
            throw new MessageRejectedException(
                    "A message may be at most " + maxCodePoints + " characters; this one is " + length);
        }

        return text;
    }

    private static boolean isDisallowedControl(int codePoint) {
        if (codePoint == '\n' || codePoint == '\t') {
            return false;
        }
        // C0 and C1. Character.isISOControl covers exactly these two ranges.
        return Character.isISOControl(codePoint);
    }

    /**
     * Cuts text down for a lock-screen preview.
     *
     * <p>The one place truncation IS right, because the preview is not the message: the message is
     * already stored in full and the app shows it in full when opened. The preview only has to say
     * "there is something here" convincingly enough to be worth tapping.
     */
    static String preview(String text, int maxCodePoints) {
        int length = text.codePointCount(0, text.length());
        if (length <= maxCodePoints) {
            return text;
        }
        // offsetByCodePoints, not substring(int), so the cut never lands between the two halves of
        // a surrogate pair and produces a lone unpaired char that some JSON encoders reject.
        int end = text.offsetByCodePoints(0, maxCodePoints - 1);
        return text.substring(0, end) + "…";
    }
}

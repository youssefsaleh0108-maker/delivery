package com.delivery.appnotification.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The gate every piece of chat text passes through on its way into the database.
 *
 * <p>Worth its own test because it is the only place in the feature where the sender's own bytes are
 * inspected, and because its central rule is the opposite of the one {@code PushPreparer} follows.
 * A push is truncated; a message is refused. Shortening what somebody said changes what they said —
 * "leave it at the back door, not the front" cut in half reverses the instruction — so the sender
 * has to be told, not quietly edited.
 */
class ChatMessageTextTest {

    /**
     * Built from character codes rather than written into the source as literals. A raw NUL or
     * escape byte in a .java file makes it a binary file to every tool that touches it, and the next
     * person to edit this test would have no way to see what they were looking at.
     */
    private static final char NUL = 0;
    private static final char BELL = 7;
    private static final char ESCAPE = 27;
    /** NEL, from the C1 block: invisible, and above the "anything below a space" range. */
    private static final char NEXT_LINE = 0x85;

    @Nested
    @DisplayName("text that is too long")
    class TooLong {

        @Test
        @DisplayName("is refused outright rather than shortened to fit")
        void is_refused_rather_than_truncated() {
            assertThatThrownBy(() -> ChatMessageText.normalise("x".repeat(11), 10))
                    .isInstanceOf(MessageRejectedException.class);
        }

        @Test
        @DisplayName("is told how long it may be and how long it was, so the sender can fix it")
        void says_the_limit_and_the_actual_length() {
            assertThatThrownBy(() -> ChatMessageText.normalise("x".repeat(11), 10))
                    .hasMessageContaining("10")
                    .hasMessageContaining("11");
        }

        @Test
        @DisplayName("is measured exactly at the boundary, so the documented cap is the real cap")
        void the_cap_itself_is_allowed() {
            assertThat(ChatMessageText.normalise("x".repeat(10), 10)).hasSize(10);
        }

        /**
         * An emoji is one character to the person who typed it. Counting UTF-16 units would tell a
         * customer their perfectly ordinary message is twice as long as it looks.
         */
        @Test
        @DisplayName("counts an emoji as one character, not as the two units it is stored in")
        void counts_code_points_not_utf16_units() {
            String fiveScooters = "🛵".repeat(5);

            assertThat(fiveScooters).hasSize(10);
            assertThat(ChatMessageText.normalise(fiveScooters, 5)).isEqualTo(fiveScooters);
        }
    }

    @Nested
    @DisplayName("text with nothing in it")
    class Empty {

        @Test
        @DisplayName("is refused, whether it is absent, blank or only whitespace")
        void is_refused() {
            assertThatThrownBy(() -> ChatMessageText.normalise(null, 100))
                    .isInstanceOf(MessageRejectedException.class);
            assertThatThrownBy(() -> ChatMessageText.normalise("", 100))
                    .isInstanceOf(MessageRejectedException.class);
            assertThatThrownBy(() -> ChatMessageText.normalise("   \n\t ", 100))
                    .isInstanceOf(MessageRejectedException.class);
        }
    }

    @Nested
    @DisplayName("control characters")
    class ControlCharacters {

        /**
         * Postgres cannot store U+0000 in a text column at all. Refusing it here turns what would
         * be a constraint violation from deep inside a transaction into a 422 the sender can read.
         */
        @Test
        @DisplayName("a NUL byte is refused rather than left to fail the insert")
        void a_nul_is_refused() {
            assertThatThrownBy(() -> ChatMessageText.normalise("hello" + NUL + "world", 100))
                    .isInstanceOf(MessageRejectedException.class);
        }

        @Test
        @DisplayName("escapes and other invisibles are refused, since a reader cannot see them")
        void invisible_controls_are_refused() {
            assertThatThrownBy(() -> ChatMessageText.normalise("hello" + BELL + "world", 100))
                    .isInstanceOf(MessageRejectedException.class);
            assertThatThrownBy(() -> ChatMessageText.normalise("hello" + ESCAPE + "[2Jworld", 100))
                    .isInstanceOf(MessageRejectedException.class);
            assertThatThrownBy(() -> ChatMessageText.normalise("hello" + NEXT_LINE + "world", 100))
                    .isInstanceOf(MessageRejectedException.class);
        }

        /** The two a person actually presses. Refusing them would forbid a two-line message. */
        @Test
        @DisplayName("newline and tab survive, because people type them")
        void newline_and_tab_survive() {
            assertThat(ChatMessageText.normalise("first\nsecond\tthird", 100))
                    .isEqualTo("first\nsecond\tthird");
        }

        /** The offending character is the sender's own input; echoing it back would re-emit it. */
        @Test
        @DisplayName("the refusal does not quote the offending character back at the sender")
        void the_refusal_does_not_echo_the_input() {
            assertThatThrownBy(() -> ChatMessageText.normalise("hi" + BELL + "there", 100))
                    .hasMessageNotContaining(String.valueOf(BELL))
                    .hasMessageNotContaining("there");
        }
    }

    @Nested
    @DisplayName("text as typed")
    class AsTyped {

        /**
         * Nothing is escaped, stripped or rewritten on the way in. The body leaves this service only
         * as a JSON string value, where the encoder escapes it — doing it here as well would corrupt
         * the message for every client that renders it as text, which is all of ours.
         */
        @Test
        @DisplayName("quotes, braces and markup are stored exactly as the sender wrote them")
        void punctuation_and_markup_are_left_alone() {
            String awkward = "it's \"fine\" <script>alert(1)</script> {\"a\":1}";

            assertThat(ChatMessageText.normalise(awkward, 200)).isEqualTo(awkward);
        }

        /** CRLF from a laptop and LF from a phone are the same message and must measure the same. */
        @Test
        @DisplayName("windows line endings do not make a message longer than the same one typed on a phone")
        void line_endings_are_normalised_before_measuring() {
            assertThat(ChatMessageText.normalise("a\r\nb", 3)).isEqualTo("a\nb");
        }

        @Test
        @DisplayName("surrounding whitespace is trimmed, so a stray newline is not a message")
        void surrounding_whitespace_is_trimmed() {
            assertThat(ChatMessageText.normalise("  on my way  ", 100)).isEqualTo("on my way");
        }
    }

    @Nested
    @DisplayName("the lock-screen preview")
    class Preview {

        /**
         * The one place cutting text IS right: the message itself is already stored in full, and the
         * preview only has to be worth tapping.
         */
        @Test
        @DisplayName("is shortened rather than refused, because it is not the message")
        void is_shortened() {
            assertThat(ChatMessageText.preview("x".repeat(50), 10))
                    .hasSize(10)
                    .endsWith("…");
        }

        @Test
        @DisplayName("leaves a short message alone rather than decorating it")
        void leaves_short_text_alone() {
            assertThat(ChatMessageText.preview("on my way", 120)).isEqualTo("on my way");
        }

        /**
         * A cut between the two halves of a surrogate pair leaves an unpaired char that some JSON
         * encoders refuse — which would turn a long emoji message into no push at all.
         */
        @Test
        @DisplayName("never cuts an emoji in half and leaves an unencodable fragment behind")
        void never_splits_a_surrogate_pair() {
            String preview = ChatMessageText.preview("🛵".repeat(20), 5);

            assertThat(preview.codePointCount(0, preview.length())).isEqualTo(5);
            assertThat(Character.isHighSurrogate(preview.charAt(preview.length() - 2))).isFalse();
        }
    }
}

package com.delivery.connector.email;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

@DisplayName("the branded email layout")
class EmailHtmlLayoutTest {

    private final EmailHtmlLayout layout = new EmailHtmlLayout("YouDrop", "#C41D4E");

    @Nested
    @DisplayName("escaping, which is the reason this was safe to add")
    class Escaping {

        @Test
        @DisplayName("renders markup in the body as text, not markup")
        void escapesBody() {
            String html = layout.render("Your order",
                    "Your order of <script>alert(1)</script> is on its way.");

            assertThat(html).doesNotContain("<script>");
            assertThat(html).contains("&lt;script&gt;");
        }

        @Test
        @DisplayName("escapes a product name that closes the surrounding tag")
        void escapesTagBreakout() {
            String html = layout.render("Receipt", "1 x </p><img src=x onerror=alert(1)>");

            assertThat(html).doesNotContain("<img");
            assertThat(html).contains("&lt;img");
        }

        @Test
        @DisplayName("escapes the subject too, which is interpolated into the title")
        void escapesSubject() {
            String html = layout.render("</title><script>x</script>", "Anything.");

            assertThat(html).doesNotContain("<script>");
        }

        @Test
        @DisplayName("escapes ampersands once, so entities do not arrive doubled")
        void escapesAmpersandOnce() {
            String html = layout.render("Receipt", "Fish & chips");

            assertThat(html).contains("Fish &amp; chips");
            assertThat(html).doesNotContain("&amp;amp;");
        }
    }

    @Nested
    @DisplayName("a one-time code")
    class Codes {

        @Test
        @DisplayName("is shown as a code block when it stands on its own first line")
        void codeBlock() {
            String html = layout.render("071037 is your code",
                    "071037\n\nUse this code to confirm your email address.");

            assertThat(html).contains("letter-spacing:6px");
            assertThat(html).contains("071037");
        }

        @Test
        @DisplayName("leaves an ordinary message alone")
        void ordinaryMessage() {
            String html = layout.render("Your order",
                    "Your order is on its way.\n\nIt should arrive in 20 minutes.");

            assertThat(html).doesNotContain("letter-spacing:6px");
        }

        @Test
        @DisplayName("does not treat a number inside a sentence as a code")
        void numberInSentence() {
            String html = layout.render("Your order", "Order 4821 is on its way.");

            assertThat(html).doesNotContain("letter-spacing:6px");
        }
    }

    @Test
    @DisplayName("carries the brand, so the mail is recognisably from us")
    void brands() {
        String html = layout.render("Anything", "Anything.");

        assertThat(html).contains("YouDrop");
        assertThat(html).contains("#C41D4E");
    }

    @Test
    @DisplayName("keeps a line break inside a paragraph as a break and nothing else")
    void lineBreaks() {
        String html = layout.render("Anything", "One line\nsecond line");

        assertThat(html).contains("One line<br>second line");
    }
}

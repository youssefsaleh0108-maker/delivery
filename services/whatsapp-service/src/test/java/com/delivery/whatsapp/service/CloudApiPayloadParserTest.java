package com.delivery.whatsapp.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.util.List;

import org.junit.jupiter.api.Test;

import com.delivery.whatsapp.domain.WhatsAppMessage;
import com.fasterxml.jackson.databind.ObjectMapper;

class CloudApiPayloadParserTest {

    private final CloudApiPayloadParser parser = new CloudApiPayloadParser();
    private final ObjectMapper mapper = new ObjectMapper();

    private List<InboundMessage> parse(String json) throws Exception {
        return parser.parse(mapper.readTree(json));
    }

    private String envelope(String contacts, String messages) {
        return """
                {"object":"whatsapp_business_account","entry":[{"id":"WABA","changes":[{
                  "field":"messages","value":{
                    "messaging_product":"whatsapp",
                    "metadata":{"display_phone_number":"96170000000","phone_number_id":"PN1"},
                    "contacts":[%s],
                    "messages":[%s]}}]}]}
                """.formatted(contacts, messages);
    }

    @Test
    void liftsATextMessageOutOfTheEnvelope() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.AAA","timestamp":"1755000000",
                 "type":"text","text":{"body":"two shawarma please"}}"""));

        assertThat(parsed).hasSize(1);
        InboundMessage message = parsed.get(0);
        assertThat(message.phoneNumberId()).isEqualTo("PN1");
        assertThat(message.customerWaId()).isEqualTo("96171234567");
        assertThat(message.customerName()).isEqualTo("Rana");
        assertThat(message.providerMessageId()).isEqualTo("wamid.AAA");
        assertThat(message.body()).isEqualTo("two shawarma please");
        assertThat(message.kind()).isEqualTo(WhatsAppMessage.Kind.TEXT);
        assertThat(message.sentAt()).isEqualTo(Instant.ofEpochSecond(1755000000L));
    }

    @Test
    void keepsTheTextVerbatim() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.BBB","timestamp":"1755000000",
                 "type":"text","text":{"body":"  2 kebab, NO onions  "}}"""));

        // Not trimmed, not normalised. The merchant is reading this to decide what to send, and
        // "no onions" is exactly the kind of detail a tidy-up would eat.
        assertThat(parsed.get(0).body()).isEqualTo("  2 kebab, NO onions  ");
    }

    @Test
    void readsArabicUnchanged() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"\\u0631\\u0627\\u0646\\u0627"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.CCC","timestamp":"1755000000",
                 "type":"text","text":{"body":"\\u0634\\u0643\\u0631\\u0627"}}"""));

        assertThat(parsed.get(0).customerName()).isEqualTo("رانا");
        assertThat(parsed.get(0).body()).isEqualTo("شكرا");
    }

    @Test
    void recordsAVoiceNoteWithNoBodyRatherThanDroppingIt() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.DDD","timestamp":"1755000000",
                 "type":"audio","audio":{"id":"MEDIA1","voice":true}}"""));

        // A merchant who sees nothing where a voice note arrived concludes the platform lost it and
        // chases the wrong problem. The type is the honest answer.
        assertThat(parsed).hasSize(1);
        assertThat(parsed.get(0).kind()).isEqualTo(WhatsAppMessage.Kind.AUDIO);
        assertThat(parsed.get(0).body()).isNull();
    }

    @Test
    void keepsTheCaptionOnAPhoto() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.EEE","timestamp":"1755000000",
                 "type":"image","image":{"id":"MEDIA2","caption":"2 of these please"}}"""));

        // Often the whole order.
        assertThat(parsed.get(0).kind()).isEqualTo(WhatsAppMessage.Kind.IMAGE);
        assertThat(parsed.get(0).body()).isEqualTo("2 of these please");
    }

    @Test
    void rendersADroppedPinAsSomethingReadable() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.FFF","timestamp":"1755000000",
                 "type":"location","location":{"latitude":33.888,"longitude":35.495,
                 "name":"Hamra"}}"""));

        assertThat(parsed.get(0).kind()).isEqualTo(WhatsAppMessage.Kind.LOCATION);
        assertThat(parsed.get(0).body()).contains("Hamra").contains("33.888").contains("35.495");
    }

    @Test
    void unknownTypesBecomeOtherRatherThanAnError() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.GGG","timestamp":"1755000000",
                 "type":"sticker","sticker":{"id":"MEDIA3"}}"""));

        // The provider ships new message types whenever it likes; a strict binding would start
        // rejecting real customers on the day they do.
        assertThat(parsed).hasSize(1);
        assertThat(parsed.get(0).kind()).isEqualTo(WhatsAppMessage.Kind.OTHER);
    }

    @Test
    void dropsAMessageWithNoProviderId() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","timestamp":"1755000000",
                 "type":"text","text":{"body":"hello"}}"""));

        // Without an id it cannot be deduplicated, and a duplicate is worse than a gap here: it
        // invites the merchant to send the same order twice.
        assertThat(parsed).isEmpty();
    }

    @Test
    void unpacksSeveralCustomersFromOneCallback() throws Exception {
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171111111"},\
                {"profile":{"name":"Sami"},"wa_id":"96172222222"}""",
                """
                {"from":"96171111111","id":"wamid.H1","timestamp":"1755000000",
                 "type":"text","text":{"body":"one"}},\
                {"from":"96172222222","id":"wamid.H2","timestamp":"1755000001",
                 "type":"text","text":{"body":"two"}}"""));

        assertThat(parsed).hasSize(2);
        assertThat(parsed).extracting(InboundMessage::customerName)
                .containsExactly("Rana", "Sami");
    }

    @Test
    void ignoresAStatusOnlyCallback() throws Exception {
        List<InboundMessage> parsed = parse("""
                {"object":"whatsapp_business_account","entry":[{"id":"WABA","changes":[{
                  "field":"messages","value":{
                    "messaging_product":"whatsapp",
                    "metadata":{"phone_number_id":"PN1"},
                    "statuses":[{"id":"wamid.OUT","status":"delivered"}]}}]}]}
                """);

        // These are about our own outbound messages. Nothing in this feature acts on them, so they
        // are skipped rather than half-handled.
        assertThat(parsed).isEmpty();
    }

    @Test
    void survivesAnEnvelopeWithNothingInIt() throws Exception {
        assertThat(parse("{}")).isEmpty();
        assertThat(parse("""
                {"entry":[{"changes":[]}]}""")).isEmpty();
        assertThat(parser.parse(null)).isEmpty();
    }

    @Test
    void fallsBackToNowWhenTheTimestampIsUnreadable() throws Exception {
        Instant before = Instant.now().minusSeconds(1);
        List<InboundMessage> parsed = parse(envelope(
                """
                {"profile":{"name":"Rana"},"wa_id":"96171234567"}""",
                """
                {"from":"96171234567","id":"wamid.III","timestamp":"not-a-number",
                 "type":"text","text":{"body":"hi"}}"""));

        // The message still has to appear in the thread; the bottom is the least wrong place.
        assertThat(parsed.get(0).sentAt()).isAfter(before);
    }

    @Test
    void toleratesAMissingContactBlock() throws Exception {
        List<InboundMessage> parsed = parse(envelope("",
                """
                {"from":"96171234567","id":"wamid.JJJ","timestamp":"1755000000",
                 "type":"text","text":{"body":"hi"}}"""));

        // The display name is absent surprisingly often. The number is always there, and the
        // conversation is identified by it anyway.
        assertThat(parsed).hasSize(1);
        assertThat(parsed.get(0).customerName()).isNull();
        assertThat(parsed.get(0).customerWaId()).isEqualTo("96171234567");
    }
}

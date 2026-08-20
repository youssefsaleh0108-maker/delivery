package com.delivery.platform.notifications;

import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.servlet.http.HttpServletRequest;

/**
 * Where a carrier tells us what actually happened to a message we sent.
 *
 * <p>This is the one endpoint in the platform that is <strong>deliberately public</strong>, and it
 * is worth being explicit about why, because {@link ConnectorSendController} sitting beside it says
 * the opposite. A vendor's callback originates on the public internet from a machine that holds no
 * token of ours and never will; there is no JWT to demand. So the authentication here is the
 * vendor's own signature over the payload, checked by the provider's
 * {@link DeliveryReceiptTranslator} before a single field is read. That is a real authentication
 * boundary, not a weaker one — but it is a different one, which is exactly why this lives on its own
 * path and its own controller rather than being bolted onto the internal-only send route.
 *
 * <p><strong>Path matters.</strong> Not under {@code /api/connector/**}: that prefix is unrouted at
 * the Gateway on purpose, and the Phase 5 suite asserts it stays that way. Routing this path does
 * not widen that one.
 *
 * <p>Receipts go onto the bus rather than being written straight to the database. The connector has
 * no access to the notification schema — each service owns its own (Section 4) — and going through
 * the bus also means a carrier retry storm queues up behind Notifications Manager instead of
 * hammering it.
 */
@RestController
public class DlrWebhookController {

    /** Public prefix; the Gateway routes exactly this and nothing else of the connector's. */
    public static final String PATH = "/webhooks/dlr";

    private static final Logger log = LoggerFactory.getLogger(DlrWebhookController.class);

    private final Map<String, DeliveryReceiptTranslator> translators = new LinkedHashMap<>();
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;

    public DlrWebhookController(List<DeliveryReceiptTranslator> translators,
                                RabbitTemplate rabbit,
                                ObjectMapper objectMapper,
                                String dlrExchange) {
        translators.forEach(t -> this.translators.put(t.name().toUpperCase(), t));
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = dlrExchange;
    }

    @PostMapping(PATH + "/{provider}")
    public ResponseEntity<Void> receive(@PathVariable String provider, HttpServletRequest request) {
        DeliveryReceiptTranslator translator = translators.get(provider.toUpperCase());
        if (translator == null) {
            // 404 rather than a hint about which providers exist: this endpoint is internet-facing
            // and enumerating our vendor list for an unauthenticated caller serves no one.
            log.warn("DLR callback for unknown provider {}", provider);
            return ResponseEntity.notFound().build();
        }

        Map<String, String> headers = headersOf(request);
        Map<String, String> form = formOf(request);
        String rawBody = rawBodyOf(request);

        if (!translator.verify(requestUrl(request), headers, form, rawBody)) {
            // Deliberately terse and deliberately loud in the log. A forged receipt and a
            // misconfigured secret look identical from here, and the second one silently discards
            // real delivery data until someone notices — so it must not be logged at debug.
            log.warn("Rejected an unverified DLR callback for provider {}", provider);
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        List<ProviderDeliveryReceipt> receipts = translator.translate(form, rawBody);
        for (ProviderDeliveryReceipt receipt : receipts) {
            publish(receipt);
        }

        if (receipts.isEmpty()) {
            // An intermediate state, correctly recognised as not-an-outcome. Still a 2xx: the
            // vendor did nothing wrong and retrying would not improve matters.
            log.debug("DLR callback from {} carried no terminal outcome", provider);
        }
        return ResponseEntity.noContent().build();
    }

    private void publish(ProviderDeliveryReceipt receipt) {
        try {
            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            // The vendor's id is the only identity a receipt has, so it is also its dedup key.
            props.setMessageId(receipt.provider() + ':' + receipt.providerMessageId());
            rabbit.send(exchange, ProviderDeliveryReceipt.ROUTING_KEY,
                    new Message(objectMapper.writeValueAsBytes(receipt), props));
        } catch (Exception e) {
            // Swallowed so one malformed receipt in a batched callback cannot cost us the rest, and
            // so the vendor is not told to retry a payload we already verified.
            log.error("Could not publish DLR for {} message {}",
                    receipt.provider(), receipt.providerMessageId(), e);
        }
    }

    /**
     * The URL as the vendor called it. Several vendors sign it, so a proxy that rewrites the host
     * or scheme silently breaks verification — which is why the forwarded headers win when present.
     */
    private String requestUrl(HttpServletRequest request) {
        String forwardedProto = request.getHeader("X-Forwarded-Proto");
        String forwardedHost = request.getHeader("X-Forwarded-Host");
        StringBuilder url = new StringBuilder();
        url.append(forwardedProto != null ? forwardedProto : request.getScheme()).append("://");
        url.append(forwardedHost != null ? forwardedHost
                : request.getServerName() + portSuffix(request));
        url.append(request.getRequestURI());
        if (request.getQueryString() != null) {
            url.append('?').append(request.getQueryString());
        }
        return url.toString();
    }

    private String portSuffix(HttpServletRequest request) {
        int port = request.getServerPort();
        boolean isDefault = ("http".equals(request.getScheme()) && port == 80)
                || ("https".equals(request.getScheme()) && port == 443);
        return isDefault ? "" : ":" + port;
    }

    private Map<String, String> headersOf(HttpServletRequest request) {
        Map<String, String> headers = new LinkedHashMap<>();
        Collections.list(request.getHeaderNames())
                .forEach(name -> headers.put(name.toLowerCase(), request.getHeader(name)));
        return headers;
    }

    private Map<String, String> formOf(HttpServletRequest request) {
        Map<String, String> form = new LinkedHashMap<>();
        request.getParameterMap().forEach((key, values) -> {
            if (values != null && values.length > 0) {
                form.put(key, values[0]);
            }
        });
        return form;
    }

    /**
     * The body verbatim, for vendors that sign bytes rather than fields.
     *
     * <p>Empty for form-encoded callbacks, and that is not a bug: the servlet container has already
     * consumed the stream to build the parameter map, so the bytes are genuinely gone. Form-signing
     * vendors therefore have to sign the fields, which is what they all in fact do.
     */
    private String rawBodyOf(HttpServletRequest request) {
        String contentType = request.getContentType();
        if (contentType != null
                && contentType.toLowerCase().startsWith(MediaType.APPLICATION_FORM_URLENCODED_VALUE)) {
            return "";
        }
        try {
            return new String(request.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        } catch (Exception e) {
            log.warn("Could not read DLR request body", e);
            return "";
        }
    }
}

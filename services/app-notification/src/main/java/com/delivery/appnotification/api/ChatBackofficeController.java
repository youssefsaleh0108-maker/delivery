package com.delivery.appnotification.api;

import java.util.List;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.appnotification.domain.ChatMessage;
import com.delivery.appnotification.service.ChatService;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.security.CurrentUser;

/**
 * Support reading a conversation it is not a party to.
 *
 * <p><strong>This is a deliberate exception to the two-participant rule, and it is worth stating
 * plainly why it exists.</strong> The disputes this feature generates — "I told the rider to leave
 * it at the door", "the customer never answered" — are decided on what was actually said, and an
 * agent who cannot read the thread can only take one person's word. Refusing support the access
 * does not make the read stop happening; it relocates it to whoever holds a database password,
 * where there is no role check, no stated reason and no record.
 *
 * <p>So it is granted, narrowly:
 * <ul>
 *   <li><strong>A separate controller and a separate service method.</strong> The participant
 *       endpoints have no backoffice branch to widen, so no ordinary read can drift into this.</li>
 *   <li><strong>Read-only.</strong> There is no support endpoint that posts. A transcript stays a
 *       record of what the two people said to each other, and an agent's words appearing inside it
 *       would corrupt the only artefact the dispute turns on.</li>
 *   <li><strong>Audited, transactionally.</strong> A row lands in {@code chat_transcript_access}
 *       before the transcript is returned, and if it cannot be written the request fails.</li>
 *   <li><strong>A reason is required</strong> and it is not optional-with-a-default, so the audit
 *       trail says why rather than only that. A ticket reference is what this is for.</li>
 *   <li><strong>Switchable off</strong> — {@code delivery.chat.backoffice-transcript-access} — for a
 *       deployment whose legal position does not allow it.</li>
 * </ul>
 *
 * <p>Not routed to riders or customers by any client. It is a backoffice tool and the role check is
 * what enforces that; {@code ROLE_BACKOFFICE} comes from the realm, not from anything the caller
 * sends.
 */
// Deliberately NOT @Validated. Spring 6.1 validates constrained controller method parameters
// itself and answers a violated @RequestParam with 400; adding @Validated switches that off in
// favour of the AOP proxy, whose ConstraintViolationException nothing here maps, and a missing
// reason would come back as a 500. The annotation looks like belt and braces and is the opposite.
@RestController
@RequestMapping("/api/chat/backoffice")
@PreAuthorize("hasRole('BACKOFFICE')")
public class ChatBackofficeController {

    private final ChatService chat;

    public ChatBackofficeController(ChatService chat) {
        this.chat = chat;
    }

    /**
     * The transcript of one conversation.
     *
     * @param reason why it is being read — recorded in the audit row, required, and capped at the
     *               column width so a long paste cannot fail the insert after the read was already
     *               authorised
     */
    @GetMapping("/conversations/{conversationId}/messages")
    public List<TranscriptMessage> transcript(
            @PathVariable UUID conversationId,
            @RequestParam @NotBlank @Size(min = 3, max = 200) String reason) {

        return chat.transcriptForSupport(conversationId, CurrentUser.requireId(), reason.strip(),
                        MDC.get(CorrelationIdFilter.MDC_KEY)).stream()
                .map(TranscriptMessage::of)
                .toList();
    }

    /**
     * A message as support sees it.
     *
     * <p>Role rather than user id, same as the participant view. An agent settling a dispute needs
     * to know which of the two people said a thing, which the role answers completely; the Keycloak
     * subs add nothing to that and would spread two more copies of them into support tooling.
     */
    public record TranscriptMessage(
            UUID id,
            long sequence,
            String senderRole,
            String text,
            java.time.Instant sentAt,
            java.time.Instant deliveredAt,
            java.time.Instant readAt) {

        static TranscriptMessage of(ChatMessage message) {
            return new TranscriptMessage(
                    message.getId(),
                    message.getSequenceNo(),
                    message.getSenderRole().name(),
                    message.getBody(),
                    message.getCreatedAt(),
                    message.getDeliveredAt(),
                    message.getReadAt());
        }
    }
}

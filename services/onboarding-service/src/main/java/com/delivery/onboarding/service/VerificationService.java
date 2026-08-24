package com.delivery.onboarding.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ContactVerification;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.ContactVerificationRepository;

/**
 * Proving that a contact detail belongs to the person typing it.
 *
 * <p>Without this an application can name any address at all, and the two ways that goes wrong are
 * both quiet. A real address belonging to somebody else means the decision — and the account that
 * follows it — is sent to a stranger. An address that does not exist means an approved applicant is
 * provisioned, told nothing, and never signs in, while the platform's own records say they were
 * welcomed.
 *
 * <p><strong>This endpoint sends mail to addresses strangers type, which makes it a spam engine if
 * it is not held down.</strong> Three limits do that: a cooldown so the same address cannot be
 * asked to receive a code every second, a daily cap per destination so it cannot be used to bury
 * somebody's inbox, and an attempt cap on each code so guessing six digits is not a strategy. The
 * limits are counted per destination rather than per caller on purpose — the caller has no account
 * and can change address, but the cost always lands on whoever owns the inbox being hammered.
 */
@Service
public class VerificationService {

    private static final Logger log = LoggerFactory.getLogger(VerificationService.class);

    /** Deliberately permissive: the relay is the real authority on whether an address exists. */
    private static final Pattern EMAIL = Pattern.compile("^[^@\\s]+@[^@\\s.]+(\\.[^@\\s.]+)+$");

    /** E.164-ish. Enough to reject prose, not so strict that it rejects real numbering plans. */
    private static final Pattern PHONE = Pattern.compile("^\\+?[0-9]{7,15}$");

    private final ContactVerificationRepository verifications;
    private final PlatformClient platform;
    private final Duration resendCooldown;
    private final int dailyCap;

    public VerificationService(
            ContactVerificationRepository verifications,
            PlatformClient platform,
            @Value("${delivery.onboarding.verification.resend-cooldown:60s}") Duration resendCooldown,
            @Value("${delivery.onboarding.verification.daily-cap:8}") int dailyCap) {
        this.verifications = verifications;
        this.platform = platform;
        this.resendCooldown = resendCooldown;
        this.dailyCap = dailyCap;
    }

    /** Thrown when a code cannot be sent or checked as asked. Carries wording an applicant can act on. */
    public static class VerificationException extends RuntimeException {
        public VerificationException(String message) {
            super(message);
        }
    }

    /** Thrown when the limits say wait. Separate, so the API can answer 429 rather than 422. */
    public static class TooManyRequestsException extends VerificationException {
        public TooManyRequestsException(String message) {
            super(message);
        }
    }

    // ---------------------------------------------------------------- sending

    /**
     * Sends a code, and returns nothing that identifies it.
     *
     * <p>Note what does not come back: no id, no hint, nothing tying the response to a particular
     * challenge. The next step is confirmed by destination and code alone, so there is nothing here
     * worth stealing and nothing to correlate one request with another.
     */
    @Transactional
    public Instant request(Channel channel, String rawDestination) {
        String destination = normalise(channel, rawDestination);

        Instant now = Instant.now();
        verifications.findFirstByChannelAndDestinationOrderByCreatedAtDesc(channel, destination)
                .ifPresent(previous -> {
                    if (previous.getCreatedAt() != null
                            && previous.getCreatedAt().isAfter(now.minus(resendCooldown))) {
                        throw new TooManyRequestsException(
                                "A code was just sent. Wait a moment before asking for another.");
                    }
                });

        long today = verifications.countByDestinationAndCreatedAtAfter(
                destination, now.minus(Duration.ofDays(1)));
        if (today >= dailyCap) {
            throw new TooManyRequestsException(
                    "That address has been sent too many codes today. Try again tomorrow.");
        }

        ContactVerification.Issued issued = ContactVerification.issue(channel, destination);
        // Saved before sending. A code that goes out and was never recorded cannot be confirmed,
        // which is the one failure the person holding it can do nothing about.
        verifications.saveAndFlush(issued.verification());

        deliver(channel, destination, issued.code());

        log.info("Verification code sent on {} (attempt {} today)", channel, today + 1);
        return issued.verification().getExpiresAt();
    }

    private void deliver(Channel channel, String destination, String code) {
        long minutes = ContactVerification.LIFETIME.toMinutes();

        // The code stands alone on the first line, and everything else follows in prose. That shape
        // is what makes both renderings work: the email layout shows a lone short code as a code
        // block, and on a phone the first thing in the notification preview is the code itself,
        // which is the only part anybody actually wants.
        String emailBody = code + "\n\n"
                + "Use this code to confirm your email address for MyDelivery."
                + " It expires in " + minutes + " minutes and can be used once.\n\n"
                + "If you did not ask for this code, no action is needed —"
                + " somebody may have typed your address by mistake."
                + " Do not share it with anyone; MyDelivery will never ask you for it.";

        // SMS is one line: no layout renders it, and a message split across several parts costs
        // more and can arrive out of order.
        String smsBody = code + " is your MyDelivery verification code. It expires in "
                + minutes + " minutes. Never share it with anyone.";

        try {
            if (channel == Channel.EMAIL) {
                // The code is in the subject as well as the body. That is deliberate and it is a
                // trade: it means somebody can read the code from a preview without opening the
                // mail, which is the fastest path for the person who asked for it and also visible
                // to anyone looking at their screen. Every large provider makes the same call, and
                // the code is already in the body, so this adds no exposure inside our own logs.
                platform.notifyDirect("EMAIL", destination,
                        code + " is your MyDelivery verification code",
                        emailBody, "onboarding.verification");
            } else {
                platform.notifyDirect("SMS", destination, null, smsBody, "onboarding.verification");
            }
        } catch (Exception e) {
            // Told plainly rather than reported as success. "We have sent you a code" is a promise,
            // and a screen that makes it while the send failed leaves somebody waiting for a
            // message that is never coming.
            log.error("Could not send a verification code on {}", channel, e);
            throw new VerificationException(
                    "We could not send the code just now. Please try again in a moment.");
        }
    }

    // ---------------------------------------------------------------- confirming

    /**
     * Checks a code and hands back the proof.
     *
     * @return the token an application presents to show this address was verified
     */
    @Transactional
    public Confirmed confirm(Channel channel, String rawDestination, String code) {
        String destination = normalise(channel, rawDestination);

        ContactVerification verification = verifications
                .findFirstByChannelAndDestinationOrderByCreatedAtDesc(channel, destination)
                // Worded the same as a wrong code, deliberately. "No code was requested for that
                // address" tells a stranger which addresses are mid-application, which is a fact
                // about somebody else that they asked for by guessing.
                .orElseThrow(() -> new VerificationException(
                        "That code is not right, or it has expired. Ask for a new one."));

        ContactVerification.Outcome outcome = verification.confirm(code);
        verifications.save(verification);

        return switch (outcome) {
            case CONFIRMED -> new Confirmed(verification.getToken(), destination);
            case EXPIRED -> throw new VerificationException(
                    "That code has expired. Ask for a new one.");
            case TOO_MANY_ATTEMPTS -> throw new VerificationException(
                    "Too many wrong attempts. Ask for a new code.");
            case ALREADY_USED -> throw new VerificationException(
                    "That code has already been used. Ask for a new one.");
            case WRONG -> throw new VerificationException(
                    "That code is not right, or it has expired. Ask for a new one.");
        };
    }

    public record Confirmed(String token, String destination) {
    }

    // ---------------------------------------------------------------- spending

    /**
     * Spends a proof, checking it was issued for the address it is being used for.
     *
     * <p>The destination check is the whole point and is easy to leave out. Without it a valid token
     * for an address somebody does own would verify an application naming an address they do not —
     * verify your own inbox once, then apply as anybody.
     */
    @Transactional
    public Instant consume(String token, Channel channel, String expectedDestination) {
        String destination = normalise(channel, expectedDestination);

        ContactVerification verification = verifications.findByToken(token)
                .orElseThrow(() -> new VerificationException(
                        "That " + channel.name().toLowerCase(Locale.ROOT)
                                + " has not been verified"));

        if (verification.getChannel() != channel
                || !verification.getDestination().equals(destination)) {
            throw new VerificationException(
                    "That verification was for a different " + channel.name().toLowerCase(Locale.ROOT));
        }
        if (!verification.isUsable()) {
            throw new VerificationException(
                    "That verification is no longer valid. Please verify again.");
        }

        verification.consume();
        verifications.save(verification);
        return verification.getConfirmedAt();
    }

    /** Whether a token would be accepted, without spending it. For validating a form as it is filled. */
    @Transactional(readOnly = true)
    public boolean isVerified(String token, Channel channel, String destination) {
        return verifications.findByToken(token)
                .filter(ContactVerification::isUsable)
                .filter(v -> v.getChannel() == channel)
                .filter(v -> v.getDestination().equals(normalise(channel, destination)))
                .isPresent();
    }

    // ---------------------------------------------------------------- shaping

    /**
     * One address, one spelling.
     *
     * <p>Without this "Sam@Example.com" and "sam@example.com" are two separate challenges to the
     * same inbox — which defeats the rate limit, since a determined sender only has to vary the
     * capitalisation to start again from zero.
     */
    public static String normalise(Channel channel, String raw) {
        if (raw == null || raw.isBlank()) {
            throw new VerificationException("Enter " + (channel == Channel.EMAIL
                    ? "an email address" : "a phone number"));
        }
        String value = raw.trim();

        if (channel == Channel.EMAIL) {
            value = value.toLowerCase(Locale.ROOT);
            if (!EMAIL.matcher(value).matches()) {
                throw new VerificationException("That does not look like an email address");
            }
            return value;
        }

        // Spaces, dashes and brackets are how people write phone numbers and none of them are part
        // of the number. Stripped so the same phone typed two ways is one destination.
        value = value.replaceAll("[\\s()\\-.]", "");
        if (!PHONE.matcher(value).matches()) {
            throw new VerificationException("That does not look like a phone number");
        }
        return value;
    }

    /** For the API layer, which needs the normalised form to echo back to the form. */
    public static Optional<String> normaliseQuietly(Channel channel, String raw) {
        try {
            return Optional.of(normalise(channel, raw));
        } catch (VerificationException e) {
            return Optional.empty();
        }
    }
}

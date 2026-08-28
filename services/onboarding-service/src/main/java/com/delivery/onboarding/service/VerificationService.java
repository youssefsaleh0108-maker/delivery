package com.delivery.onboarding.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Optional;
import java.util.function.BooleanSupplier;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.domain.ContactVerification;
import com.delivery.onboarding.domain.ContactVerification.Channel;
import com.delivery.onboarding.domain.ContactVerification.Purpose;
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

    /**
     * E.164, and deliberately the SAME rule the SMS connector enforces: a leading +, a non-zero
     * country digit, then up to 14 more.
     *
     * <p>It used to be {@code ^\+?[0-9]{7,15}$} — the plus optional — and that one character cost
     * every applicant who typed a national number their verification code. This service accepted
     * {@code 71423308}, answered 200, issued a code and handed it on; {@code SmsPreparer} requires
     * the plus, refused it, and dead-lettered the message. Nothing failed anywhere the applicant
     * could see: they sat on the verify screen waiting for an SMS that was never sendable.
     *
     * <p>So the two rules have to agree, and the number a person actually types has to be turned
     * into one that satisfies both — see {@link #toE164}. If that ever drifts again, the symptom is
     * silent, which is why {@code phone_numbers_are_normalised_to_what_the_sms_connector_accepts}
     * asserts this pattern against the connector's own spelling of it.
     */
    private static final Pattern PHONE = Pattern.compile("^\\+[1-9]\\d{7,14}$");

    /** What a configured dialling code may look like: a plus and one to three digits. */
    private static final Pattern DIAL_CODE = Pattern.compile("^\\+[1-9]\\d{0,3}$");

    private final ContactVerificationRepository verifications;
    private final PlatformClient platform;
    private final Duration resendCooldown;
    private final int dailyCap;
    private final String defaultDialCode;

    public VerificationService(
            ContactVerificationRepository verifications,
            PlatformClient platform,
            @Value("${delivery.onboarding.verification.resend-cooldown:60s}") Duration resendCooldown,
            @Value("${delivery.onboarding.verification.daily-cap:8}") int dailyCap,
            @Value("${delivery.onboarding.verification.default-dial-code:+961}") String defaultDialCode) {
        this.verifications = verifications;
        this.platform = platform;
        this.resendCooldown = resendCooldown;
        this.dailyCap = dailyCap;
        String code = defaultDialCode == null ? "" : defaultDialCode.trim();
        if (!DIAL_CODE.matcher(code).matches()) {
            // Refused at startup rather than at the first signup. A bad value here makes every
            // national number unsendable, and that failure is invisible from this service.
            throw new IllegalStateException(
                    "delivery.onboarding.verification.default-dial-code is not a dialling code: \""
                            + code + "\". Give a plus and up to four digits, e.g. +961 or +966.");
        }
        this.defaultDialCode = code;
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

    /**
     * Thrown when the relay refused the message. A subtype so a caller can tell "your input is
     * wrong" from "our sending is down": the sign-up form surfaces both, but the password-reset
     * endpoint must swallow this one — answering differently when the relay fails would answer
     * differently only for addresses that have an account, which is the fact it must not reveal.
     */
    public static class CodeSendFailedException extends VerificationException {
        public CodeSendFailedException(String message) {
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
        return request(channel, rawDestination, Purpose.SIGNUP, () -> true);
    }

    /**
     * A password-reset challenge, recorded whether or not the address has an account.
     *
     * <p>The shape of this method is the anti-enumeration property. The challenge row is saved and
     * the limits are counted for <em>every</em> request, so a cooldown refusal, a daily-cap
     * refusal and a 202 all behave identically for an address with an account and one without —
     * the only difference is whether a message actually leaves, which the caller cannot observe.
     * {@code accountExists} is a supplier rather than a boolean so the account lookup runs only
     * after the limits have passed: the limits are this endpoint's shield, and the lookup should
     * sit behind them, not in front.
     */
    @Transactional
    public Instant requestPasswordReset(String rawEmail, BooleanSupplier accountExists) {
        return request(Channel.EMAIL, rawEmail, Purpose.PASSWORD_RESET, accountExists);
    }

    private Instant request(Channel channel, String rawDestination, Purpose purpose,
                            BooleanSupplier deliverable) {
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

        ContactVerification.Issued issued = ContactVerification.issue(channel, destination, purpose);
        // Saved before sending. A code that goes out and was never recorded cannot be confirmed,
        // which is the one failure the person holding it can do nothing about.
        verifications.saveAndFlush(issued.verification());

        if (deliverable.getAsBoolean()) {
            deliver(channel, destination, purpose, issued.code());
            log.info("{} code sent on {} (attempt {} today)", purpose, channel, today + 1);
        } else {
            // A reset asked for on an address with no account. The challenge above was still
            // recorded so the limits and the response stay identical either way; the code it holds
            // was never sent and cannot be guessed, so nothing can be done with the row.
            log.info("{} code recorded but not sent on {} (attempt {} today)",
                    purpose, channel, today + 1);
        }
        return issued.verification().getExpiresAt();
    }

    private void deliver(Channel channel, String destination, Purpose purpose, String code) {
        long minutes = ContactVerification.LIFETIME.toMinutes();

        String act = purpose == Purpose.PASSWORD_RESET
                ? "reset your YouDrop passcode"
                : "confirm your email address for YouDrop";

        // The code stands alone on the first line, and everything else follows in prose. That shape
        // is what makes both renderings work: the email layout shows a lone short code as a code
        // block, and on a phone the first thing in the notification preview is the code itself,
        // which is the only part anybody actually wants.
        String emailBody = code + "\n\n"
                + "Use this code to " + act + "."
                + " It expires in " + minutes + " minutes and can be used once.\n\n"
                + "If you did not ask for this code, no action is needed —"
                + (purpose == Purpose.PASSWORD_RESET
                        ? " your passcode has not changed."
                        : " somebody may have typed your address by mistake.")
                + " Do not share it with anyone; YouDrop will never ask you for it.";

        // SMS is one line: no layout renders it, and a message split across several parts costs
        // more and can arrive out of order.
        String smsBody = code + " is your YouDrop verification code. It expires in "
                + minutes + " minutes. Never share it with anyone.";

        String notifyPurpose = purpose == Purpose.PASSWORD_RESET
                ? "onboarding.password-reset" : "onboarding.verification";

        try {
            if (channel == Channel.EMAIL) {
                // The code is in the subject as well as the body. That is deliberate and it is a
                // trade: it means somebody can read the code from a preview without opening the
                // mail, which is the fastest path for the person who asked for it and also visible
                // to anyone looking at their screen. Every large provider makes the same call, and
                // the code is already in the body, so this adds no exposure inside our own logs.
                String subject = purpose == Purpose.PASSWORD_RESET
                        ? code + " is your YouDrop passcode reset code"
                        : code + " is your YouDrop verification code";
                platform.notifyDirect("EMAIL", destination, subject, emailBody, notifyPurpose);
            } else {
                platform.notifyDirect("SMS", destination, null, smsBody, notifyPurpose);
            }
        } catch (Exception e) {
            // Told plainly rather than reported as success. "We have sent you a code" is a promise,
            // and a screen that makes it while the send failed leaves somebody waiting for a
            // message that is never coming. (The password-reset path deliberately swallows this
            // subtype — see CodeSendFailedException for why.)
            log.error("Could not send a verification code on {}", channel, e);
            throw new CodeSendFailedException(
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
        return confirm(channel, rawDestination, code, Purpose.SIGNUP);
    }

    /**
     * The purpose-aware form. The lookup itself filters by purpose, which is what makes a
     * password-reset code worthless on the sign-up form and the reverse: a code answered against
     * the wrong purpose simply finds no challenge, and is refused in the same words as a wrong
     * code so the caller learns nothing from the difference.
     */
    @Transactional
    public Confirmed confirm(Channel channel, String rawDestination, String code, Purpose purpose) {
        String destination = normalise(channel, rawDestination);

        ContactVerification verification = verifications
                .findFirstByChannelAndDestinationAndPurposeOrderByCreatedAtDesc(
                        channel, destination, purpose)
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
        return consume(token, channel, expectedDestination, Purpose.SIGNUP);
    }

    /**
     * The purpose-aware form. The purpose check mirrors the destination check above it and exists
     * for the same reason: a proof earned for one act must not be spendable on another. Without it
     * a password-reset token — earned by holding an inbox for ten minutes — would stand in for the
     * sign-up verification an application requires.
     */
    @Transactional
    public Instant consume(String token, Channel channel, String expectedDestination,
                           Purpose purpose) {
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
        if (verification.getPurpose() != purpose) {
            throw new VerificationException(
                    "That verification was for something else. Please verify again.");
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
                // Sign-up proofs only. This backs sign-up forms, and a reset token must read as
                // unverified there for the same reason consume refuses it.
                .filter(v -> v.getPurpose() == Purpose.SIGNUP)
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
    public String normalise(Channel channel, String raw) {
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

        return toE164(value);
    }

    /**
     * The number as the SMS connector needs it, from the number as a person writes it.
     *
     * <p>People type their own country's numbers the way they say them out loud — {@code 71 423 308}
     * in Beirut, {@code 05x xxx xxxx} in Riyadh — and almost nobody types a {@code +}. Refusing all
     * of that would be technically correct and useless, so each accepted spelling is converted:
     *
     * <ul>
     *   <li>{@code +961...} — already international, kept as it stands.</li>
     *   <li>{@code 00961...} — the other way of writing a plus, in most of the world.</li>
     *   <li>{@code 071...} — a national number with a trunk prefix. The leading zero is not part of
     *       the number; it is dropped and the default dialling code goes on.</li>
     *   <li>{@code 71...} — a bare national number, which just takes the default dialling code.</li>
     * </ul>
     *
     * <p>The default matters and is configurable for a reason: the platform's screens are currently
     * written for two countries at once, and guessing wrong sends somebody's code to a stranger in
     * another one. Whatever comes out is checked against {@link #PHONE} before it can be stored or
     * sent, so a number that cannot be made valid is refused HERE — where the applicant is looking
     * at the field and can fix it — rather than accepted and quietly dropped downstream.
     */
    private String toE164(String raw) {
        // Spaces, dashes and brackets are how people write phone numbers and none of them are part
        // of the number. Stripped so the same phone typed two ways is one destination.
        String value = raw.replaceAll("[\\s()\\-.]", "");

        if (value.startsWith("00")) {
            value = "+" + value.substring(2);
        } else if (!value.startsWith("+")) {
            // A single leading zero is a national trunk prefix, not a digit of the number.
            String national = value.startsWith("0") ? value.substring(1) : value;
            value = defaultDialCode + national;
        }

        if (!PHONE.matcher(value).matches()) {
            throw new VerificationException(
                    "That does not look like a phone number. Include the country code, "
                            + "for example " + defaultDialCode + "71123456.");
        }
        return value;
    }

    /** For the API layer, which needs the normalised form to echo back to the form. */
    public Optional<String> normaliseQuietly(Channel channel, String raw) {
        try {
            return Optional.of(normalise(channel, raw));
        } catch (VerificationException e) {
            return Optional.empty();
        }
    }
}

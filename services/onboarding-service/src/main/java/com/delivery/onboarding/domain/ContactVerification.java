package com.delivery.onboarding.domain;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A one-time code sent to an address, and whether it was ever answered correctly.
 *
 * <p>The code itself is never stored. It exists in memory long enough to be sent and is kept here
 * only as a salted SHA-256, on the same reasoning as a password: this table is the one place a
 * database leak would otherwise hand somebody a working code for every address currently
 * mid-verification, and those codes are the sole barrier between a stranger and an application in
 * somebody else's name.
 *
 * <p>Three things make a six-digit code worth anything, and none of them is the code. It expires,
 * so a code read over somebody's shoulder is worthless by the afternoon. Wrong guesses are counted
 * and capped, because one in a million per attempt is one in a thousand over a thousand attempts.
 * And the proof it produces is single-use, so one verified address cannot underwrite an endless
 * stream of applications.
 */
@Entity
@Table(name = "onboarding_verifications")
public class ContactVerification {

    public enum Channel { EMAIL, PHONE }

    /**
     * What answering this code is allowed to accomplish.
     *
     * <p>A code is proof that somebody holds an inbox <em>right now</em>, and the two things that
     * proof unlocks are very different acts: {@link #SIGNUP} lets an application or an account name
     * the address, {@link #PASSWORD_RESET} replaces the passcode of an account that already exists.
     * Without this field the two would be interchangeable — a reset code answered on the sign-up
     * form would verify an address for an application, and a sign-up code would reset a passcode.
     * Every lookup that resolves a challenge therefore matches on purpose as well as destination.
     */
    public enum Purpose { SIGNUP, PASSWORD_RESET }

    /**
     * Six digits.
     *
     * <p>Short enough to be read from a notification and typed without a mistake, which is not a
     * small consideration: a code people mistype is a code people give up on. The length is not
     * what makes it safe — the attempt cap is — so making it longer would cost usability and buy
     * very little.
     */
    public static final int CODE_LENGTH = 6;

    /** Long enough to fetch a phone from another room, short enough that a shoulder-surfed code dies. */
    public static final Duration LIFETIME = Duration.ofMinutes(10);

    /** After this many wrong guesses the code is dead and a new one has to be requested. */
    public static final int MAX_ATTEMPTS = 5;

    private static final SecureRandom RANDOM = new SecureRandom();

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "channel", nullable = false, updatable = false, length = 16)
    private Channel channel;

    @Column(name = "destination", nullable = false, updatable = false, length = 255)
    private String destination;

    @Enumerated(EnumType.STRING)
    @Column(name = "purpose", nullable = false, updatable = false, length = 32)
    private Purpose purpose = Purpose.SIGNUP;

    @Column(name = "code_hash", nullable = false, updatable = false, length = 64)
    private String codeHash;

    @Column(name = "salt", nullable = false, updatable = false, length = 32)
    private String salt;

    @Column(name = "attempts", nullable = false)
    private short attempts;

    @Column(name = "expires_at", nullable = false, updatable = false)
    private Instant expiresAt;

    @Column(name = "confirmed_at")
    private Instant confirmedAt;

    @Column(name = "consumed_at")
    private Instant consumedAt;

    @Column(name = "token", nullable = false, updatable = false, length = 64)
    private String token;

    @Column(name = "created_at", nullable = false, insertable = false, updatable = false)
    private Instant createdAt;

    protected ContactVerification() {
        // for JPA
    }

    private ContactVerification(Channel channel, String destination, Purpose purpose, String code) {
        this.id = UUID.randomUUID();
        this.channel = channel;
        this.destination = destination;
        this.purpose = purpose;
        this.salt = randomBase64(12);
        this.codeHash = hash(code, this.salt);
        this.attempts = 0;
        this.expiresAt = Instant.now().plus(LIFETIME);
        this.token = randomBase64(20);
    }

    /**
     * A new challenge, and the code to send.
     *
     * <p>Returned alongside the entity rather than readable from it, because the entity genuinely
     * does not know the code once this returns — which is the point, and would be quietly untrue if
     * there were a getter for it.
     */
    public static Issued issue(Channel channel, String destination) {
        return issue(channel, destination, Purpose.SIGNUP);
    }

    /** A challenge for a stated purpose. See {@link Purpose} for why the two cannot be swapped. */
    public static Issued issue(Channel channel, String destination, Purpose purpose) {
        String code = randomCode();
        return new Issued(new ContactVerification(channel, destination, purpose, code), code);
    }

    public record Issued(ContactVerification verification, String code) {
    }

    /**
     * Checks a code, counting the attempt whether it was right or wrong.
     *
     * <p>The comparison is constant-time. That is close to paranoia for a six-digit code over HTTP —
     * the network noise dwarfs the timing difference — but the alternative is reasoning about
     * exactly how much signal leaks on every future change, and there is no cost to being certain.
     *
     * <p><strong>An already-confirmed challenge is still gated on the code.</strong> Confirming
     * twice has to keep working — a form may retry, or somebody may press the button again — but
     * the earlier shape of that allowance returned {@code CONFIRMED} the moment it saw
     * {@code confirmedAt}, without looking at the code at all. The endpoint that calls this is
     * public, takes a destination and a code, and answers with the proof token, so the shortcut let
     * anyone who could name an address collect the token somebody else had just earned for it — any
     * six digits would do — and apply as them. Idempotency is preserved by re-checking the code
     * rather than by skipping it.
     */
    public Outcome confirm(String code) {
        if (consumedAt != null) {
            return Outcome.ALREADY_USED;
        }
        if (attempts >= MAX_ATTEMPTS) {
            return Outcome.TOO_MANY_ATTEMPTS;
        }
        // Expiry ends the window for answering a code. It does not end an answer already given:
        // once confirmed, the proof's life is governed by consumption, and an applicant who
        // verified their address then spent ten minutes on the rest of the form has done nothing
        // wrong.
        if (confirmedAt == null && Instant.now().isAfter(expiresAt)) {
            return Outcome.EXPIRED;
        }

        attempts++;
        if (!constantTimeEquals(hash(code, salt), codeHash)) {
            return Outcome.WRONG;
        }

        if (confirmedAt == null) {
            confirmedAt = Instant.now();
        }
        return Outcome.CONFIRMED;
    }

    public enum Outcome { CONFIRMED, WRONG, EXPIRED, TOO_MANY_ATTEMPTS, ALREADY_USED }

    /** Spends the proof. One verified address, one application. */
    public void consume() {
        if (confirmedAt == null) {
            throw new IllegalStateException("That contact detail has not been verified");
        }
        if (consumedAt != null) {
            throw new IllegalStateException("That verification has already been used");
        }
        this.consumedAt = Instant.now();
    }

    public boolean isUsable() {
        return confirmedAt != null && consumedAt == null;
    }

    private static String randomCode() {
        // Uniform over the full range, leading zeros kept: trimming them would make some codes five
        // digits and quietly shrink the space.
        int value = RANDOM.nextInt(1_000_000);
        return String.format("%0" + CODE_LENGTH + "d", value);
    }

    private static String randomBase64(int bytes) {
        byte[] buffer = new byte[bytes];
        RANDOM.nextBytes(buffer);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(buffer);
    }

    private static String hash(String code, String salt) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            digest.update(salt.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest.digest(code.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 is required of every JVM; if it is absent the platform has bigger problems.
            throw new IllegalStateException("SHA-256 is unavailable", e);
        }
    }

    private static boolean constantTimeEquals(String a, String b) {
        return MessageDigest.isEqual(
                a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }

    public UUID getId() {
        return id;
    }

    public Channel getChannel() {
        return channel;
    }

    public String getDestination() {
        return destination;
    }

    public Purpose getPurpose() {
        return purpose;
    }

    public String getToken() {
        return token;
    }

    public short getAttempts() {
        return attempts;
    }

    public Instant getExpiresAt() {
        return expiresAt;
    }

    public Instant getConfirmedAt() {
        return confirmedAt;
    }

    public Instant getConsumedAt() {
        return consumedAt;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}

package com.delivery.onboarding.domain;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ContactVerificationRepository extends JpaRepository<ContactVerification, UUID> {

    /** The proof an application presents. Looked up by token alone — it is the only credential. */
    Optional<ContactVerification> findByToken(String token);

    /** The live challenge for a destination: the newest one, since a resend supersedes its predecessor. */
    Optional<ContactVerification> findFirstByChannelAndDestinationOrderByCreatedAtDesc(
            ContactVerification.Channel channel, String destination);

    /**
     * The live challenge for one purpose only.
     *
     * <p>This is the lookup the confirm step uses, and the purpose in it is not decoration: it is
     * what makes a password-reset code unable to verify a sign-up and the reverse. The
     * purpose-less variant above stays for the resend cooldown, which deliberately counts every
     * recent send to a destination regardless of why it was sent.
     */
    Optional<ContactVerification> findFirstByChannelAndDestinationAndPurposeOrderByCreatedAtDesc(
            ContactVerification.Channel channel, String destination,
            ContactVerification.Purpose purpose);

    /**
     * How many codes this address has been sent recently.
     *
     * <p>This is the rate limit, and it is the difference between a verification endpoint and a
     * machine for sending unsolicited mail to any address a stranger types. Counted per destination
     * rather than per caller: the caller has no account and can change IP, but the cost lands on
     * whoever owns the address being hammered.
     */
    long countByDestinationAndCreatedAtAfter(String destination, Instant since);

    /**
     * How many codes this address has been sent recently for one purpose.
     *
     * <p>Password resets get their own, tighter budget on top of the shared one above. A reset
     * request is rarer and riskier than a sign-up resend — a person genuinely locked out asks two
     * or three times and then contacts support, while a stream of them is somebody probing the
     * account — so the reset cap can sit well below the shared cap without ever refusing a real
     * person.
     */
    long countByDestinationAndPurposeAndCreatedAtAfter(
            String destination, ContactVerification.Purpose purpose, Instant since);
}

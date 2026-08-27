package com.delivery.onboarding.domain;

import java.math.BigInteger;
import java.util.Map;

/**
 * An international bank account number that has been checked, not merely typed.
 *
 * <p><strong>Why the mod-97 check is worth writing rather than trusting the form.</strong> The
 * obvious alternative — accept anything of roughly the right length and let the bank sort it out —
 * fails at the worst possible moment. An IBAN with two digits transposed is still the right length,
 * still starts with the right country code, and still looks correct to the person who typed it and
 * to the reviewer who reads it. It is discovered weeks later, when the first payout run either
 * bounces (an outage for the merchant, a support thread, and a manual re-run) or, if the wrong
 * number happens to belong to somebody, does not bounce at all. ISO 13616 puts a checksum in the
 * number precisely so that a client can catch that at the keyboard, while the applicant is still
 * looking at the field.
 *
 * <p>It has to be here as well as in the wizard. The client's validation is a convenience for
 * whoever is typing; this endpoint is reachable by anything that can POST JSON, and the wizards are
 * shipped separately and get rewritten. A rule that only exists in a form is a rule that is one
 * redesign away from not existing.
 *
 * <p>What it does <em>not</em> prove, and this matters for how the result is recorded: mod-97 says
 * the number is well formed and was not mistyped. It says nothing about the account existing, being
 * open, or belonging to the name on the application. That takes a bank — see
 * {@code PayoutAccountVerifier}.
 *
 * <p>{@link #toString()} is masked. This type is the one place an IBAN is guaranteed to pass
 * through, so making the careless thing safe here is worth more than remembering not to do it at
 * every call site.
 */
public final class Iban {

    /** ISO 13616: two letters, two check digits, then up to 30 alphanumerics. */
    private static final int MIN_LENGTH = 15;
    private static final int MAX_LENGTH = 34;

    /**
     * Registered IBAN lengths for the countries YouDrop pays into, checked in addition to the
     * checksum.
     *
     * <p>Not a substitute for mod-97 and not the primary check — it is here because the two catch
     * different mistakes. The checksum catches a mistyped digit; the length catches a number that
     * was pasted with a digit missing entirely, which has roughly a 1-in-97 chance of passing the
     * checksum anyway. An unknown country falls back to the generic bounds above rather than being
     * refused: the registry gains entries, and refusing an account in a country this map has simply
     * not been updated for would be a rule about this file rather than about the number.
     */
    private static final Map<String, Integer> REGISTERED_LENGTHS = Map.of(
            "EG", 29,   // Egypt
            "SA", 24,   // Saudi Arabia
            "AE", 23,   // United Arab Emirates
            "JO", 30,   // Jordan
            "KW", 30,   // Kuwait
            "QA", 29,   // Qatar
            "BH", 22,   // Bahrain
            "GB", 22,   // United Kingdom
            "DE", 22,   // Germany
            "FR", 27);  // France

    private static final BigInteger NINETY_SEVEN = BigInteger.valueOf(97);

    private final String value;

    private Iban(String value) {
        this.value = value;
    }

    /** Thrown when a number cannot be an IBAN. The message is safe to show whoever typed it. */
    public static class InvalidIbanException extends IllegalArgumentException {
        public InvalidIbanException(String message) {
            super(message);
        }
    }

    /**
     * Parses and checks a number as somebody typed it.
     *
     * @throws InvalidIbanException with a message that says which check failed. Deliberately
     *         specific — "that account number is not valid" tells the applicant nothing about
     *         whether they mistyped a digit or pasted the wrong field, and the failure modes call
     *         for different corrections. None of these messages reveal anything the caller did not
     *         already send.
     */
    public static Iban parse(String raw) {
        if (raw == null || raw.isBlank()) {
            throw new InvalidIbanException("An account number is required");
        }

        // Printed IBANs are grouped in fours, and people paste them that way. Normalising rather
        // than refusing: a space is a formatting convention, not a typo.
        String normalised = raw.replaceAll("[\\s -]", "").toUpperCase(java.util.Locale.ROOT);

        if (normalised.length() < MIN_LENGTH || normalised.length() > MAX_LENGTH) {
            throw new InvalidIbanException(
                    "An IBAN is between " + MIN_LENGTH + " and " + MAX_LENGTH + " characters");
        }
        if (!normalised.matches("[A-Z]{2}[0-9]{2}[A-Z0-9]+")) {
            throw new InvalidIbanException(
                    "An IBAN starts with two letters for the country and two check digits");
        }

        String country = normalised.substring(0, 2);
        Integer expectedLength = REGISTERED_LENGTHS.get(country);
        if (expectedLength != null && normalised.length() != expectedLength) {
            throw new InvalidIbanException("An IBAN for " + country + " is "
                    + expectedLength + " characters, not " + normalised.length());
        }

        if (!checksumHolds(normalised)) {
            // The message a mistyped digit produces, and the one this class exists for.
            throw new InvalidIbanException(
                    "That account number failed its check digits — a digit is probably wrong or "
                            + "two are the wrong way round");
        }

        return new Iban(normalised);
    }

    /**
     * The mod-97 check itself (ISO 7064 MOD 97-10).
     *
     * <p>Move the first four characters to the end, replace each letter with two digits (A=10 …
     * Z=35), read the result as one enormous integer, and it is a valid IBAN exactly when that
     * integer leaves a remainder of 1 when divided by 97.
     *
     * <p>Done with {@link BigInteger} rather than the piecewise remainder loop the standard also
     * allows. The loop is faster and this is not on a hot path; the direct form is the one that can
     * be read against the specification without trusting that the chunking was done right, and a
     * bank account check that is subtly wrong is worse than one that is slow.
     */
    private static boolean checksumHolds(String normalised) {
        String rearranged = normalised.substring(4) + normalised.substring(0, 4);

        StringBuilder digits = new StringBuilder(rearranged.length() * 2);
        for (int i = 0; i < rearranged.length(); i++) {
            char c = rearranged.charAt(i);
            if (c >= '0' && c <= '9') {
                digits.append(c);
            } else {
                // 'A' becomes 10, 'B' 11, and so on to 'Z' as 35 — appended as decimal digits, so
                // the number grows by two characters per letter.
                digits.append(c - 'A' + 10);
            }
        }

        return new BigInteger(digits.toString()).mod(NINETY_SEVEN).equals(BigInteger.ONE);
    }

    /** The normalised number: uppercase, no spaces. The only accessor that returns it in full. */
    public String value() {
        return value;
    }

    public String country() {
        return value.substring(0, 2);
    }

    /** The last four digits, which is all any listing is ever allowed to show. */
    public String lastFour() {
        return value.substring(value.length() - 4);
    }

    /**
     * Masked, always.
     *
     * <p>A bank account number reaches a log through {@code toString()} — inside a collection being
     * printed, an exception message, a debug line added in a hurry. Making the default rendering
     * safe removes a whole class of that, and anything that genuinely needs the number has to ask
     * for it by name.
     */
    @Override
    public String toString() {
        return country() + "••••" + lastFour();
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof Iban iban && value.equals(iban.value);
    }

    @Override
    public int hashCode() {
        return value.hashCode();
    }
}

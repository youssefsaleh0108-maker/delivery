package com.delivery.settings.domain;

import java.util.List;

/**
 * The connectors whose runtime configuration a Backoffice user may change (Section 8).
 *
 * <p>The provider list per connector is closed on purpose. The Backoffice renders it as a dropdown
 * rather than free text so an admin cannot point production at the dev test-inbox by typo — and the
 * service re-checks it, because a dropdown is only a UI convention.
 */
public enum ConnectorType {

    /**
     * The one that actually varies. DEV_PASSTHROUGH redirects the message to an email inbox so it
     * is readable without a paid account or a real handset; the other two are the live vendors,
     * both built in Phase 3 so going live is a settings change rather than a release.
     */
    SMS(List.of("DEV_PASSTHROUGH", "MONTYMOBILE", "TWILIO")),

    /** Fixed: SMTP relay, not a third-party HTTP API (Section 7). */
    EMAIL(List.of("SMTP")),

    /**
     * Firebase Cloud Messaging covers both Android and iOS, so there is no second real vendor to
     * choose between. DEV_LOG is not a vendor — it is the dev fallback for environments with no
     * Firebase project, where a connector that could only refuse messages would leave the entire
     * push path untested until the day it goes live.
     */
    PUSH(List.of("DEV_LOG", "FIREBASE")),

    /**
     * Three, and the difference between the first two matters.
     *
     * <p>MOCK is in-process: it accepts every posting, returns a {@code MOCK-} reference and moves
     * nothing. It is what lets the settlement saga complete and reconciliation report on an
     * environment with no simulator deployed and no banking agreement.
     *
     * <p>SIMULATOR is a separate deployable with a real ledger and a fault-injection endpoint —
     * the one to pick when the point is to test what happens when a bank refuses or breaks, which
     * MOCK by design never does.
     *
     * <p>REAL refuses every posting until the bank's published spec exists. Selecting it before
     * then is a misconfiguration, and RealBankClient says so loudly rather than failing quietly.
     */
    CORE_BANKING(List.of("MOCK", "SIMULATOR", "REAL"));

    private final List<String> providers;

    ConnectorType(List<String> providers) {
        this.providers = providers;
    }

    public List<String> providers() {
        return providers;
    }

    public boolean supports(String provider) {
        return providers.contains(provider);
    }
}

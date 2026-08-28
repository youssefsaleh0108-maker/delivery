package com.delivery.onboarding.service;

import java.util.EnumSet;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * Which kinds of applicant are let in without a human deciding.
 *
 * <p>The platform was built the other way round — every application waits for a reviewer — and this
 * turns that off per kind. It exists because growth and review are in tension: a rider who applies
 * on Friday evening and is approved on Monday morning has probably signed up with somebody else by
 * Monday morning.
 *
 * <p><strong>What is given up is real and worth stating.</strong> With auto-approval on, the only
 * thing standing between a stranger and a live merchant or rider account is a verified email
 * address. Nobody reads the licence plate; nobody looks at the commercial registration. The papers
 * are still collected and still visible in the backoffice — they are simply no longer a gate. That
 * is a deliberate trade, not an oversight, and it is why this is configuration rather than a
 * deleted branch: the day it needs reversing, it reverses with a restart.
 *
 * <p>Per kind, because the risks are not equal. A rider who turns out to be nobody wastes a
 * delivery; a merchant who turns out to be nobody takes a customer's money for food that never
 * existed; a carrier is a company, signing for a fleet and a payout account. Defaults reflect that
 * order, and the safest thing this class can do is refuse to guess: an unknown kind is never
 * automatic.
 */
@Component
public class AutoApprovalPolicy {

    /**
     * Who the audit trail names when nobody decided.
     *
     * <p>Not a person, not blank, and not a reviewer's name borrowed for the purpose. When somebody
     * asks in a year's time who let this merchant onto the platform, the honest answer has to be
     * available, and "the policy did, at this instant" is that answer.
     */
    public static final String AUTOMATIC_REVIEWER = "system:auto-approval";

    private final Set<Kind> automatic;

    public AutoApprovalPolicy(
            @Value("${delivery.onboarding.auto-approve.rider:false}") boolean rider,
            @Value("${delivery.onboarding.auto-approve.merchant:false}") boolean merchant,
            @Value("${delivery.onboarding.auto-approve.carrier:false}") boolean carrier) {

        Set<Kind> kinds = EnumSet.noneOf(Kind.class);
        if (rider) kinds.add(Kind.RIDER);
        if (merchant) kinds.add(Kind.MERCHANT);
        if (carrier) kinds.add(Kind.CARRIER);
        this.automatic = kinds;
    }

    /**
     * Whether an application of this kind is approved on submission.
     *
     * <p>Null is false. A kind the platform gains later is manual until somebody says otherwise,
     * which is the direction a default should fail in.
     */
    public boolean isAutomatic(Kind kind) {
        return kind != null && automatic.contains(kind);
    }

    /** For the startup line and for the backoffice to show what is currently in force. */
    public Set<Kind> automaticKinds() {
        return Set.copyOf(automatic);
    }
}

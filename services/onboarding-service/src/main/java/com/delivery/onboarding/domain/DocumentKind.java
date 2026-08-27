package com.delivery.onboarding.domain;

import java.util.EnumSet;
import java.util.Set;

import com.delivery.onboarding.domain.OnboardingApplication.Kind;

/**
 * Which paper an applicant is being asked for.
 *
 * <p>An enum rather than free text, because what a merchant must produce is not what a rider must,
 * and the difference is a rule this service enforces rather than a label the wizard chose. A rider
 * uploading a commercial registration is either confused or probing; either way the upload is
 * refused before a presigned URL exists for it.
 *
 * <p>The sets below are the platform's current requirements, not the law's. They are stated here,
 * once, so the wizard, the reviewer's checklist and the "is this application complete" answer all
 * come from the same place — three copies of this list is how a step gets added to the form and
 * never becomes required.
 */
public enum DocumentKind {

    /** Identity. Asked of every applicant, because every applicant is a person the platform pays. */
    NATIONAL_ID,

    /** A rider's licence to be on the road at all. */
    DRIVING_LICENCE,

    /** The papers for the vehicle a rider will actually ride. */
    VEHICLE_REGISTRATION,

    /** A registered business: a shop, or a delivery company. */
    COMMERCIAL_REGISTRATION;

    private static final Set<DocumentKind> MERCHANT_DOCUMENTS =
            EnumSet.of(NATIONAL_ID, COMMERCIAL_REGISTRATION);

    private static final Set<DocumentKind> CARRIER_DOCUMENTS =
            EnumSet.of(NATIONAL_ID, COMMERCIAL_REGISTRATION);

    private static final Set<DocumentKind> RIDER_DOCUMENTS =
            EnumSet.of(NATIONAL_ID, DRIVING_LICENCE, VEHICLE_REGISTRATION);

    /**
     * What this kind of applicant is expected to produce.
     *
     * <p>"Expected", not "must". A missing document does not block an application being submitted
     * or even approved — a reviewer with the papers in front of them on a desk is entitled to say
     * yes — it decides what the wizard asks for and what the reviewer's panel shows as outstanding.
     */
    public static Set<DocumentKind> expectedFor(Kind applicantKind) {
        return switch (applicantKind) {
            case MERCHANT -> MERCHANT_DOCUMENTS;
            case CARRIER -> CARRIER_DOCUMENTS;
            case RIDER -> RIDER_DOCUMENTS;
        };
    }

    /** Whether this kind of applicant may upload this document at all. */
    public boolean appliesTo(Kind applicantKind) {
        return expectedFor(applicantKind).contains(this);
    }
}

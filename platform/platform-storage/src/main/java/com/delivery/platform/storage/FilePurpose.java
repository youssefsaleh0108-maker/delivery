package com.delivery.platform.storage;

import java.util.List;

/**
 * What a stored object is for, and therefore which bucket it lands in, who may read it, and which
 * content types may be uploaded into it (Section 5).
 *
 * <p>Binding purpose to bucket here rather than letting callers pass a bucket name means a service
 * cannot accidentally write a KYC document into the publicly-readable product-images bucket.
 *
 * <p><strong>Content types are per purpose (since 0.1.3).</strong> Until then one global allow-list,
 * named for images, applied to every purpose. onboarding-service needed PDF for applicant documents,
 * and the only way to get it was to add PDF to that global list — which let a PDF into its public
 * product-images bucket and its avatar bucket as well. The rule now sits with the purpose that needs
 * it: a KYC document may be a PDF, a product photo may not. A service can still replace one purpose's
 * list with {@code delivery.storage.minio.allowed-content-types.<PURPOSE>}, and doing so touches no
 * other purpose (see {@link StorageProperties#allowedContentTypesFor(FilePurpose)}).
 *
 * <p>Note what is on none of these lists: {@code image/svg+xml}. SVG is script, and private objects
 * are served from the MinIO origin by presigned URL; an SVG would run in that origin. Every list here
 * is an allow-list so that adding a type is a decision somebody makes on purpose.
 */
public enum FilePurpose {

    /** Merchant product photos. Public-read via CDN; upload by MERCHANT. */
    PRODUCT_IMAGE("product-images", true, Types.PHOTOS),

    /** Proof-of-delivery photos/signatures. Private, versioned, retention-locked — dispute evidence. */
    DELIVERY_PROOF("delivery-proof", false, Types.PHOTOS),

    /**
     * Business registration / ID documents. Private, BACKOFFICE-only read. Photos and PDF: a
     * commercial registration arrives as a PDF far more often than as a photograph. This is the rule
     * onboarding-service used to express by widening the global list.
     */
    MERCHANT_KYC("merchant-kyc", false, Types.PHOTOS_AND_PDF),

    /** Profile photos, all roles. Owner-only write. */
    USER_AVATAR("user-avatars", false, Types.PHOTOS),

    /** Generated invoices/receipts from the accounting flow. Private. */
    RECEIPT("receipts", false, Types.PHOTOS),

    /**
     * A customer's file on an order — the artwork a print shop is asked to print. Private: read only
     * through a short-lived signed URL, which order-manager issues to the order's customer, its
     * merchant and back office after checking which of them is asking.
     *
     * <p>PDF, JPEG or PNG and nothing else — the owner's list for service orders. No WebP: it is not a
     * format a print shop's tools can be assumed to open, and a file the provider cannot open is an
     * order that cannot start.
     */
    ORDER_ATTACHMENT("order-attachments", false, Types.PRINT_FILES);

    private final String bucket;
    private final boolean publiclyReadable;
    private final List<String> defaultContentTypes;

    FilePurpose(String bucket, boolean publiclyReadable, List<String> defaultContentTypes) {
        this.bucket = bucket;
        this.publiclyReadable = publiclyReadable;
        this.defaultContentTypes = defaultContentTypes;
    }

    public String bucket() {
        return bucket;
    }

    /**
     * True when the bucket policy allows anonymous GET, so a direct URL can be handed out instead
     * of a short-TTL presigned one.
     */
    public boolean isPubliclyReadable() {
        return publiclyReadable;
    }

    /**
     * The content types an upload for this purpose may declare when the consuming service has not
     * configured its own list for it. Unmodifiable.
     */
    public List<String> defaultContentTypes() {
        return defaultContentTypes;
    }

    /**
     * The lists, in a nested class because an enum constant may not refer to a static field of its
     * own enum before that field is initialised — a nested class is initialised on first use instead.
     */
    private static final class Types {
        static final List<String> PHOTOS = List.of("image/jpeg", "image/png", "image/webp");
        static final List<String> PHOTOS_AND_PDF =
                List.of("image/jpeg", "image/png", "image/webp", "application/pdf");
        static final List<String> PRINT_FILES = List.of("application/pdf", "image/jpeg", "image/png");

        private Types() {
        }
    }
}

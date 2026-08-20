package com.delivery.platform.storage;

/**
 * What a stored object is for, and therefore which bucket it lands in and who may read it
 * (Section 5).
 *
 * <p>Binding purpose to bucket here rather than letting callers pass a bucket name means a service
 * cannot accidentally write a KYC document into the publicly-readable product-images bucket.
 */
public enum FilePurpose {

    /** Merchant product photos. Public-read via CDN; upload by MERCHANT. */
    PRODUCT_IMAGE("product-images", true),

    /** Proof-of-delivery photos/signatures. Private, versioned, retention-locked — dispute evidence. */
    DELIVERY_PROOF("delivery-proof", false),

    /** Business registration / ID documents. Private, BACKOFFICE-only read. */
    MERCHANT_KYC("merchant-kyc", false),

    /** Profile photos, all roles. Owner-only write. */
    USER_AVATAR("user-avatars", false),

    /** Generated invoices/receipts from the accounting flow. Private. */
    RECEIPT("receipts", false);

    private final String bucket;
    private final boolean publiclyReadable;

    FilePurpose(String bucket, boolean publiclyReadable) {
        this.bucket = bucket;
        this.publiclyReadable = publiclyReadable;
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
}

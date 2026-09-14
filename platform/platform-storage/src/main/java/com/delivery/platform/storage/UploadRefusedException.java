package com.delivery.platform.storage;

/**
 * An upload refused at confirm for what it turned out to be — and already dealt with: its object
 * removed from the bucket and its row marked deleted before this was thrown.
 *
 * <p>That is what sets it apart from the {@link StorageException} it extends. A confirm that throws
 * this has changed something that must be kept, so {@link StorageService#confirmUpload} and
 * {@link StorageService#confirm} do not roll their transaction back for it ({@code noRollbackFor}); a
 * caller that joins that transaction and wants the deletion kept does the same in its own. Rolled back,
 * the row would go on calling a deleted file PENDING — and a caller's own record of the upload with it,
 * holding whatever slot that upload was counted against until something swept it.
 *
 * <p>{@link #reason()} says which check refused it, so a caller can tell its user something they can act
 * on — the file is too large, or not the kind of file it was declared as — without reading a message
 * that names buckets and keys.
 */
public class UploadRefusedException extends StorageException {

    /** Which of confirm's checks the upload failed. */
    public enum Reason {
        /** Larger than {@code delivery.storage.minio.max-upload-size-bytes}. */
        TOO_LARGE,
        /** Stored with a content type other than the declared one, or its bytes are not that type. */
        WRONG_TYPE
    }

    private final Reason reason;

    public UploadRefusedException(Reason reason, String message) {
        super(message);
        this.reason = reason;
    }

    public Reason reason() {
        return reason;
    }
}

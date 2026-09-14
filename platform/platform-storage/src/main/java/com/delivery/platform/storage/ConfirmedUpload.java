package com.delivery.platform.storage;

/**
 * An upload that passed confirm ({@link StorageService#confirm}): its row, now UPLOADED, and the entity
 * tag of exactly the bytes the checks passed.
 *
 * <p>Keep the tag. The upload's presigned URL goes on working until it expires, so the object under the
 * key can be replaced a moment after this answer — with anything, of any type, that the edge lets
 * through. A caller that uses the file again later compares {@link StorageService#inspect} with the tag
 * and the row's size first ({@link StoredObject#isStill}); nothing else notices the swap.
 */
public record ConfirmedUpload(FileMetadata file, String etag) {
}

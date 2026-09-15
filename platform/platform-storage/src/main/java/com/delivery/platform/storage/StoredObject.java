package com.delivery.platform.storage;

/**
 * What the bucket holds under one key at the moment it was asked ({@link StorageService#inspect}).
 *
 * @param sizeBytes   the object's length
 * @param etag        storage's entity tag for exactly these bytes, without quotes. Any write through the
 *                    key — a presigned PUT used a second time — gives the object a new one.
 * @param contentType the Content-Type the object was stored with: whatever its uploader's PUT carried
 */
public record StoredObject(long sizeBytes, String etag, String contentType) {

    /**
     * Whether this is still the object a caller recorded at confirm ({@link ConfirmedUpload}): the same
     * length and the same entity tag. False for a recorded tag of null — nothing unrecorded is vouched for.
     */
    public boolean isStill(long recordedSizeBytes, String recordedEtag) {
        return sizeBytes == recordedSizeBytes && recordedEtag != null && recordedEtag.equals(etag);
    }
}

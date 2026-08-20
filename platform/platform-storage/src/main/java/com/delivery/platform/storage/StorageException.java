package com.delivery.platform.storage;

/** Wraps the MinIO SDK's broad checked-exception surface into one unchecked type. */
public class StorageException extends RuntimeException {

    public StorageException(String message) {
        super(message);
    }

    public StorageException(String message, Throwable cause) {
        super(message, cause);
    }
}

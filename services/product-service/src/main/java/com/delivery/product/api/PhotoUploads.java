package com.delivery.product.api;

import java.io.IOException;

import org.springframework.web.multipart.MultipartFile;

import com.delivery.product.service.PhotoSearchException;

/**
 * The checks a photo sent for reading passes before anything reads it: there, small enough, and a JPEG
 * or a PNG.
 *
 * <p>The type is judged by the bytes' own signature, not by the part's declared content type, which is
 * whatever the client wrote: a JPEG is a JPEG however it is labelled, and a HEIC labelled
 * {@code image/jpeg} is not one. These are the only two formats the decoder behind the reader reads
 * ({@code Thumbnailer}).
 *
 * <p>The size is checked here as well as by the servlet container's multipart limit, which answers the
 * same 413 before a byte reaches a controller ({@code ApiExceptionHandler#onUploadTooLarge}): a request
 * that did not pass through the container's parser — a test's, or a future caller's — is held to the
 * same limit.
 */
final class PhotoUploads {

    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF};
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};

    private PhotoUploads() {
    }

    /**
     * The photo's bytes, or the refusal: {@code PHOTO_MISSING} (400), {@code PHOTO_TOO_LARGE} (413),
     * {@code PHOTO_TYPE} (415) or {@code PHOTO_UNREADABLE} (422).
     */
    static byte[] bytesOf(MultipartFile photo, long maxBytes) {
        if (photo == null || photo.isEmpty()) {
            throw PhotoSearchException.missing();
        }
        if (photo.getSize() > maxBytes) {
            throw PhotoSearchException.tooLarge(maxBytes);
        }
        byte[] bytes;
        try {
            bytes = photo.getBytes();
        } catch (IOException e) {
            throw PhotoSearchException.unreadable();
        }
        if (bytes.length > maxBytes) {
            throw PhotoSearchException.tooLarge(maxBytes);
        }
        if (!startsWith(bytes, JPEG) && !startsWith(bytes, PNG)) {
            throw PhotoSearchException.type();
        }
        return bytes;
    }

    private static boolean startsWith(byte[] bytes, byte[] signature) {
        if (bytes.length < signature.length) {
            return false;
        }
        for (int i = 0; i < signature.length; i++) {
            if (bytes[i] != signature[i]) {
                return false;
            }
        }
        return true;
    }
}

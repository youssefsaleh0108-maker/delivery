package com.delivery.platform.storage;

import java.util.Locale;

/**
 * What a file of each content type this library allows begins with — the check, at confirm, that an
 * upload is the kind of file it was declared as rather than merely stored under that type.
 *
 * <p>Why the bytes as well as the stored Content-Type: that header is whatever the uploader's PUT
 * carried, and an uploader who means harm simply sends the declared one. Serving a private file as the
 * checked type ({@code response-content-type}, with nosniff at the edge) keeps a browser from running an
 * HTML page uploaded as a "PDF"; it does nothing about a print shop's software, or anybody who saves the
 * file, opening whatever the bytes really are. Checking the first bytes means such a file is never
 * accepted as a PDF, a JPEG or a PNG in the first place.
 *
 * <p>A type not listed here is not checked by its bytes. Every type on a built-in list is (a test pins
 * that); a service that configures another type for a purpose has chosen one this check cannot vouch for.
 */
final class FileSignature {

    /** Enough of a file's start to recognise every type below: WebP names itself at offset 8. */
    static final int BYTES_NEEDED = 12;

    private static final int[] PDF = {'%', 'P', 'D', 'F'};
    private static final int[] JPEG = {0xFF, 0xD8, 0xFF};
    private static final int[] PNG = {0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A};
    private static final int[] RIFF = {'R', 'I', 'F', 'F'};
    private static final int[] WEBP = {'W', 'E', 'B', 'P'};

    private FileSignature() {
    }

    /** Whether this class knows what a file of {@code contentType} begins with. */
    static boolean isKnown(String contentType) {
        return switch (mediaType(contentType)) {
            case "application/pdf", "image/jpeg", "image/png", "image/webp" -> true;
            default -> false;
        };
    }

    /**
     * Whether {@code head} — the first bytes of a file, up to {@link #BYTES_NEEDED} of them — begins the
     * way a file of {@code contentType} does. True for a type this class does not know.
     */
    static boolean matches(String contentType, byte[] head) {
        return switch (mediaType(contentType)) {
            case "application/pdf" -> startsWith(head, 0, PDF);
            case "image/jpeg" -> startsWith(head, 0, JPEG);
            case "image/png" -> startsWith(head, 0, PNG);
            case "image/webp" -> startsWith(head, 0, RIFF) && startsWith(head, 8, WEBP);
            default -> true;
        };
    }

    /**
     * The media type alone, lower case: {@code "Application/PDF; charset=binary"} is
     * {@code "application/pdf"}. Empty for null.
     */
    static String mediaType(String contentType) {
        if (contentType == null) {
            return "";
        }
        int parameters = contentType.indexOf(';');
        return (parameters < 0 ? contentType : contentType.substring(0, parameters))
                .trim().toLowerCase(Locale.ROOT);
    }

    private static boolean startsWith(byte[] head, int offset, int[] signature) {
        if (head == null || head.length < offset + signature.length) {
            return false;
        }
        for (int i = 0; i < signature.length; i++) {
            if ((head[offset + i] & 0xFF) != signature[i]) {
                return false;
            }
        }
        return true;
    }
}

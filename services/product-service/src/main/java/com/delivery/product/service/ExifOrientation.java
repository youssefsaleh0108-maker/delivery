package com.delivery.product.service;

import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;

/**
 * A JPEG's EXIF orientation, and the turn that stands its pixels upright.
 *
 * <p>A phone camera does not rotate the pixels of a portrait photo. It stores them in the sensor's
 * own landscape frame and adds a tag — EXIF Orientation — saying how to turn them for display, and
 * on Android image_picker hands the photo over that way. Every viewer a merchant uses honours the
 * tag (Flutter's image decoder, every browser), so the photo looks upright everywhere. ImageIO does
 * not: it decodes the stored frame and ignores the tag. So a portrait shelf photo reached the vision
 * model lying on its side, and every box it returned was measured in that sideways frame while the
 * merchant's screen drew the photo upright — the tags landed where the products are not. Product
 * thumbnails came out sideways for the same reason.
 *
 * <p>Read straight off the bytes rather than through a new dependency or ImageIO's metadata tree.
 * Nothing on this service's classpath reads EXIF — no metadata-extractor, commons-imaging or
 * TwelveMonkeys — and ImageIO's JPEG plugin hands an APP1 segment back only as opaque bytes, so that
 * route parses the same structure after a second pass over the file. The one value needed is a
 * 16-bit number at a known place that a few dozen lines reach. Every offset is checked before it is
 * used, and anything unexpected reads as "already upright": a malformed tag must never cost the
 * merchant the photo.
 */
final class ExifOrientation {

    /** Stored upright: nothing to do. Also the answer for anything that is not a tagged JPEG. */
    static final int UPRIGHT = 1;

    private static final int TAG_ORIENTATION = 0x0112;
    private static final int TYPE_SHORT = 3;

    private ExifOrientation() {
    }

    /** The orientation a JPEG's EXIF says to display it at, 1 to 8; {@link #UPRIGHT} otherwise. */
    static int of(byte[] jpeg) {
        try {
            if (jpeg == null || jpeg.length < 4 || u8(jpeg, 0) != 0xFF || u8(jpeg, 1) != 0xD8) {
                return UPRIGHT;
            }
            int at = 2;
            while (at + 4 <= jpeg.length) {
                if (u8(jpeg, at) != 0xFF) {
                    return UPRIGHT;
                }
                int marker = u8(jpeg, at + 1);
                if (marker == 0xFF) {
                    // A fill byte before the marker proper.
                    at++;
                    continue;
                }
                if (marker == 0xDA || marker == 0xD9) {
                    // The pixels, or the end of the file: a camera writes EXIF before either.
                    return UPRIGHT;
                }
                if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
                    // Markers that carry no length.
                    at += 2;
                    continue;
                }
                int length = u16(jpeg, at + 2, true);
                int end = at + 2 + length;
                if (length < 2 || end > jpeg.length) {
                    return UPRIGHT;
                }
                if (marker == 0xE1 && length >= 8 && isExif(jpeg, at + 4)) {
                    return fromTiff(jpeg, at + 10, end);
                }
                at = end;
            }
        } catch (RuntimeException e) {
            // Every read above is bounds-checked; this is only so a photo can never cost a 500.
        }
        return UPRIGHT;
    }

    /**
     * The image turned and mirrored the way {@code orientation} says, onto an opaque RGB canvas —
     * or the very same image when it is already upright.
     */
    static BufferedImage apply(BufferedImage image, int orientation) {
        if (orientation <= UPRIGHT || orientation > 8) {
            return image;
        }
        int w = image.getWidth();
        int h = image.getHeight();
        // AffineTransform(m00, m10, m01, m11, m02, m12): x' = m00*x + m01*y + m02, y' = m10*x + m11*y + m12.
        AffineTransform turn = switch (orientation) {
            case 2 -> new AffineTransform(-1, 0, 0, 1, w, 0);   // mirrored left to right
            case 3 -> new AffineTransform(-1, 0, 0, -1, w, h);  // upside down
            case 4 -> new AffineTransform(1, 0, 0, -1, 0, h);   // mirrored top to bottom
            case 5 -> new AffineTransform(0, 1, 1, 0, 0, 0);    // mirrored across the diagonal
            case 6 -> new AffineTransform(0, 1, -1, 0, h, 0);   // a quarter turn clockwise
            case 7 -> new AffineTransform(0, -1, -1, 0, h, w);  // mirrored across the other diagonal
            default -> new AffineTransform(0, -1, 1, 0, 0, w);  // 8: a quarter turn anticlockwise
        };
        boolean quarterTurn = orientation >= 5;
        BufferedImage upright = new BufferedImage(quarterTurn ? h : w, quarterTurn ? w : h,
                BufferedImage.TYPE_INT_RGB);
        Graphics2D g = upright.createGraphics();
        try {
            // Whole-pixel moves: nearest neighbour copies every pixel exactly instead of blending it
            // with the one beside it.
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_NEAREST_NEIGHBOR);
            g.drawImage(image, turn, null);
        } finally {
            g.dispose();
        }
        return upright;
    }

    /** "Exif\0\0". An APP1 segment can also hold XMP, which says nothing about orientation. */
    private static boolean isExif(byte[] b, int at) {
        return b[at] == 'E' && b[at + 1] == 'x' && b[at + 2] == 'i' && b[at + 3] == 'f'
                && b[at + 4] == 0 && b[at + 5] == 0;
    }

    /** Orientation lives in IFD0 of the TIFF structure the segment carries. */
    private static int fromTiff(byte[] b, int tiff, int end) {
        if (tiff + 8 > end) {
            return UPRIGHT;
        }
        boolean bigEndian;
        if (b[tiff] == 'M' && b[tiff + 1] == 'M') {
            bigEndian = true;
        } else if (b[tiff] == 'I' && b[tiff + 1] == 'I') {
            bigEndian = false;
        } else {
            return UPRIGHT;
        }
        if (u16(b, tiff + 2, bigEndian) != 42) {
            return UPRIGHT;
        }
        long offset = u32(b, tiff + 4, bigEndian);
        if (offset < 8 || tiff + offset + 2 > end) {
            return UPRIGHT;
        }
        int directory = tiff + (int) offset;
        int entries = u16(b, directory, bigEndian);
        for (int i = 0; i < entries; i++) {
            int entry = directory + 2 + i * 12;
            if (entry + 12 > end) {
                return UPRIGHT;
            }
            if (u16(b, entry, bigEndian) == TAG_ORIENTATION) {
                if (u16(b, entry + 2, bigEndian) != TYPE_SHORT) {
                    return UPRIGHT;
                }
                int value = u16(b, entry + 8, bigEndian);
                return value >= 1 && value <= 8 ? value : UPRIGHT;
            }
        }
        return UPRIGHT;
    }

    private static int u8(byte[] b, int at) {
        return b[at] & 0xFF;
    }

    private static int u16(byte[] b, int at, boolean bigEndian) {
        return bigEndian
                ? (u8(b, at) << 8) | u8(b, at + 1)
                : (u8(b, at + 1) << 8) | u8(b, at);
    }

    private static long u32(byte[] b, int at, boolean bigEndian) {
        long high = u16(b, bigEndian ? at : at + 2, bigEndian);
        long low = u16(b, bigEndian ? at + 2 : at, bigEndian);
        return (high << 16) | low;
    }
}

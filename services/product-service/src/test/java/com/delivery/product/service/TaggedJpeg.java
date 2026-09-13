package com.delivery.product.service;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

import javax.imageio.ImageIO;

/**
 * A JPEG laid out the way a phone camera writes one: the start-of-image marker, then an EXIF APP1
 * segment carrying Orientation, then the pixels — and no JFIF header, which a camera does not write
 * either.
 *
 * <p>The stored picture is a dark blue field with a red block over its top-left quarter, so a test
 * can see where that corner ends up once the photo has been stood upright.
 */
final class TaggedJpeg {

    /** Where the EXIF segment this writes ends: 2 bytes of SOI, then a 36-byte APP1. */
    static final int TAG_END = 38;

    private TaggedJpeg() {
    }

    static byte[] of(int width, int height, int orientation, boolean littleEndian) {
        return tag(plain(width, height), orientation, littleEndian);
    }

    /** The same picture with no EXIF at all, straight out of ImageIO. */
    static byte[] plain(int width, int height) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = image.createGraphics();
        g.setColor(new Color(0x20, 0x50, 0xA0));
        g.fillRect(0, 0, width, height);
        g.setColor(Color.RED);
        g.fillRect(0, 0, width / 4, height / 4);
        g.dispose();
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            ImageIO.write(image, "jpg", out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    static boolean isRed(int rgb) {
        int r = (rgb >> 16) & 0xFF;
        int g = (rgb >> 8) & 0xFF;
        int b = rgb & 0xFF;
        return r > 180 && g < 90 && b < 90;
    }

    private static byte[] tag(byte[] jpeg, int orientation, boolean littleEndian) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(jpeg, 0, 2);
        // Skip ImageIO's JFIF APP0, as a camera writes none.
        int rest = 2;
        if ((jpeg[2] & 0xFF) == 0xFF && (jpeg[3] & 0xFF) == 0xE0) {
            rest = 4 + (((jpeg[4] & 0xFF) << 8) | (jpeg[5] & 0xFF));
        }
        byte o = (byte) orientation;
        byte[] tiff = littleEndian
                // "II", 42, IFD0 at 8; one entry: tag 0x0112, SHORT, count 1, value; no next IFD.
                ? new byte[] {'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3, 0, 1, 0, 0, 0, o, 0, 0, 0,
                        0, 0, 0, 0}
                : new byte[] {'M', 'M', 0, 42, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, o, 0, 0,
                        0, 0, 0, 0};
        byte[] exif = {'E', 'x', 'i', 'f', 0, 0};
        int length = 2 + exif.length + tiff.length;
        out.write(0xFF);
        out.write(0xE1);
        out.write(length >> 8);
        out.write(length & 0xFF);
        out.write(exif, 0, exif.length);
        out.write(tiff, 0, tiff.length);
        out.write(jpeg, rest, jpeg.length - rest);
        return out.toByteArray();
    }
}

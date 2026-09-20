package com.delivery.product.shoppage;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.EnumMap;
import java.util.Map;

import javax.imageio.ImageIO;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.EncodeHintType;
import com.google.zxing.WriterException;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;

/**
 * The QR code a shop prints and sticks on its counter.
 *
 * <p>Generated here, in the service, and not by a script in the page. The site's policy is
 * {@code script-src 'self'} with no third-party origin at all, so the QR libraries every other
 * site loads from a CDN are not available to this one — and a printed sign should not depend on a
 * stranger's CDN being up on the morning it is printed anyway. The page links to a PNG; the phone
 * that scans it never runs anything.
 *
 * <p>The image is a pure function of the URL, and the URL is a pure function of the slug, which a
 * shop keeps for life. That is why it can be cached for a year.
 */
final class ShopQrCode {

    private ShopQrCode() {
    }

    /**
     * Roughly the long edge of the image, in pixels.
     *
     * <p>Sized for the sign it is going on: an A5 card is 148 mm across, a QR printed on one is
     * about 90 mm of that, and 90 mm at 300 dpi is about 1,063 pixels. 1,024 is that, rounded to
     * something that divides cleanly, and it costs about 2 kB as a one-bit PNG — a printer has
     * enough dots to keep the modules square, and nobody is waiting on the download.
     */
    static final int SIZE_PX = 1024;

    /**
     * The quiet zone, in modules.
     *
     * <p>Four is the specification's minimum and it is not decoration: a scanner finds the symbol
     * by the contrast at its border, and a code printed hard against a shop's artwork is the
     * commonest reason a printed QR will not read.
     */
    private static final int QUIET_ZONE_MODULES = 4;

    /**
     * Encodes a URL as a black-and-white PNG.
     *
     * <p>Error correction M — about 15% of the symbol can be lost and still read. Not L, because
     * this one is printed and then lives on a counter: it gets splashed, rubbed and taped over.
     * Not Q or H, which would grow the symbol for a URL that is already short.
     *
     * @throws IllegalArgumentException if the content is too long for any QR version, which for a
     *         shop URL would mean a slug far past the 180 characters the column allows
     */
    static byte[] pngOf(String url) {
        Map<EncodeHintType, Object> hints = new EnumMap<>(EncodeHintType.class);
        hints.put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.M);
        // A shop slug is ASCII, but the hint is what stops the encoder guessing a platform default
        // charset for a URL that one day carries something else.
        hints.put(EncodeHintType.CHARACTER_SET, "UTF-8");
        hints.put(EncodeHintType.MARGIN, QUIET_ZONE_MODULES);

        BitMatrix matrix;
        try {
            matrix = new QRCodeWriter().encode(url, BarcodeFormat.QR_CODE, SIZE_PX, SIZE_PX, hints);
        } catch (WriterException e) {
            throw new IllegalArgumentException("Could not encode " + url + " as a QR code", e);
        }

        // One bit per pixel. A QR code is two colours, and TYPE_BYTE_BINARY is what makes the PNG
        // writer emit a 1-bit image rather than a 24-bit one: about 2 kB instead of about 30 kB,
        // for exactly the same picture.
        BufferedImage image = new BufferedImage(matrix.getWidth(), matrix.getHeight(),
                BufferedImage.TYPE_BYTE_BINARY);
        for (int y = 0; y < matrix.getHeight(); y++) {
            for (int x = 0; x < matrix.getWidth(); x++) {
                image.setRGB(x, y, matrix.get(x, y) ? 0x000000 : 0xFFFFFF);
            }
        }

        ByteArrayOutputStream out = new ByteArrayOutputStream(4096);
        try {
            if (!ImageIO.write(image, "png", out)) {
                throw new IllegalStateException("This JVM has no PNG writer");
            }
        } catch (IOException e) {
            // Writing to a byte array cannot fail for any reason the caller could act on.
            throw new UncheckedIOException(e);
        }
        return out.toByteArray();
    }
}

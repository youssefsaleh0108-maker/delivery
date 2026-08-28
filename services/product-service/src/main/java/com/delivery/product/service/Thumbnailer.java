package com.delivery.product.service;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Iterator;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.MemoryCacheImageInputStream;
import javax.imageio.stream.MemoryCacheImageOutputStream;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Turns an uploaded photo into the small JPEG a list row actually needs.
 *
 * <p>The problem this exists for, measured from outside the datacentre: three product photos on one
 * shop screen were 631 KB, 575 KB and 410 KB and took 2.0–2.9 s each to arrive, for an 80 dp row
 * thumbnail. The bytes on the wire were roughly fifty times what the pixels on screen could show.
 *
 * <p>Pure and stateless on purpose — no storage, no database, no Spring beyond the one tuning
 * property. Everything that can go wrong with an image goes wrong in here, which makes it the one
 * class worth testing exhaustively, and makes the calling services' job just "call this, and carry
 * on if it throws".
 */
@Component
public class Thumbnailer {

    /**
     * The long edge of every derivative: 320 px.
     *
     * <p>Sized from the largest list surface that will load it, not from a round number. The
     * customer shop page draws an 80 dp row thumbnail, which is 240 physical px on a 3x phone; the
     * home screen's shop cards draw a 100 dp and a 130 dp cover, which are 200 and 260 px at 2x.
     * 320 covers all three with headroom and leaves room for one more design iteration before a
     * list surface outgrows it.
     *
     * <p>It is deliberately <em>not</em> big enough for the detail surfaces — the 280 dp product
     * hero and the shop cover hero. Those keep loading the original. A single derivative that
     * served both would have to be sized for the hero, which is most of the way back to the
     * problem.
     */
    public static final int LONG_EDGE_PX = 320;

    /** Derivatives are always JPEG, whatever the source was. */
    public static final String CONTENT_TYPE = "image/jpeg";

    /**
     * JPEG quality 0.82.
     *
     * <p>The knee of the curve for photographic content at this size. Below about 0.75 the ringing
     * around packaging text and logos — which is most of what a product photo contains — is visible
     * at 1:1; above about 0.85 the file grows steeply to encode differences nobody can see in an
     * 80 dp square. ImageIO's own default is 0.75, which is slightly too soft for label text.
     */
    private static final float JPEG_QUALITY = 0.82f;

    /**
     * Appended to the original's key, replacing its extension.
     *
     * <p><strong>Suffix rather than a {@code thumb/} prefix.</strong> The derivative stays in the
     * same folder as the original — {@code products/{productId}/…} or {@code stores/{storeId}/…} —
     * so every existing thing that reasons about a key prefix keeps working unchanged: the
     * namespacing {@link ProductImageService#presign} sets up, and any per-product orphan sweep
     * that lists one prefix. A top-level {@code thumb/} prefix would make derivatives easy to
     * expire as a set, which is the one thing it is better at, at the cost of every such sweep
     * silently leaving half the objects behind.
     *
     * <p>The key is also a pure function of the original's key, so nothing has to store or look up
     * a second identifier to find a thumbnail.
     */
    private static final String THUMB_SUFFIX = "-thumb.jpg";

    /**
     * The most pixels this will decode. 40 megapixels by default.
     *
     * <p>The upload size cap does not bound this: compressed size and decoded size are unrelated.
     * A 50000x50000 PNG of flat colour is a few hundred kilobytes on disk and comfortably inside
     * the 10 MB upload limit, and 2.5 gigapixels — ten gigabytes of ARGB raster — the moment
     * anything decodes it. That is a decompression bomb, and the pod dies before the request
     * finishes.
     *
     * <p>40 MP is above any camera a merchant is photographing stock with, and about 160 MB of
     * raster if one ever arrives, which the service survives.
     */
    private final long maxSourcePixels;

    public Thumbnailer(
            @Value("${delivery.catalog.thumbnail.max-source-pixels:40000000}") long maxSourcePixels) {
        this.maxSourcePixels = maxSourcePixels;
    }

    /**
     * Raised for every reason a thumbnail cannot be produced, so callers have one thing to catch.
     *
     * <p>Never a reason to fail the upload it came from — see
     * {@link ThumbnailService#createFor}.
     */
    public static class ThumbnailUnavailableException extends RuntimeException {

        public ThumbnailUnavailableException(String message) {
            super(message);
        }

        public ThumbnailUnavailableException(String message, Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * The object key a given original's thumbnail lives at.
     *
     * <p>Replaces the extension rather than appending to it, because the output is JPEG regardless
     * of what went in: {@code products/x/ab-cd.png} becomes {@code products/x/ab-cd-thumb.jpg}. The
     * stem is a server-generated UUID, which cannot itself end in {@code -thumb}, so a derivative's
     * key can never collide with an original's.
     */
    public static String thumbKeyFor(String objectKey) {
        int dot = objectKey.lastIndexOf('.');
        int slash = objectKey.lastIndexOf('/');
        String stem = dot > slash ? objectKey.substring(0, dot) : objectKey;
        return stem + THUMB_SUFFIX;
    }

    /** Whether a key is one of this class's own derivatives, rather than an uploaded original. */
    public static boolean isThumbKey(String objectKey) {
        return objectKey != null && objectKey.endsWith(THUMB_SUFFIX);
    }

    /**
     * Decodes, shrinks and re-encodes.
     *
     * @throws ThumbnailUnavailableException for anything at all — an unreadable format, a truncated
     *                                       file, a colour model ImageIO will not convert, or a
     *                                       source too large to decode safely
     */
    public byte[] render(byte[] source) {
        if (source == null || source.length == 0) {
            throw new ThumbnailUnavailableException("nothing to read");
        }

        BufferedImage decoded = decodeWithinBudget(source);
        try {
            return encodeJpeg(scale(decoded));
        } catch (IOException | RuntimeException e) {
            throw new ThumbnailUnavailableException("could not encode the thumbnail", e);
        } finally {
            decoded.flush();
        }
    }

    /**
     * Reads the dimensions out of the header, refuses an absurd one, and only then decodes pixels.
     *
     * <p>The order is the whole point. {@code ImageReader.getWidth}/{@code getHeight} parse the
     * format's header — a PNG IHDR, a JPEG SOF marker — without allocating a raster, so the guard
     * costs a few dozen bytes and runs before the allocation it is protecting against.
     * {@code ImageIO.read} would have allocated first and asked questions afterwards.
     */
    private BufferedImage decodeWithinBudget(byte[] source) {
        try (ImageInputStream in = new MemoryCacheImageInputStream(new ByteArrayInputStream(source))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(in);
            if (!readers.hasNext()) {
                throw new ThumbnailUnavailableException("no ImageIO reader recognises these bytes");
            }

            ImageReader reader = readers.next();
            try {
                reader.setInput(in, true, true);

                long pixels = (long) reader.getWidth(0) * reader.getHeight(0);
                if (pixels > maxSourcePixels) {
                    throw new ThumbnailUnavailableException(
                            "source is " + reader.getWidth(0) + "x" + reader.getHeight(0)
                                    + " (" + pixels + " pixels), over the " + maxSourcePixels
                                    + "-pixel decode limit");
                }

                BufferedImage image = reader.read(0);
                if (image == null) {
                    throw new ThumbnailUnavailableException("the reader produced no image");
                }
                return image;
            } finally {
                reader.dispose();
            }
        } catch (ThumbnailUnavailableException e) {
            throw e;
        } catch (IOException | RuntimeException e) {
            // Truncated files, unsupported colour models and malformed headers all land here, and
            // they all mean the same thing to the caller.
            throw new ThumbnailUnavailableException("could not decode the source image", e);
        }
    }

    /**
     * Shrinks to {@link #LONG_EDGE_PX} on the long edge, preserving the aspect ratio.
     *
     * <p>Halves repeatedly before the final step rather than jumping straight to the target. A
     * single bilinear pass from 4000 px to 320 px samples about one source pixel in twelve and
     * aliases badly on anything with fine detail — exactly the packaging and text a product photo
     * is full of. Each halving averages every pixel it discards, so the last step starts from
     * something already close to the target.
     *
     * <p>Never upscales: a source smaller than the target is copied at its own size. A 200 px photo
     * blown up to 320 px would be bigger on the wire and no better on screen.
     */
    private static BufferedImage scale(BufferedImage source) {
        int width = source.getWidth();
        int height = source.getHeight();

        double factor = Math.min(1.0, (double) LONG_EDGE_PX / Math.max(width, height));
        int targetWidth = Math.max(1, (int) Math.round(width * factor));
        int targetHeight = Math.max(1, (int) Math.round(height * factor));

        BufferedImage current = source;
        int currentWidth = width;
        int currentHeight = height;
        while (currentWidth > targetWidth * 2 && currentHeight > targetHeight * 2) {
            currentWidth /= 2;
            currentHeight /= 2;
            current = draw(current, currentWidth, currentHeight);
        }
        return draw(current, targetWidth, targetHeight);
    }

    /**
     * One resampling step onto an opaque RGB canvas.
     *
     * <p>{@code TYPE_INT_RGB} over a white fill, not {@code TYPE_INT_ARGB}: JPEG has no alpha
     * channel, and handing a writer an image that has one produces either a refusal or — worse —
     * silently inverted colours, because the four bands get read as CMYK. A transparent PNG's
     * background therefore becomes white here, deliberately, rather than black.
     */
    private static BufferedImage draw(BufferedImage source, int width, int height) {
        BufferedImage target = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = target.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING,
                    RenderingHints.VALUE_RENDER_QUALITY);
            g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                    RenderingHints.VALUE_ANTIALIAS_ON);
            g.setColor(Color.WHITE);
            g.fillRect(0, 0, width, height);
            g.drawImage(source, 0, 0, width, height, null);
        } finally {
            g.dispose();
        }
        return target;
    }

    private static byte[] encodeJpeg(BufferedImage image) throws IOException {
        Iterator<ImageWriter> writers = ImageIO.getImageWritersByFormatName("jpeg");
        if (!writers.hasNext()) {
            throw new ThumbnailUnavailableException("no JPEG writer on this JVM");
        }

        ImageWriter writer = writers.next();
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (MemoryCacheImageOutputStream out = new MemoryCacheImageOutputStream(bytes)) {
            ImageWriteParam params = writer.getDefaultWriteParam();
            if (params.canWriteCompressed()) {
                params.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
                params.setCompressionQuality(JPEG_QUALITY);
            }
            writer.setOutput(out);
            writer.write(null, new IIOImage(image, null, null), params);
            out.flush();
        } finally {
            writer.dispose();
        }
        return bytes.toByteArray();
    }
}

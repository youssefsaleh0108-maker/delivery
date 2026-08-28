package com.delivery.product.service;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Random;
import java.util.zip.CRC32;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import com.delivery.product.service.Thumbnailer.ThumbnailUnavailableException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The image work itself, which is where every interesting failure lives.
 *
 * <p>Two things are being pinned down. First, that the derivative is the size the list screens
 * need and no bigger — the measured problem was 631 KB arriving to fill an 80 dp square. Second,
 * that no input can turn an upload into an incident: a truncated file, a format ImageIO does not
 * know, or a header claiming fifty thousand pixels a side.
 */
class ThumbnailerTest {

    /** The production default, restated here so a change to it shows up as a failing test. */
    private static final long MAX_SOURCE_PIXELS = 40_000_000L;

    private final Thumbnailer thumbnailer = new Thumbnailer(MAX_SOURCE_PIXELS);

    // ---------------------------------------------------------------- fixtures

    /**
     * Something with enough detail to compress like a photograph.
     *
     * <p>A flat fill would encode to almost nothing and make the size assertions meaningless.
     * A fixed seed keeps the byte counts reproducible.
     */
    private static BufferedImage photoLike(int width, int height) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Random random = new Random(42);
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int r = (x * 255 / Math.max(1, width) + random.nextInt(40)) & 0xFF;
                int g = (y * 255 / Math.max(1, height) + random.nextInt(40)) & 0xFF;
                int b = ((x + y) * 255 / Math.max(1, width + height) + random.nextInt(40)) & 0xFF;
                image.setRGB(x, y, (r << 16) | (g << 8) | b);
            }
        }
        Graphics2D g = image.createGraphics();
        g.setColor(Color.WHITE);
        g.fillRect(width / 8, height / 8, width / 3, height / 6);
        g.setColor(Color.BLACK);
        g.drawString("PRODUCT", width / 6, height / 5);
        g.dispose();
        return image;
    }

    private static byte[] encode(BufferedImage image, String format) {
        try {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            assertThat(ImageIO.write(image, format, out)).isTrue();
            return out.toByteArray();
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    private static BufferedImage decode(byte[] bytes) {
        try {
            BufferedImage image = ImageIO.read(new ByteArrayInputStream(bytes));
            assertThat(image).isNotNull();
            return image;
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    private static byte[] jpeg(int width, int height) {
        return encode(photoLike(width, height), "jpg");
    }

    // ---------------------------------------------------------------- size

    @Nested
    @DisplayName("the size it comes out at")
    class Size {

        @Test
        void a_landscape_photo_is_320_on_its_long_edge() {
            BufferedImage thumb = decode(thumbnailer.render(jpeg(2000, 1500)));

            assertThat(thumb.getWidth()).isEqualTo(Thumbnailer.LONG_EDGE_PX);
            assertThat(thumb.getHeight()).isEqualTo(240);
        }

        @Test
        void a_portrait_photo_is_320_on_its_long_edge_too() {
            BufferedImage thumb = decode(thumbnailer.render(jpeg(1500, 2000)));

            assertThat(thumb.getHeight()).isEqualTo(Thumbnailer.LONG_EDGE_PX);
            assertThat(thumb.getWidth()).isEqualTo(240);
        }

        /**
         * The ratio, not the rounding. A squashed thumbnail beside a correct hero is a visible bug
         * on the one screen this whole change exists to fix.
         */
        @Test
        void the_aspect_ratio_survives_an_awkward_ratio() {
            BufferedImage thumb = decode(thumbnailer.render(jpeg(1600, 900)));

            assertThat(thumb.getWidth()).isEqualTo(320);
            assertThat((double) thumb.getWidth() / thumb.getHeight())
                    .isCloseTo(1600.0 / 900.0, org.assertj.core.data.Offset.offset(0.01));
        }

        @Test
        void a_square_photo_stays_square() {
            BufferedImage thumb = decode(thumbnailer.render(jpeg(1024, 1024)));

            assertThat(thumb.getWidth()).isEqualTo(320);
            assertThat(thumb.getHeight()).isEqualTo(320);
        }

        /** Blowing a 200 px photo up to 320 would cost bytes and add nothing. */
        @Test
        void a_source_already_smaller_than_the_target_is_not_upscaled() {
            BufferedImage thumb = decode(thumbnailer.render(jpeg(200, 120)));

            assertThat(thumb.getWidth()).isEqualTo(200);
            assertThat(thumb.getHeight()).isEqualTo(120);
        }

        /** A one-pixel-tall banner must not round its short edge down to nothing. */
        @Test
        void an_extreme_ratio_keeps_at_least_one_pixel_on_the_short_edge() {
            BufferedImage thumb = decode(thumbnailer.render(jpeg(4000, 3)));

            assertThat(thumb.getWidth()).isEqualTo(320);
            assertThat(thumb.getHeight()).isGreaterThanOrEqualTo(1);
        }
    }

    // ---------------------------------------------------------------- weight

    @Nested
    @DisplayName("what it weighs")
    class Weight {

        /**
         * The number the change is for.
         *
         * <p>Measured from production: three photos on one shop screen at 631 KB, 575 KB and
         * 410 KB, 2.0–2.9 s each, rendered into an 80 dp square.
         *
         * <p>On the fixture below — deliberately noisier than a real photograph, which is the
         * hardest case for a 2:1 downscale — 80,967 bytes at 640x480 come out as 17,575 at
         * 320x240. The bounds are looser than those figures because the exact count depends on the
         * JDK's encoder; what must not change is the order of magnitude.
         */
        @Test
        void a_640px_source_reduces_by_several_times() {
            byte[] source = jpeg(640, 480);
            byte[] thumb = thumbnailer.render(source);

            assertThat(thumb.length).isLessThan(source.length / 4);
            assertThat(thumb.length).isLessThan(60_000);
        }

        /**
         * The production case. A 2400x1800 photo is 1.1 MB on this fixture and about 9 KB as a
         * derivative — the two orders of magnitude the shop screen was paying for.
         */
        @Test
        void a_photo_sized_like_the_ones_that_were_measured_lands_in_tens_of_kilobytes() {
            byte[] source = jpeg(2400, 1800);
            byte[] thumb = thumbnailer.render(source);

            assertThat(thumb.length).isLessThan(60_000);
            assertThat(thumb.length).isLessThan(source.length / 10);
        }

        @Test
        void the_output_is_a_jpeg_whatever_went_in() {
            byte[] fromPng = thumbnailer.render(encode(photoLike(800, 600), "png"));

            // SOI: every JPEG starts FF D8.
            assertThat(fromPng[0] & 0xFF).isEqualTo(0xFF);
            assertThat(fromPng[1] & 0xFF).isEqualTo(0xD8);
        }
    }

    // ---------------------------------------------------------------- refusals

    @Nested
    @DisplayName("input it must refuse rather than choke on")
    class Refusals {

        /**
         * A decompression bomb: tiny on disk, enormous decoded.
         *
         * <p>The IHDR is rewritten to claim 50000x50000 and its CRC recomputed, so the header is
         * valid and the pixels are not. That is the shape of the attack, and it is also the proof
         * that the guard reads the header rather than the image — a Thumbnailer that decoded first
         * would either allocate ten gigabytes here or fail with something other than the limit
         * message.
         */
        @Test
        void a_header_claiming_50000_square_is_refused_before_any_pixel_is_decoded() {
            byte[] bomb = pngClaiming(50_000, 50_000);

            assertThatThrownBy(() -> thumbnailer.render(bomb))
                    .isInstanceOf(ThumbnailUnavailableException.class)
                    .hasMessageContaining("decode limit");
        }

        @Test
        void a_source_just_over_the_pixel_budget_is_refused_and_one_just_under_is_not() {
            Thumbnailer small = new Thumbnailer(10_000);

            assertThatThrownBy(() -> small.render(jpeg(200, 100)))
                    .isInstanceOf(ThumbnailUnavailableException.class);
            assertThat(small.render(jpeg(90, 100))).isNotEmpty();
        }

        @Test
        void bytes_that_are_not_an_image_at_all_are_refused() {
            assertThatThrownBy(() -> thumbnailer.render("not an image".getBytes(StandardCharsets.UTF_8)))
                    .isInstanceOf(ThumbnailUnavailableException.class);
        }

        /**
         * Cut inside the header, before the frame that declares the dimensions.
         *
         * <p>Worth being precise about what is <em>not</em> claimed here: a JPEG truncated further
         * in, inside the scan data, is not refused. ImageIO decodes what arrived and greys out the
         * rest, and that is the right outcome — the original is truncated in exactly the same way,
         * so the thumbnail and the hero degrade together rather than one of them disappearing.
         */
        @Test
        void a_file_truncated_inside_its_header_is_refused() {
            byte[] whole = jpeg(800, 600);
            byte[] stub = new byte[40];
            System.arraycopy(whole, 0, stub, 0, stub.length);

            assertThatThrownBy(() -> thumbnailer.render(stub))
                    .isInstanceOf(ThumbnailUnavailableException.class);
        }

        @Test
        void nothing_at_all_is_refused() {
            assertThatThrownBy(() -> thumbnailer.render(new byte[0]))
                    .isInstanceOf(ThumbnailUnavailableException.class);
            assertThatThrownBy(() -> thumbnailer.render(null))
                    .isInstanceOf(ThumbnailUnavailableException.class);
        }

        /**
         * A transparent PNG has a colour model JPEG cannot represent. The naive conversion either
         * throws or writes four bands that a decoder reads as CMYK — the classic inverted
         * thumbnail. It must simply come out opaque.
         */
        @Test
        void a_transparent_png_becomes_an_opaque_jpeg_rather_than_failing() {
            BufferedImage transparent = new BufferedImage(600, 400, BufferedImage.TYPE_INT_ARGB);
            Graphics2D g = transparent.createGraphics();
            g.setColor(new Color(200, 30, 30, 255));
            g.fillOval(100, 50, 300, 200);
            g.dispose();

            BufferedImage thumb = decode(thumbnailer.render(encode(transparent, "png")));

            assertThat(thumb.getWidth()).isEqualTo(320);
            // The corner was fully transparent; it must be white, not black and not an exception.
            Color corner = new Color(thumb.getRGB(2, 2));
            assertThat(corner.getRed()).isGreaterThan(240);
            assertThat(corner.getGreen()).isGreaterThan(240);
            assertThat(corner.getBlue()).isGreaterThan(240);
        }
    }

    // ---------------------------------------------------------------- keys

    @Nested
    @DisplayName("where the derivative is filed")
    class Keys {

        @Test
        void it_sits_beside_its_original_with_a_jpg_extension() {
            assertThat(Thumbnailer.thumbKeyFor("products/abc/11111111-2222-3333-4444-555555555555.jpg"))
                    .isEqualTo("products/abc/11111111-2222-3333-4444-555555555555-thumb.jpg");
        }

        /** The output is JPEG regardless of the source, so the extension is replaced, not kept. */
        @Test
        void a_png_original_still_gets_a_jpg_derivative() {
            assertThat(Thumbnailer.thumbKeyFor("stores/abc/logo/deadbeef.png"))
                    .isEqualTo("stores/abc/logo/deadbeef-thumb.jpg");
        }

        @Test
        void a_key_with_no_extension_still_resolves() {
            assertThat(Thumbnailer.thumbKeyFor("products/abc/plain"))
                    .isEqualTo("products/abc/plain-thumb.jpg");
        }

        /** A dot in a folder name is not an extension. */
        @Test
        void a_dot_before_the_last_slash_is_not_treated_as_an_extension() {
            assertThat(Thumbnailer.thumbKeyFor("products/v1.2/file"))
                    .isEqualTo("products/v1.2/file-thumb.jpg");
        }

        @Test
        void a_derivative_is_recognisable_as_one() {
            assertThat(Thumbnailer.isThumbKey("products/a/b-thumb.jpg")).isTrue();
            assertThat(Thumbnailer.isThumbKey("products/a/b.jpg")).isFalse();
            assertThat(Thumbnailer.isThumbKey(null)).isFalse();
        }
    }

    /**
     * A real, small PNG whose IHDR has been rewritten to claim the given dimensions, CRC included.
     *
     * <p>PNG layout: 8-byte signature, then the IHDR chunk — a 4-byte length, the 4-byte type, 13
     * bytes of header (width, height, then five single-byte fields) and a 4-byte CRC over the type
     * and the data. So width sits at offset 16, height at 20, and the CRC at 29.
     */
    private static byte[] pngClaiming(int width, int height) {
        byte[] png = encode(photoLike(4, 4), "png");
        ByteBuffer buffer = ByteBuffer.wrap(png);
        buffer.putInt(16, width);
        buffer.putInt(20, height);

        CRC32 crc = new CRC32();
        crc.update(png, 12, 17);
        buffer.putInt(29, (int) crc.getValue());
        return png;
    }
}

package com.delivery.product.service;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * A camera's orientation tag, honoured the way every viewer a merchant uses honours it.
 *
 * <p>A phone stores a portrait photo as landscape pixels plus a tag saying "turn me". The merchant's
 * screen draws it upright; ImageIO would not. What is pinned: the tag is found in either byte order
 * and never guessed from a damaged file, and a photo leaves {@link Thumbnailer} upright — with the
 * corner that was stored top-left where the turn puts it, not merely the right way round in size.
 */
@DisplayName("a camera photo's orientation tag")
class ExifOrientationTest {

    private final Thumbnailer thumbnailer = new Thumbnailer(40_000_000L);

    private static BufferedImage decode(byte[] bytes) throws IOException {
        BufferedImage image = ImageIO.read(new ByteArrayInputStream(bytes));
        assertThat(image).isNotNull();
        return image;
    }

    @Test
    void the_tag_is_read_in_either_byte_order_and_anything_else_reads_as_upright() {
        assertThat(ExifOrientation.of(TaggedJpeg.of(40, 20, 6, true))).isEqualTo(6);
        assertThat(ExifOrientation.of(TaggedJpeg.of(40, 20, 8, false))).isEqualTo(8);
        assertThat(ExifOrientation.of(TaggedJpeg.plain(40, 20))).isEqualTo(1);
        assertThat(ExifOrientation.of("not a photo".getBytes(StandardCharsets.US_ASCII))).isEqualTo(1);
        assertThat(ExifOrientation.of(null)).isEqualTo(1);
    }

    /** Cut off anywhere inside the tag: never an exception, never a guess. */
    @Test
    void a_file_cut_short_inside_its_tag_reads_as_upright() {
        byte[] tagged = TaggedJpeg.of(40, 20, 6, false);

        for (int cut = 0; cut < TaggedJpeg.TAG_END; cut++) {
            assertThat(ExifOrientation.of(Arrays.copyOf(tagged, cut))).as("cut at %d", cut).isEqualTo(1);
        }
        assertThat(ExifOrientation.of(Arrays.copyOf(tagged, TaggedJpeg.TAG_END))).isEqualTo(6);
    }

    /** 6 is "turn a quarter clockwise": the stored top-left corner ends up top right. */
    @Test
    void a_photo_tagged_six_comes_out_portrait_with_its_stored_top_left_at_the_top_right() throws IOException {
        BufferedImage out = decode(thumbnailer.renderLongEdge(TaggedJpeg.of(400, 200, 6, false), 400));

        assertThat(out.getWidth()).isEqualTo(200);
        assertThat(out.getHeight()).isEqualTo(400);
        assertThat(TaggedJpeg.isRed(out.getRGB(190, 10))).isTrue();
        assertThat(TaggedJpeg.isRed(out.getRGB(10, 10))).isFalse();
    }

    @Test
    void a_photo_tagged_eight_turns_the_other_way_and_three_turns_right_over() throws IOException {
        BufferedImage eight = decode(thumbnailer.renderLongEdge(TaggedJpeg.of(400, 200, 8, true), 400));
        assertThat(eight.getWidth()).isEqualTo(200);
        assertThat(eight.getHeight()).isEqualTo(400);
        assertThat(TaggedJpeg.isRed(eight.getRGB(10, 390))).isTrue();

        BufferedImage three = decode(thumbnailer.renderLongEdge(TaggedJpeg.of(400, 200, 3, false), 400));
        assertThat(three.getWidth()).isEqualTo(400);
        assertThat(three.getHeight()).isEqualTo(200);
        assertThat(TaggedJpeg.isRed(three.getRGB(390, 190))).isTrue();
    }

    /** Shrinking and turning together: the long edge is still the one that is capped. */
    @Test
    void a_tagged_photo_is_shrunk_on_its_long_edge_and_turned() throws IOException {
        BufferedImage out = decode(thumbnailer.renderLongEdge(TaggedJpeg.of(1600, 800, 6, false), 400));

        assertThat(out.getWidth()).isEqualTo(200);
        assertThat(out.getHeight()).isEqualTo(400);
        assertThat(TaggedJpeg.isRed(out.getRGB(190, 10))).isTrue();
    }

    @Test
    void a_photo_with_no_tag_is_left_exactly_as_it_was_stored() throws IOException {
        BufferedImage out = decode(thumbnailer.renderLongEdge(TaggedJpeg.plain(400, 200), 400));

        assertThat(out.getWidth()).isEqualTo(400);
        assertThat(out.getHeight()).isEqualTo(200);
        assertThat(TaggedJpeg.isRed(out.getRGB(10, 10))).isTrue();
    }
}

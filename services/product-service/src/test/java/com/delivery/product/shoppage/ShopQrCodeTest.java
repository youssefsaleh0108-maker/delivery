package com.delivery.product.shoppage;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.util.EnumMap;
import java.util.Map;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MvcResult;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.client.j2se.BufferedImageLuminanceSource;
import com.google.zxing.common.HybridBinarizer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * {@code GET /s/{slug}/qr.png}: the code a shop prints and tapes to its counter.
 *
 * <p>The only assertion worth making about a QR code is that a scanner reads it, so this one
 * decodes the PNG the endpoint actually returned — bytes, luminance, binarise, detect, decode —
 * rather than comparing the encoder to itself. If the symbol were malformed, the mask chosen badly
 * or the quiet zone missing, this is where it would show, and not on a printed sign nobody can fix
 * remotely.
 */
@DisplayName("a shop's QR code")
class ShopQrCodeTest {

    private static BufferedImage decodeImage(byte[] png) throws Exception {
        BufferedImage image = ImageIO.read(new ByteArrayInputStream(png));
        assertThat(image).as("the bytes are a PNG this JVM can read").isNotNull();
        return image;
    }

    private static String scan(byte[] png) throws Exception {
        BinaryBitmap bitmap = new BinaryBitmap(
                new HybridBinarizer(new BufferedImageLuminanceSource(decodeImage(png))));
        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.TRY_HARDER, Boolean.TRUE);
        return new MultiFormatReader().decode(bitmap, hints).getText();
    }

    @Test
    @DisplayName("the PNG decodes back to the page's own URL")
    void decodesBackToThePage() throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        MvcResult result = shop.mvc().perform(get("/s/" + shop.slug() + "/qr.png"))
                .andExpect(status().isOk())
                .andReturn();

        byte[] png = result.getResponse().getContentAsByteArray();
        assertThat(result.getResponse().getContentType()).isEqualTo("image/png");
        // The PNG signature, so a wrong content type cannot pass by agreeing with itself.
        assertThat(png).startsWith(new byte[] {(byte) 0x89, 'P', 'N', 'G'});
        assertThat(scan(png)).isEqualTo(shop.url());
    }

    @Test
    @DisplayName("it is big enough to print on an A5 sign, and small enough to be free")
    void isSizedForPrinting() throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        byte[] png = shop.mvc().perform(get("/s/" + shop.slug() + "/qr.png"))
                .andReturn().getResponse().getContentAsByteArray();

        BufferedImage image = decodeImage(png);
        // 1,024 px is about 90 mm at 300 dpi, which is the QR on an A5 card.
        assertThat(image.getWidth()).isEqualTo(ShopQrCode.SIZE_PX);
        assertThat(image.getHeight()).isEqualTo(ShopQrCode.SIZE_PX);
        // One bit per pixel. A 24-bit PNG of the same picture is an order of magnitude larger.
        assertThat(png.length).isLessThan(16 * 1024);
    }

    @Test
    @DisplayName("the code points at the page, in neither language: the phone that scans it chooses")
    void encodesTheCanonicalUrl() throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        byte[] arabicRequest = shop.mvc()
                .perform(get("/s/" + shop.slug() + "/qr.png").param("lang", "ar"))
                .andReturn().getResponse().getContentAsByteArray();

        assertThat(scan(arabicRequest)).isEqualTo(shop.url()).doesNotContain("lang=");
    }

    @Test
    @DisplayName("the longest slug the column allows still encodes")
    void encodesTheLongestSlugThereCanBe() throws Exception {
        // slug is varchar(180): 160 characters of name plus a dash and eight hex digits.
        String longest = "a".repeat(160) + "-0123abcd";
        String url = ShopFixtureUrl.of(longest);

        assertThat(scan(ShopQrCode.pngOf(url))).isEqualTo(url);
    }

    /** The shape of a page URL, so the long-slug case does not need a whole shop behind it. */
    private static final class ShopFixtureUrl {
        static String of(String slug) {
            return ShopPageFixture.BASE + "/s/" + slug;
        }
    }

    @Test
    @DisplayName("the code and the stylesheet are cached hard: neither ever changes")
    void isCachedForAYear() throws Exception {
        ShopPageFixture shop = new ShopPageFixture();
        MvcResult result = shop.mvc().perform(get("/s/" + shop.slug() + "/qr.png")).andReturn();

        assertThat(result.getResponse().getHeader("Cache-Control"))
                .contains("max-age=31536000").contains("immutable").contains("public");
        String etag = result.getResponse().getHeader("ETag");
        assertThat(etag).isNotBlank();

        shop.mvc().perform(get("/s/" + shop.slug() + "/qr.png").header("If-None-Match", etag))
                .andExpect(status().isNotModified());
    }
}

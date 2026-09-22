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
import com.google.zxing.ResultMetadataType;
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
    @DisplayName("the longest slug the column allows still encodes, at either resilience")
    void encodesTheLongestSlugThereCanBe() throws Exception {
        // slug is varchar(180): 160 characters of name plus a dash and eight hex digits.
        String longest = "a".repeat(160) + "-0123abcd";
        String url = ShopFixtureUrl.of(longest);

        assertThat(scan(ShopQrCode.pngOf(url, ShopQrCode.Resilience.COUNTER))).isEqualTo(url);
        // And with a table on the end, at the higher correction a table card is printed with: the
        // denser symbol is the case that could have run past what a QR version can hold.
        String table = ShopTableCodes.urlOf(ShopPageFixture.BASE, longest, 400);
        assertThat(scan(ShopQrCode.pngOf(table, ShopQrCode.Resilience.TABLE))).isEqualTo(table);
    }

    @Test
    @DisplayName("a table card's code is encoded to survive a table, and a photocopier")
    void tableCodesCarryMoreCorrection() throws Exception {
        ShopPageFixture shop = new ShopPageFixture().tables(4);
        byte[] counter = shop.mvc().perform(get("/s/" + shop.slug() + "/qr.png"))
                .andReturn().getResponse().getContentAsByteArray();
        byte[] table = shop.mvc().perform(get("/s/" + shop.slug() + "/qr.png").param("t", "3"))
                .andReturn().getResponse().getContentAsByteArray();

        // Both still read, which is the only thing that finally matters.
        assertThat(scan(counter)).isEqualTo(shop.url());
        assertThat(scan(table)).isEqualTo(shop.url() + "?t=3");

        // Read out of the decoded symbol, not out of the constant that made it: what a scanner
        // finds in the printed square is the claim, and a table card claims Q — about a quarter of
        // it recoverable, against the counter sign's sixth. That quarter is what is left after a
        // candle, a water ring and a photocopy have each taken a bite out of it.
        assertThat(correctionOf(table)).isEqualTo("Q");
        assertThat(correctionOf(counter)).isEqualTo("M");
    }

    /** The error-correction level a scanner reports for the symbol it just read. */
    private static String correctionOf(byte[] png) throws Exception {
        BinaryBitmap bitmap = new BinaryBitmap(
                new HybridBinarizer(new BufferedImageLuminanceSource(decodeImage(png))));
        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.TRY_HARDER, Boolean.TRUE);
        return String.valueOf(new MultiFormatReader().decode(bitmap, hints)
                .getResultMetadata().get(ResultMetadataType.ERROR_CORRECTION_LEVEL));
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

package com.delivery.product.shoppage;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.Arrays;
import java.util.Base64;
import java.util.HexFormat;
import java.util.function.LongSupplier;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.util.StreamUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.product.shoppage.PublicShopPageService.ShopPageNotFoundException;
import com.delivery.product.shoppage.ShopPosterHtml.Paper;

/**
 * {@code GET /s/{slug}/poster} — the printable sheet for a shop's counter, and the two stylesheets
 * that lay it out.
 *
 * <p>A controller of its own rather than another method on {@link PublicShopPageController}. The
 * page is a document a stranger reads on a phone and a chat app previews; this is a document a
 * merchant sends to a printer. They answer to different rules — the poster may carry nothing that
 * can go stale, and it is allowed a narrower content policy because it loads one same-origin image
 * and nothing else — and keeping them apart means a change to one cannot quietly change the other.
 *
 * <p>What they do share is the decision about <em>which shops have a page at all</em>, and that is
 * shared by calling {@link PublicShopPageService#read}, not by copying its rule: a draft shop, a
 * suspended shop, a shop with no pin and a slug nobody has ever had all raise the one exception and
 * get the one 404 — the same bytes {@link ShopPageHtml#renderNotFound} writes for the page. A
 * poster for a shop that has no page would be a QR code on a counter pointing at a 404.
 *
 * <p>Anonymous, like everything under {@code /s/**} ({@code delivery.security.permit-all}), and it
 * reads nothing about the caller: there is no {@code CurrentUser} here, so a poster cannot become
 * personalised and cannot be cached for one reader and served to another.
 */
@RestController
public class ShopPosterController {

    /**
     * How long a poster may be reused.
     *
     * <p>The QR code's year, not the page's five minutes, because a poster is the QR code with a
     * name written under it: no price, no opening hour, nothing that moves week to week.
     *
     * <p>Not {@code immutable}, which is the one thing it does not share with the QR. That code is
     * a pure function of a slug that never moves, so it can tell a browser never to ask again; this
     * sheet also carries the shop's <em>name</em>, and {@code Store.updateProfile} can change one.
     * {@code immutable} suppresses even the revalidation a reload would do, so a merchant who
     * renamed the shop and reloaded would print the old name with nothing to explain it. Without
     * it, the ETag makes that reload cost a few hundred bytes and come back right.
     */
    private static final Duration POSTER_MAX_AGE = Duration.ofDays(365);

    /** The stylesheets: this build's own bytes, so they really are immutable. */
    private static final Duration ASSET_MAX_AGE = Duration.ofDays(365);

    /**
     * How long a rendered poster is held, and how many.
     *
     * <p>A day and 128 sheets, which is at most a couple of hundred kilobytes on a pod with 512
     * MiB. This is not the page's traffic problem — nobody links a poster into a WhatsApp status —
     * it is that rendering one costs a full {@link PublicShopPageService#read}, six queries and a
     * shelf of products, to print a name and a slug. A merchant setting up a print run asks for the
     * same sheet several times in a minute, in both papers.
     */
    private static final Duration POSTER_MEMO_FOR = Duration.ofDays(1);

    private static final int POSTER_MEMO_ENTRIES = 128;

    /**
     * What this sheet is allowed to load: one picture, from here.
     *
     * <p>Stricter than the page's, and fixed rather than configured, because the poster has no
     * merchant-supplied artwork on it at all — the QR code is served by this service at
     * {@code /s/{slug}/qr.png}, the stylesheets are served by this service, and there is no third
     * origin in the document to name. Everything else is {@code 'none'}.
     */
    private static final String CONTENT_SECURITY_POLICY = "default-src 'none'; "
            + "img-src 'self'; "
            + "style-src 'self'; "
            + "base-uri 'none'; "
            + "form-action 'none'; "
            + "frame-ancestors 'none'";

    private final PublicShopPageService pages;
    private final String baseUrl;
    private final byte[] stylesheet;
    private final byte[] stylesheetA4;
    private final byte[] stylesheetTables;
    private final ShopPageCache<Sheet> posters;

    /**
     * The rendered card sheets, by shop, language and which table.
     *
     * <p>Shares the poster's window and bound rather than adding a second policy: a sheet of table
     * cards is the same kind of document, asked for in the same burst — a merchant setting up a
     * room asks for the whole sheet, then for table 4 again because the printer ate it — and it
     * costs the same {@link PublicShopPageService#read} to draw a name and a slug twelve times.
     */
    private final ShopPageCache<Sheet> tableSheets;

    @Autowired
    public ShopPosterController(
            PublicShopPageService pages,
            @Value("${delivery.public.base-url:https://www.youdrop.shop}") String baseUrl) {
        this(pages, baseUrl, System::nanoTime);
    }

    /** The clock the memo ages on, injectable so a test can step over an expiry. */
    ShopPosterController(PublicShopPageService pages, String baseUrl, LongSupplier nanoClock) {
        this.pages = pages;
        this.baseUrl = trimTrailingSlash(baseUrl);
        this.stylesheet = read("shoppage/poster.css");
        this.stylesheetA4 = read("shoppage/poster-a4.css");
        this.stylesheetTables = read("shoppage/tables.css");
        this.posters = new ShopPageCache<>(POSTER_MEMO_FOR, POSTER_MEMO_ENTRIES, nanoClock);
        this.tableSheets = new ShopPageCache<>(POSTER_MEMO_FOR, POSTER_MEMO_ENTRIES, nanoClock);
    }

    /**
     * The poster.
     *
     * <p>{@code ?size=a4} asks for the wall-sized copy; anything else is the A5 card. {@code ?lang}
     * and {@code Accept-Language} choose the document's direction and which of the two printed
     * lines comes first — both are always printed, so neither answer is missing an instruction.
     */
    @GetMapping("/s/{slug}/poster")
    public ResponseEntity<byte[]> poster(@PathVariable String slug,
                                         @RequestParam(name = "size", required = false) String size,
                                         @RequestParam(name = "lang", required = false) String lang,
                                         @RequestHeader(name = HttpHeaders.ACCEPT_LANGUAGE,
                                                 required = false) String acceptLanguage,
                                         HttpServletRequest request) {
        ShopPageText text = ShopPageText.choose(lang, acceptLanguage);
        Paper paper = Paper.of(size);
        Sheet sheet;
        try {
            // One rendering per shop per language per paper. The slug is lower-case letters, digits
            // and hyphens, so no key can be made to collide with another shop's.
            sheet = posters.get(slug + "\n" + text.tag() + "\n" + paper.tag(),
                    () -> render(slug, text, paper));
        } catch (ShopPageNotFoundException absent) {
            return notFound(text);
        }
        return respond(sheet.body(), sheet.etag(), MediaType.TEXT_HTML,
                CacheControl.maxAge(POSTER_MAX_AGE).cachePublic(), text, request);
    }

    private Sheet render(String slug, ShopPageText text, Paper paper) {
        return Sheet.of(ShopPosterHtml.render(pages.read(slug), text, paper, baseUrl)
                .getBytes(StandardCharsets.UTF_8));
    }

    /**
     * The sheet of table cards: one per table, cut along the dotted lines.
     *
     * <p>{@code ?t=7} reprints that one card instead, which is what a merchant needs when one gets
     * peeled off; the card it draws is the card the whole sheet drew, because
     * {@link ShopTableCardsHtml#card} is the only thing that writes one and it is given nothing
     * that varies with when it was asked for. {@code ?lang} and {@code Accept-Language} choose the
     * direction and which of the two printed lines comes first — both are always printed.
     *
     * <p>A shop with no tables, and a table past the number the shop says it has, are the same 404
     * as a shop nobody may see. The count is a thing the merchant declared
     * ({@code PUT /api/stores/{id}/tables}), and a card for table 30 in a room with twelve is a
     * card that would be stuck to nothing.
     */
    @GetMapping("/s/{slug}/tables")
    public ResponseEntity<byte[]> tables(@PathVariable String slug,
                                         @RequestParam(name = ShopTableCodes.PARAM,
                                                 required = false) Integer table,
                                         @RequestParam(name = "lang", required = false) String lang,
                                         @RequestHeader(name = HttpHeaders.ACCEPT_LANGUAGE,
                                                 required = false) String acceptLanguage,
                                         HttpServletRequest request) {
        ShopPageText text = ShopPageText.choose(lang, acceptLanguage);
        short seats = pages.tablesOf(slug);
        if (seats < 1 || (table != null && (table < 1 || table > seats))) {
            return notFound(text);
        }
        Sheet sheet;
        try {
            sheet = tableSheets.get(slug + "\n" + text.tag() + "\n" + (table == null ? "*" : table),
                    () -> Sheet.of(ShopTableCardsHtml
                            .render(pages.read(slug), text, table, baseUrl)
                            .getBytes(StandardCharsets.UTF_8)));
        } catch (ShopPageNotFoundException absent) {
            // The count said the shop was visible a moment ago; a suspension between the two reads
            // lands here, and gets the answer everything else under /s/** gives.
            return notFound(text);
        }
        return respond(sheet.body(), sheet.etag(), MediaType.TEXT_HTML,
                CacheControl.maxAge(POSTER_MAX_AGE).cachePublic(), text, request);
    }

    /** The card sheet's layout. Same origin, so its own {@code style-src 'self'} allows it. */
    @GetMapping("/s/assets/tables.css")
    public ResponseEntity<byte[]> stylesheetTables(HttpServletRequest request) {
        return asset(stylesheetTables, request);
    }

    /** The poster's layout. Same origin, so its own {@code style-src 'self'} allows it. */
    @GetMapping("/s/assets/poster.css")
    public ResponseEntity<byte[]> stylesheet(HttpServletRequest request) {
        return asset(stylesheet, request);
    }

    /** What the A4 copy lays over the top: the paper, and the scale that goes with it. */
    @GetMapping("/s/assets/poster-a4.css")
    public ResponseEntity<byte[]> stylesheetA4(HttpServletRequest request) {
        return asset(stylesheetA4, request);
    }

    // ---------------------------------------------------------------- responses

    /**
     * The same refusal the page gives, written by the same method.
     *
     * <p>Not "no poster for this shop" — a distinct refusal here would answer "does this shop
     * exist" for anybody who could not get the page to answer it. A draft shop, a suspended shop, a
     * shop with no pin and a slug nobody has ever had are one answer with one status and one set of
     * headers.
     *
     * <p>The app is what explains the difference, and it has the right to: it is talking to the
     * merchant who owns the shop, so it says "place your shop on the map" instead of showing a QR
     * code that leads nowhere. This surface is anonymous and says nothing.
     */
    private ResponseEntity<byte[]> notFound(ShopPageText text) {
        byte[] body = ShopPageHtml.renderNotFound(text, baseUrl, ShopPageHtml.Assets.none()).getBytes(StandardCharsets.UTF_8);
        return secured(ResponseEntity.status(HttpStatus.NOT_FOUND))
                .cacheControl(CacheControl.maxAge(Duration.ofMinutes(1)).cachePublic())
                .header("X-Robots-Tag", "noindex")
                .header(HttpHeaders.VARY, HttpHeaders.ACCEPT_LANGUAGE)
                .contentType(MediaType.TEXT_HTML)
                .body(body);
    }

    /** A stylesheet: this build's bytes, so a year and immutable is the truth. */
    private ResponseEntity<byte[]> asset(byte[] body, HttpServletRequest request) {
        return respond(body, strongTag(body), MediaType.valueOf("text/css;charset=UTF-8"),
                CacheControl.maxAge(ASSET_MAX_AGE).cachePublic().immutable(), null, request);
    }

    /**
     * One cacheable, revalidatable response.
     *
     * <p>The ETag is the content, so a reload after a rename is answered with the new sheet and a
     * reload after nothing is answered 304 with no body at all.
     */
    private ResponseEntity<byte[]> respond(byte[] body, String tag, MediaType type,
                                           CacheControl cache, ShopPageText text,
                                           HttpServletRequest request) {
        boolean unchanged = conditional(request, tag);
        ResponseEntity.BodyBuilder response = secured(unchanged
                ? ResponseEntity.status(HttpStatus.NOT_MODIFIED)
                : ResponseEntity.ok())
                .cacheControl(cache)
                .eTag(tag);
        if (text != null) {
            // One URL, two renderings. Without Vary a shared cache would hand whichever it stored
            // first to everybody after it.
            response = response.header(HttpHeaders.CONTENT_LANGUAGE, text.tag())
                    .header(HttpHeaders.VARY, HttpHeaders.ACCEPT_LANGUAGE);
        }
        return unchanged ? response.build() : response.contentType(type).body(body);
    }

    /** The headers every response here carries, whatever its status. */
    private static ResponseEntity.BodyBuilder secured(ResponseEntity.BodyBuilder builder) {
        return builder
                .header("Content-Security-Policy", CONTENT_SECURITY_POLICY)
                .header("X-Content-Type-Options", "nosniff")
                .header("X-Frame-Options", "DENY")
                .header("Referrer-Policy", "strict-origin-when-cross-origin");
    }

    private static boolean conditional(HttpServletRequest request, String tag) {
        String sent = request.getHeader(HttpHeaders.IF_NONE_MATCH);
        if (sent == null) {
            return false;
        }
        for (String candidate : sent.split(",")) {
            String trimmed = candidate.trim();
            // A shared cache is allowed to weaken a tag it stored.
            if (trimmed.startsWith("W/")) {
                trimmed = trimmed.substring(2);
            }
            if (trimmed.equals(tag) || "*".equals(trimmed)) {
                return true;
            }
        }
        return false;
    }

    /** A strong ETag over the exact bytes sent. Content-addressed, so it cannot go stale. */
    private static String strongTag(byte[] body) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(body);
            return "\"" + Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(Arrays.copyOf(digest, 16)) + "\"";
        } catch (NoSuchAlgorithmException impossible) {
            return "\"" + HexFormat.of().toHexDigits(Arrays.hashCode(body)) + "\"";
        }
    }

    private static String trimTrailingSlash(String url) {
        String trimmed = url == null ? "" : url.trim();
        while (trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        return trimmed;
    }

    private static byte[] read(String resource) {
        try (var in = new ClassPathResource(resource).getInputStream()) {
            return StreamUtils.copyToByteArray(in);
        } catch (IOException e) {
            // Packaged in the jar beside this class. Missing means a broken build, and a service
            // that started without it would print every poster unstyled onto whatever paper the
            // printer guessed.
            throw new UncheckedIOException(resource + " is missing from the build", e);
        }
    }

    /** Bytes and the ETag for exactly those bytes, so a memoised sheet carries its own tag. */
    private record Sheet(byte[] body, String etag) {

        static Sheet of(byte[] body) {
            return new Sheet(body, strongTag(body));
        }
    }
}

package com.delivery.product.shoppage;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
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

/**
 * The public, anonymous, server-rendered pages: a shop's own page, its QR code, and the sitemap.
 *
 * <p>Outside {@code /api/**} on purpose. This is not an API — it is a document a person opens, a
 * chat app previews and a crawler indexes — and the one address a shopkeeper prints on a sign
 * should be {@code /s/the-shop}, not an endpoint path with a version in it.
 *
 * <p>Everything here is reachable with no token ({@code delivery.security.permit-all}) and is
 * rate-limited at the edge like the rest of the public surface. Nothing here reads the caller:
 * there is no {@code CurrentUser}, so a page cannot accidentally become personalised and cannot be
 * cached for one reader and served to another.
 */
@RestController
public class PublicShopPageController {

    /**
     * How long a page may be reused before it is re-fetched.
     *
     * <p>Five minutes. A merchant who corrects a price wants to see it on the shared link soon,
     * and a chat app that previews a link a hundred times in an hour should not ask a hundred
     * times. The ETag makes the re-check free when nothing changed.
     */
    private static final Duration PAGE_MAX_AGE = Duration.ofMinutes(5);

    /**
     * The QR code and the stylesheet: a year, and immutable.
     *
     * <p>Both are pure functions of an address that never moves — the slug is fixed at creation and
     * survives a rename ({@code Store.updateProfile}), and the stylesheet is served from this
     * build. A printed sign scanned next summer resolves the same URL.
     */
    private static final Duration ASSET_MAX_AGE = Duration.ofDays(365);

    /** The sitemap: an hour. A new shop is worth finding today, not within five minutes. */
    private static final Duration SITEMAP_MAX_AGE = Duration.ofHours(1);

    /**
     * How long a rendered QR code is kept, and how many.
     *
     * <p>The image cannot go stale — it is a pure function of a slug a shop keeps for life, which
     * is why the response says immutable for a year. The entry expires only so that a shop nobody
     * has asked about since yesterday stops holding a kilobyte, and the count is bounded because
     * this pod has 512 MiB. Every code is about 1.5 kB, so this is under a megabyte held.
     */
    private static final Duration QR_MEMO_FOR = Duration.ofDays(1);

    private static final int QR_MEMO_ENTRIES = 512;

    /**
     * How many rendered pages are held.
     *
     * <p>A page is about 18 kB, so this is a few megabytes on a pod with 512 MiB — enough for every
     * shop on the platform twice over, once per language, and bounded so that a script asking for
     * slugs that do not exist cannot grow it (a refusal is never stored).
     */
    private static final int PAGE_MEMO_ENTRIES = 256;

    private final PublicShopPageService pages;

    /**
     * The QR codes this service has already drawn, by slug.
     *
     * <p>Encoding one is a million pixel writes into a 1,024² bitmap and a PNG encode, and it is
     * the same million every time: a printed sign is scanned, the phone opens the page, the page
     * offers "QR code to print" again, and a shop that prints a batch of cards asks for the same
     * image all afternoon. Drawing it once per slug is the whole of this.
     */
    private final ShopPageCache<byte[]> qrCodes;

    /**
     * The pages already rendered, by slug and language.
     *
     * <p>This is the origin's protection, and the page's traffic is the reason it needs one: a link
     * in a WhatsApp status is opened by everyone in the group inside a minute, previewed by every
     * chat app that draws a card for it, and walked by crawlers — and each of those cost six
     * queries, a hundred and twenty products and a full render, for an answer that is the same for
     * all of them. Nothing here reads the caller, so there is no page that is right for one reader
     * and wrong for the next.
     *
     * <p>Held for the {@link #PAGE_MAX_AGE} the response already advertises, so this promises
     * nothing new: a merchant who corrects a price sees it within the five minutes they were
     * already told about, whether the copy they are looking at came from here, from a CDN or from
     * their own phone.
     */
    private final ShopPageCache<Document> renderedPages;

    /**
     * The manifests already built, by slug and language.
     *
     * <p>Held for the same five minutes as the page, and for the same reason: a browser fetches it
     * on every page load, it is built from the same read, and it is the same few hundred bytes for
     * everybody. The bound is smaller than the page memo's because a manifest is a twentieth of
     * the size and is asked for once per reader rather than once per link in a group chat.
     */
    private final ShopPageCache<Document> manifests;

    /**
     * The sitemap, under one key.
     *
     * <p>A cache of one, because there is one sitemap — the map is here so that the hour, the bound
     * and the single-flight rebuild are the same code as everything else on this page, rather than
     * a second, slightly different piece of caching written out by hand.
     */
    private final ShopPageCache<Document> sitemaps;

    /**
     * The address this page believes it lives at.
     *
     * <p>Configuration rather than the request's {@code Host}, and that is the point: the canonical
     * link, the Open Graph URL and the bytes inside the QR code must all name the one public
     * address of the shop, whichever router or internal name the request happened to arrive on. A
     * page that took its own hostname from the request would mint a second, indexable copy of every
     * shop the moment somebody reached it another way.
     */
    private final String baseUrl;

    /** The stylesheet, read once: it ships with the build and never changes while this JVM runs. */
    private final byte[] stylesheet;

    /** The one script, read once, for the same reason and on the same terms. */
    private final byte[] script;

    /**
     * The two asset URLs every rendering points at, fingerprinted by the bytes behind them.
     *
     * <p>Computed once from the files this build shipped. Both are served {@code immutable} for a
     * year, so the address has to move when the bytes do — see {@link ShopPageHtml.Assets}.
     */
    private final ShopPageHtml.Assets assets;

    /**
     * What the page's own Content-Security-Policy allows.
     *
     * <p>Exactly four things: the stylesheet, the catalogue filter and the shop's manifest from
     * this origin, and pictures from the object store the URLs in the markup actually point at.
     * Everything else — font, frame, form, connect — is {@code 'none'}, because the page uses none
     * of them and a policy that allowed what it did not use would be a hole nobody was watching.
     *
     * <p>{@code script-src 'self'} and no {@code 'unsafe-inline'}: the page's one script is a file
     * this service serves, so the policy never has to allow a block of markup to run. The
     * structured data at the end of the body is a {@code <script>} element too, but it carries a
     * JSON media type — a browser parses it as data and never executes it, which is why it needs
     * nothing from this policy and why opening the policy up for it would have been the wrong way
     * to ship it.
     *
     * <p>Built from {@code delivery.storage.minio.public-endpoint}, which is the very setting that
     * produced those image URLs ({@code StorageService.readUrl}), so the policy cannot drift from
     * the markup: move the object store and both move together.
     *
     * <p>Sent by the service rather than written into a Traefik middleware for the same reason. A
     * policy in YAML is a string nothing can test; this one is asserted by
     * {@code PublicShopPageApiTest.carriesItsOwnContentSecurityPolicy} against the page it actually
     * protects.
     */
    private final String contentSecurityPolicy;

    @Autowired
    public PublicShopPageController(
            PublicShopPageService pages,
            @Value("${delivery.public.base-url:https://www.youdrop.shop}") String baseUrl,
            @Value("${delivery.storage.minio.public-endpoint:}") String imageOrigin) {
        this(pages, baseUrl, imageOrigin, System::nanoTime);
    }

    /** The clock the memos age on, injectable so a test can step over an expiry. */
    PublicShopPageController(PublicShopPageService pages, String baseUrl, String imageOrigin,
                             LongSupplier nanoClock) {
        this.pages = pages;
        this.baseUrl = trimTrailingSlash(baseUrl);
        this.stylesheet = readAsset("shoppage/shop.css");
        this.script = readAsset("shoppage/shop.js");
        this.assets = new ShopPageHtml.Assets(
                ShopPageHtml.STYLESHEET + "?v=" + fingerprint(stylesheet),
                ShopPageHtml.SCRIPT + "?v=" + fingerprint(script));
        this.contentSecurityPolicy = policyFor(imageOrigin);
        this.qrCodes = new ShopPageCache<>(QR_MEMO_FOR, QR_MEMO_ENTRIES, nanoClock);
        this.renderedPages = new ShopPageCache<>(PAGE_MAX_AGE, PAGE_MEMO_ENTRIES, nanoClock);
        this.manifests = new ShopPageCache<>(PAGE_MAX_AGE, PAGE_MEMO_ENTRIES, nanoClock);
        this.sitemaps = new ShopPageCache<>(SITEMAP_MAX_AGE, 1, nanoClock);
    }

    // ---------------------------------------------------------------- the page

    /**
     * A shop's page.
     *
     * <p>{@code lang} wins over {@code Accept-Language}, and {@code Vary: Accept-Language} is what
     * stops a shared cache handing an Arabic rendering to the next reader who asked for English.
     */
    @GetMapping("/s/{slug}")
    public ResponseEntity<byte[]> page(@PathVariable String slug,
                                       @RequestParam(name = "lang", required = false) String lang,
                                       @RequestHeader(name = HttpHeaders.ACCEPT_LANGUAGE,
                                               required = false) String acceptLanguage,
                                       HttpServletRequest request) {
        ShopPageText text = ShopPageText.choose(lang, acceptLanguage);
        Document page;
        try {
            // One rendering per shop per language per window. The slug cannot contain a newline —
            // it is lower-case letters, digits and hyphens — so the two parts cannot run together.
            page = renderedPages.get(slug + "\n" + text.tag(), () -> render(slug, text));
        } catch (ShopPageNotFoundException absent) {
            return notFound(text);
        }
        return document(page, MediaType.TEXT_HTML,
                CacheControl.maxAge(PAGE_MAX_AGE).cachePublic(), text, request);
    }

    private Document render(String slug, ShopPageText text) {
        return Document.of(ShopPageHtml
                .render(pages.read(slug), text, baseUrl, pages.lbpPerUsd(), assets)
                .getBytes(StandardCharsets.UTF_8));
    }

    /**
     * The QR code of the page's own URL.
     *
     * <p>Refused for a shop nobody may see — a QR that outlived its shop is a sign on a counter
     * pointing at a 404 — but by asking whether the shop exists, which is one indexed lookup, and
     * not by building the page. Reading the page here cost six queries and up to a hundred and
     * twenty products, all of it thrown away, to decide whether to draw a square; and then the
     * square was drawn from scratch as well, a million pixel writes at a time, for an image that
     * cannot change. The existence check still runs on every request, so a shop suspended this
     * morning stops having a printable code this morning; only the pixels are remembered.
     */
    @GetMapping("/s/{slug}/qr.png")
    public ResponseEntity<byte[]> qr(@PathVariable String slug,
                                     @RequestParam(name = "lang", required = false) String lang,
                                     @RequestHeader(name = HttpHeaders.ACCEPT_LANGUAGE,
                                             required = false) String acceptLanguage,
                                     HttpServletRequest request) {
        if (!pages.exists(slug)) {
            return notFound(ShopPageText.choose(lang, acceptLanguage));
        }
        // The un-suffixed page URL, not this request's: what the sign points at is the page, in
        // whichever language the phone that scans it prefers.
        byte[] png = qrCodes.get(slug, () -> ShopQrCode.pngOf(baseUrl + "/s/" + slug));
        return asset(png, MediaType.IMAGE_PNG, request);
    }

    /**
     * The shop's web manifest, so a regular can keep it on a home screen.
     *
     * <p>Under the shop's own address rather than a shared file with a query string, because a
     * manifest's scope and {@code start_url} are this one shop's page and a browser keys what it
     * installed by the manifest's URL.
     *
     * <p>Refused for a shop nobody may see, by the same rule and with the same page as everything
     * else here: a manifest that outlived its shop is an icon on somebody's home screen pointing
     * at a 404.
     */
    @GetMapping("/s/{slug}" + ShopPageManifest.PATH)
    public ResponseEntity<byte[]> manifest(@PathVariable String slug,
                                           @RequestParam(name = "lang", required = false)
                                           String lang,
                                           @RequestHeader(name = HttpHeaders.ACCEPT_LANGUAGE,
                                                   required = false) String acceptLanguage,
                                           HttpServletRequest request) {
        ShopPageText text = ShopPageText.choose(lang, acceptLanguage);
        Document manifest;
        try {
            manifest = manifests.get(slug + "\n" + text.tag(), () -> renderManifest(slug, text));
        } catch (ShopPageNotFoundException absent) {
            return notFound(text);
        }
        return document(manifest, MediaType.valueOf("application/manifest+json"),
                CacheControl.maxAge(PAGE_MAX_AGE).cachePublic(), text, request);
    }

    private Document renderManifest(String slug, ShopPageText text) {
        PublicShopPage page = pages.read(slug);
        return Document.of(ShopPageManifest
                .render(page, text, baseUrl + "/s/" + slug, ShopPageHtml.describe(page, text))
                .getBytes(StandardCharsets.UTF_8));
    }

    /** The page's one stylesheet. Same origin, so the site's {@code style-src 'self'} allows it. */
    @GetMapping("/s/assets/shop.css")
    public ResponseEntity<byte[]> stylesheet(HttpServletRequest request) {
        return asset(stylesheet, MediaType.valueOf("text/css;charset=UTF-8"), request);
    }

    /**
     * The page's one script: the catalogue filter, and nothing else.
     *
     * <p>A file from this origin rather than a block in the markup, because the policy this
     * service sends is {@code script-src 'self'} with no {@code 'unsafe-inline'} — and because a
     * script that is its own request is cached for a year across every shop page a reader opens,
     * while an inline one is re-sent with every one of them.
     */
    @GetMapping("/s/assets/shop.js")
    public ResponseEntity<byte[]> script(HttpServletRequest request) {
        return asset(script, MediaType.valueOf("text/javascript;charset=UTF-8"), request);
    }

    /**
     * Every shop page there is, for the crawlers.
     *
     * <p>Only shops that would actually render: a sitemap of addresses that answer 404 teaches a
     * search engine to distrust the file. No {@code lastmod}: {@code stores.updated_at} moves when
     * a merchant edits anything at all, including things this page does not draw, so it would claim
     * a change the crawler could not find and would be worse than saying nothing.
     *
     * <p>Built once an hour, which is what the response has always told crawlers. It is the widest
     * read this service has — every shop there is — and several crawlers fetching it within the
     * same hour is the normal case, not the exception.
     */
    @GetMapping("/sitemap.xml")
    public ResponseEntity<byte[]> sitemap(HttpServletRequest request) {
        Document sitemap = sitemaps.get("sitemap", this::renderSitemap);
        return respond(sitemap.body(), sitemap.etag(), MediaType.APPLICATION_XML,
                CacheControl.maxAge(SITEMAP_MAX_AGE).cachePublic(), null, request);
    }

    private Document renderSitemap() {
        List<String> slugs = pages.listedSlugs();
        StringBuilder xml = new StringBuilder(128 + slugs.size() * 96);
        xml.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
                .append("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\" ")
                .append("xmlns:xhtml=\"http://www.w3.org/1999/xhtml\">");
        for (String slug : slugs) {
            String url = baseUrl + "/s/" + slug;
            xml.append("<url><loc>").append(ShopPageHtml.esc(url)).append("</loc>")
                    // The two renderings of the one page, declared as alternates rather than as
                    // separate <url> entries: they are one document, and listing both would ask to
                    // have the same shop indexed twice.
                    .append("<xhtml:link rel=\"alternate\" hreflang=\"en\" href=\"")
                    .append(ShopPageHtml.esc(url)).append("?lang=en\"/>")
                    .append("<xhtml:link rel=\"alternate\" hreflang=\"ar\" href=\"")
                    .append(ShopPageHtml.esc(url)).append("?lang=ar\"/>")
                    .append("</url>");
        }
        xml.append("</urlset>");

        return Document.of(xml.toString().getBytes(StandardCharsets.UTF_8));
    }

    // ---------------------------------------------------------------- responses

    /**
     * The one refusal.
     *
     * <p>A draft shop, a suspended shop, a shop with no pin, a service shop in a closed category and
     * a slug nobody has ever had all arrive here with nothing but the reader's language, so the four
     * answers are the same bytes with the same status and the same headers. There is no ETag and no
     * {@code Content-Language}: two 404s that differed in a header would be as good as an answer.
     *
     * <p>Cached for a minute, publicly. Long enough that a crawler walking a stale list does not
     * hammer the service, short enough that a shop that goes live this afternoon is not missing all
     * evening.
     */
    private ResponseEntity<byte[]> notFound(ShopPageText text) {
        byte[] body = ShopPageHtml.renderNotFound(text, baseUrl, assets)
                .getBytes(StandardCharsets.UTF_8);
        return secured(ResponseEntity.status(HttpStatus.NOT_FOUND))
                .cacheControl(CacheControl.maxAge(Duration.ofMinutes(1)).cachePublic())
                .header("X-Robots-Tag", "noindex")
                // Two renderings of this page too, so a shared cache must not hand an Arabic
                // refusal to an English reader. It says nothing about which shop was asked for:
                // all four refusals carry it.
                .header(HttpHeaders.VARY, HttpHeaders.ACCEPT_LANGUAGE)
                .contentType(MediaType.TEXT_HTML)
                .body(body);
    }

    /** A document a reader sees: cached briefly, revalidated with an ETag, language-aware. */
    private ResponseEntity<byte[]> document(Document document, MediaType type, CacheControl cache,
                                            ShopPageText text, HttpServletRequest request) {
        return respond(document.body(), document.etag(), type, cache, text, request);
    }

    /** An immutable byte-for-byte asset: the QR code and the stylesheet. */
    private ResponseEntity<byte[]> asset(byte[] body, MediaType type, HttpServletRequest request) {
        return respond(body, strongTag(body), type,
                CacheControl.maxAge(ASSET_MAX_AGE).cachePublic().immutable(), null, request);
    }

    /**
     * One cacheable, revalidatable response, for every one of these documents.
     *
     * <p>The ETag is the content, so "has this changed" is answered without the merchant, the
     * database or this method knowing what changed. A matching {@code If-None-Match} is answered
     * 304 with the caching headers and no body — a phone that already has the page spends a few
     * hundred bytes finding out it is still current.
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
    private ResponseEntity.BodyBuilder secured(ResponseEntity.BodyBuilder builder) {
        return builder
                .header("Content-Security-Policy", contentSecurityPolicy)
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
            // A shared cache is allowed to weaken a tag it stored. Two renderings that differ only
            // by that prefix are the same bytes, so honour it.
            if (trimmed.startsWith("W/")) {
                trimmed = trimmed.substring(2);
            }
            if (trimmed.equals(tag) || "*".equals(trimmed)) {
                return true;
            }
        }
        return false;
    }

    /**
     * The short content fingerprint an asset's URL carries.
     *
     * <p>The same digest the ETag is made of, so the two can never disagree about whether a file
     * changed. Ten characters of it: this only has to separate one build's stylesheet from the
     * next's, not resist anybody.
     */
    private static String fingerprint(byte[] body) {
        return strongTag(body).replace("\"", "").substring(0, 10);
    }

    /** A strong ETag over the exact bytes sent. Content-addressed, so it cannot go stale. */
    private static String strongTag(byte[] body) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(body);
            return "\"" + Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(java.util.Arrays.copyOf(digest, 16)) + "\"";
        } catch (NoSuchAlgorithmException impossible) {
            // Every JVM ships SHA-256; HexFormat is here only so the fallback is not a silent one.
            return "\"" + HexFormat.of().toHexDigits(java.util.Arrays.hashCode(body)) + "\"";
        }
    }

    /**
     * {@code default-src 'none'} and then exactly what the page uses.
     *
     * <p>{@code img-src} names the object store's public origin because that is where the markup's
     * picture URLs point; when it is not configured the policy simply does not name it, which
     * blocks pictures rather than opening the policy up to guesswork.
     */
    private static String policyFor(String imageOrigin) {
        String origin = originOf(imageOrigin);
        return "default-src 'none'; "
                + "img-src 'self'" + (origin == null ? "" : " " + origin) + "; "
                + "style-src 'self'; "
                + "script-src 'self'; "
                // Exactly this service's own manifest, and nothing else: default-src 'none' would
                // block it outright, and the only alternative to naming it was not shipping it.
                + "manifest-src 'self'; "
                + "base-uri 'none'; "
                + "form-action 'none'; "
                + "frame-ancestors 'none'";
    }

    /** scheme://host[:port] of a configured endpoint, or null when it is not a usable URL. */
    private static String originOf(String endpoint) {
        if (endpoint == null || endpoint.isBlank()) {
            return null;
        }
        try {
            URI uri = new URI(endpoint.trim());
            if (uri.getScheme() == null || uri.getHost() == null) {
                return null;
            }
            return uri.getPort() < 0
                    ? uri.getScheme() + "://" + uri.getHost()
                    : uri.getScheme() + "://" + uri.getHost() + ":" + uri.getPort();
        } catch (URISyntaxException notAUrl) {
            return null;
        }
    }

    private static String trimTrailingSlash(String url) {
        String trimmed = url == null ? "" : url.trim();
        while (trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length() - 1);
        }
        return trimmed;
    }

    private static byte[] readAsset(String path) {
        try (var in = new ClassPathResource(path).getInputStream()) {
            return StreamUtils.copyToByteArray(in);
        } catch (IOException e) {
            // They are packaged in the jar beside this class. Missing means a broken build, and a
            // service that started without one would serve every shop page unstyled, or with a
            // search box that never appears.
            throw new UncheckedIOException(path + " is missing from the build", e);
        }
    }

    /**
     * Bytes and the ETag for exactly those bytes, kept together.
     *
     * <p>So that a memoised page carries its own tag rather than being re-digested on every hit,
     * and so that the two can never be told apart: the tag is derived here, once, from the body it
     * will be sent with.
     */
    private record Document(byte[] body, String etag) {

        static Document of(byte[] body) {
            return new Document(body, strongTag(body));
        }
    }
}

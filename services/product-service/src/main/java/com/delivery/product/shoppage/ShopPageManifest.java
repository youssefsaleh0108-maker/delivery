package com.delivery.product.shoppage;

/**
 * The few hundred bytes that let a customer keep a shop on their home screen.
 *
 * <p>A regular is not going to search for the same dekkane every week, and this page is the only
 * address they have for it. Without a manifest, "add to home screen" gives them the page's title
 * and whatever icon the browser can scrape; with one, it gives them the shop's own name and the
 * shop's own logo, which is the difference between a shortcut they recognise and one they delete.
 *
 * <p><strong>{@code minimal-ui}, not {@code standalone}.</strong> A page that opened chromeless,
 * with no address bar, would be presenting itself as the shop's app — and this page cannot take an
 * order, has no account and is five minutes stale by design. Keeping the address bar is the honest
 * shape for a document somebody chose to keep.
 *
 * <p>It carries nothing the page does not: the shop's name, the sentence already in the meta
 * description, the logo already drawn in the header, and the platform's two colours. The one thing
 * it needs from the page's Content-Security-Policy is {@code manifest-src 'self'}, which permits
 * exactly this file from exactly this origin and nothing else — {@code default-src 'none'} would
 * otherwise block it, and a manifest is not worth loosening anything for.
 */
final class ShopPageManifest {

    private ShopPageManifest() {
    }

    /** The platform's own two, lifted from the stylesheet so the two cannot drift apart. */
    static final String THEME = "#E11D48";
    static final String BACKGROUND = "#F8FAFC";

    /** Where a shop's manifest lives, relative to its page. */
    static final String PATH = "/manifest.webmanifest";

    /**
     * @param url the shop's canonical page URL, which is the scope and the start of this
     *            "application": tapping the icon opens the page, in the language the reader chose
     *            when they kept it
     */
    static String render(PublicShopPage page, ShopPageText t, String url, String description) {
        StringBuilder b = new StringBuilder(512);
        b.append("{\"name\":\"").append(json(page.name())).append('"')
                .append(",\"description\":\"").append(json(description)).append('"')
                // A manifest has its own language and direction: the name inside it is drawn by
                // the launcher, outside any page that could have set them.
                .append(",\"lang\":\"").append(t.tag()).append('"')
                .append(",\"dir\":\"").append(t.dir()).append('"')
                .append(",\"id\":\"").append(json(url)).append('"')
                .append(",\"scope\":\"").append(json(url)).append('"')
                .append(",\"start_url\":\"").append(json(url)).append("?lang=").append(t.tag())
                .append('"')
                .append(",\"display\":\"minimal-ui\"")
                .append(",\"theme_color\":\"").append(THEME).append('"')
                .append(",\"background_color\":\"").append(BACKGROUND).append('"');
        if (page.logoUrl() != null) {
            // "any" rather than a pixel size: the derivative is 320 px on its long edge and keeps
            // the logo's own shape, so there is no square this file could honestly name. A shop
            // that never uploaded a logo declares no icon at all, which lets the browser fall back
            // to what it would have done anyway rather than to a broken image.
            b.append(",\"icons\":[{\"src\":\"").append(json(page.logoUrl()))
                    .append("\",\"sizes\":\"any\"}]");
        }
        return b.append('}').toString();
    }

    private static String json(String raw) {
        return ShopPageHtml.json(raw);
    }
}

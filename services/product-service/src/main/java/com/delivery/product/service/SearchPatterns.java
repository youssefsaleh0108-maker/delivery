package com.delivery.product.service;

/**
 * Turns an optional search term into a LIKE pattern.
 *
 * <p>Extracted rather than duplicated per service because the two rules it encodes are easy to get
 * subtly wrong in only one copy:
 *
 * <ul>
 *   <li>The result is <strong>never null</strong>. A null String bound inside {@code LOWER()} has no
 *       inferable type, so the driver sends it as {@code bytea} and Postgres fails the whole query
 *       with "function lower(bytea) does not exist". An unfiltered search is {@code %}, not null.
 *   <li>Wildcards in user input are escaped, so a search for "50%" matches the literal text rather
 *       than everything. Queries using this must declare {@code ESCAPE '\'}.
 * </ul>
 */
public final class SearchPatterns {

    private SearchPatterns() {
    }

    public static String like(String search) {
        if (search == null || search.isBlank()) {
            return "%";
        }
        String escaped = search.toLowerCase()
                .replace("\\", "\\\\")
                .replace("%", "\\%")
                .replace("_", "\\_");
        return "%" + escaped + "%";
    }
}

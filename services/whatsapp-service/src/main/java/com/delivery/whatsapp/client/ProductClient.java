package com.delivery.whatsapp.client;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import com.delivery.platform.security.CurrentUser;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Looks up a product so a draft line can name it and show a price.
 *
 * <p>The merchant's own bearer token is forwarded, which is what makes the catalog's own ownership
 * rules apply: a merchant browsing for something to add to a draft sees exactly what they would see
 * anywhere else.
 *
 * <p>What this price is <em>not</em>: what the customer will pay. The catalog prices the real order
 * at the moment it is placed. This is a number the merchant reads back to the customer, and treating
 * it as authoritative is how a draft built this morning charges yesterday's price.
 */
public class ProductClient {

    private static final Logger log = LoggerFactory.getLogger(ProductClient.class);

    private final RestClient restClient;

    public ProductClient(RestClient restClient) {
        this.restClient = restClient;
    }

    /**
     * What a draft line needs: something to call it, and something to add up.
     *
     * <p>A narrow view of the catalog's own response — images, descriptions and timestamps are all
     * there and all irrelevant here. Unknown fields are ignored, so the catalog can grow its
     * response without breaking this.
     */
    public record CatalogProduct(UUID id, String merchantId, UUID storeId, String name,
                                 BigDecimal price, String status) {

        /** Whether a merchant may sell it. The catalog's own word, not a guess made here. */
        public boolean isSellable() {
            return "ACTIVE".equalsIgnoreCase(status);
        }
    }

    /**
     * A selection priced by the catalog.
     *
     * @param basePrice the product's own price, before options
     * @param unitPrice what one of them costs with the options chosen — the number that matters
     * @param options   the chosen options with their names, so the draft can be read back in words
     */
    public record PricedLine(BigDecimal basePrice, BigDecimal unitPrice,
                             List<ChosenOption> options) {
    }

    public record ChosenOption(String groupName, String optionName, BigDecimal priceDelta) {
    }

    private record PriceRequest(List<UUID> optionIds) {
    }

    /**
     * A product's option groups — what the merchant picks from.
     *
     * <p>Also how a chosen option id becomes a name: {@link PricedLine} carries the names but not
     * the ids, so the two are matched up here to snapshot "Choose Size: Large" against the id that
     * will actually be sent to Order Manager.
     */
    public record OptionGroup(UUID id, String name, int minSelect, int maxSelect, boolean required,
                              boolean singleChoice, List<Option> options) {
    }

    public record Option(UUID id, String name, BigDecimal priceDelta, boolean isDefault,
                         boolean available) {
    }

    /** Thrown when the product does not exist, or the catalog cannot be reached. */
    public static class ProductLookupException extends RuntimeException {
        public ProductLookupException(String message) {
            super(message);
        }
    }

    /**
     * Fatal on failure, unlike most cross-service calls here.
     *
     * <p>A draft line whose product could not be read is a line with no name and no price — there is
     * nothing useful to put in the draft, and adding a blank one would let a merchant confirm an
     * order containing an item nobody can identify.
     */
    public CatalogProduct fetch(UUID productId) {
        String token = CurrentUser.jwt().map(Jwt::getTokenValue).orElse(null);
        if (token == null) {
            throw new ProductLookupException("no credentials to read the catalog with");
        }

        try {
            CatalogProduct product = restClient.get()
                    .uri("/api/products/{id}", productId)
                    .header("Authorization", "Bearer " + token)
                    .retrieve()
                    .body(CatalogProduct.class);
            if (product == null) {
                throw new ProductLookupException("the catalog returned nothing for " + productId);
            }
            return product;
        } catch (RestClientResponseException e) {
            log.warn("Catalog refused a lookup of product {}: {}", productId, e.getStatusCode());
            throw new ProductLookupException("that product could not be found");
        } catch (ProductLookupException e) {
            throw e;
        } catch (Exception e) {
            log.error("Could not reach the catalog for product {}", productId, e);
            throw new ProductLookupException("the catalog could not be reached");
        }
    }

    /**
     * The product's option groups.
     *
     * <p>Fails soft, unlike {@link #fetch}: a product with no groups and a product whose groups
     * could not be read look the same from here, and the second is a display problem rather than a
     * reason to stop the merchant adding a plain item to a draft. The pricing call is what actually
     * enforces the rules, and it does not fail soft.
     */
    public List<OptionGroup> options(UUID productId) {
        String token = CurrentUser.jwt().map(Jwt::getTokenValue).orElse(null);
        if (token == null) {
            return List.of();
        }
        try {
            OptionGroup[] groups = restClient.get()
                    .uri("/api/products/{id}/options", productId)
                    .header("Authorization", "Bearer " + token)
                    .retrieve()
                    .body(OptionGroup[].class);
            return groups == null ? List.of() : List.of(groups);
        } catch (Exception e) {
            log.warn("Could not read options for product {}", productId, e);
            return List.of();
        }
    }

    /**
     * Prices a selection, using the same endpoint the customer app uses.
     *
     * <p>Called when the line is added rather than when the order is placed, so a required group the
     * merchant forgot — {@code "Choose Size" needs a selection} — surfaces while they are still
     * talking to the customer. Discovering it at placement means telling someone their order failed
     * after they were told it was on its way.
     *
     * <p>The catalog's own refusal is carried through verbatim. It names the group that is missing,
     * which is the one thing the merchant needs in order to fix it.
     */
    public PricedLine price(UUID productId, List<UUID> optionIds) {
        String token = CurrentUser.jwt().map(Jwt::getTokenValue).orElse(null);
        if (token == null) {
            throw new ProductLookupException("no credentials to price with");
        }

        try {
            PricedLine priced = restClient.post()
                    .uri("/api/products/{id}/price", productId)
                    .header("Authorization", "Bearer " + token)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(new PriceRequest(optionIds == null ? List.of() : optionIds))
                    .retrieve()
                    .body(PricedLine.class);
            if (priced == null) {
                throw new ProductLookupException("the catalog returned no price");
            }
            return priced;
        } catch (RestClientResponseException e) {
            String reason = detailOf(e.getResponseBodyAsString());
            log.warn("Catalog refused to price product {}: {} {}",
                    productId, e.getStatusCode(), reason);
            throw new ProductLookupException(reason == null ? "that selection is not valid" : reason);
        } catch (ProductLookupException e) {
            throw e;
        } catch (Exception e) {
            log.error("Could not price product {}", productId, e);
            throw new ProductLookupException("the catalog could not be reached");
        }
    }

    /**
     * The {@code detail} out of an RFC 7807 body.
     *
     * <p>Parsed, not pattern-matched: the refusals that matter most here contain quoted group names
     * ({@code "Choose Size" needs a selection}), and a regex that stops at the first quote turns the
     * one useful sentence into a backslash.
     */
    private String detailOf(String body) {
        if (body == null || body.isBlank()) {
            return null;
        }
        try {
            JsonNode detail = MAPPER.readTree(body).path("detail");
            return detail.isTextual() && !detail.asText().isBlank() ? detail.asText() : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static final ObjectMapper MAPPER = new ObjectMapper();
}

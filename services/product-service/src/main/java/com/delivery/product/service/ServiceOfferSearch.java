package com.delivery.product.service;

import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.DeliveredOrderLineRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;

/**
 * The customer's reads of service offers: the Services tab's search, and its "Popular" row.
 *
 * <p>Both list only what a customer may be shown: live offers of listed service shops in open service
 * categories. Never a goods product, a paused offer, or an offer of a draft or suspended shop; the
 * queries pin that ({@link ProductRepository#findListedServiceOffers}). Which categories a read may show
 * is decided here, as {@code StoreService} decides it for shops: every open one, or the one the read
 * names when that one is open, or none. A closed category is never shown, even when asked for by name.
 */
@Service
public class ServiceOfferSearch {

    /** The most offers one "Popular" request may ask for. The row shows a handful. */
    static final int MAX_POPULAR = 20;

    private final ProductRepository products;
    private final DeliveredOrderLineRepository deliveredLines;
    private final ServiceCategories serviceCategories;

    /**
     * How many delivered orders an offer must have been in before "Popular" lists it:
     * {@code delivery.catalog.services.popular-min-delivered-orders}, three unless configured. Never
     * below one, so a misconfigured zero cannot list offers nobody has ever received.
     */
    private final long popularMinDeliveredOrders;

    public ServiceOfferSearch(ProductRepository products, DeliveredOrderLineRepository deliveredLines,
                              ServiceCategories serviceCategories,
                              @Value("${delivery.catalog.services.popular-min-delivered-orders:3}")
                              long popularMinDeliveredOrders) {
        this.products = products;
        this.deliveredLines = deliveredLines;
        this.serviceCategories = serviceCategories;
        this.popularMinDeliveredOrders = Math.max(1, popularMinDeliveredOrders);
    }

    /**
     * Live offers of listed service shops, by name, in the open categories or the open one named.
     *
     * <p>A read that may show no category answers an empty page without asking the database. The id
     * breaks ties in the caller's sort, so a page boundary never repeats one offer and loses another
     * (the reason {@code StoreService} gives for its storefront).
     */
    @Transactional(readOnly = true)
    public Page<Product> search(String search, Store.ServiceCategory serviceCategory,
                                Pageable pageable) {
        Set<Store.ServiceCategory> scope = scope(serviceCategory);
        if (scope.isEmpty()) {
            return Page.empty(pageable);
        }
        return products.findListedServiceOffers(scope, SearchPatterns.like(search),
                tieBroken(pageable));
    }

    /** An offer on the "Popular" row, with the count of delivered orders that put it there. */
    public record PopularOffer(Product product, long deliveredOrders) {
    }

    /**
     * The offers delivered most often, from real delivered orders only, most delivered first.
     *
     * <p>Counted from {@code delivered_order_lines}, the projection of {@code order.delivered}, so an
     * order placed and then cancelled counts for nothing. An offer below the floor is left out rather
     * than padded, and when none reaches it the answer is empty: the app then shows "Services near
     * you" (owner default 16). Nothing here ranks by anything else, or invents a number.
     *
     * <p>The counts are read first and the offers second. An offer paused between the two is dropped
     * rather than listed with a count for something no longer on sale.
     */
    @Transactional(readOnly = true)
    public List<PopularOffer> popular(Store.ServiceCategory serviceCategory, int limit) {
        Set<Store.ServiceCategory> scope = scope(serviceCategory);
        if (scope.isEmpty()) {
            return List.of();
        }
        List<Object[]> counts = deliveredLines.countDeliveredOrdersOfListedServiceOffers(scope,
                popularMinDeliveredOrders, PageRequest.of(0, Math.min(Math.max(limit, 1), MAX_POPULAR)));
        if (counts.isEmpty()) {
            return List.of();
        }
        Map<UUID, Product> byId = products.findByIdIn(counts.stream().map(row -> (UUID) row[0]).toList())
                .stream()
                .collect(Collectors.toMap(Product::getId, Function.identity()));
        return counts.stream()
                .map(row -> {
                    Product product = byId.get((UUID) row[0]);
                    return product == null || product.getStatus() != Product.Status.ACTIVE
                            ? null
                            : new PopularOffer(product, ((Number) row[1]).longValue());
                })
                .filter(Objects::nonNull)
                .toList();
    }

    /** Which categories one read may show: every open one, or the one it names when that is open. */
    Set<Store.ServiceCategory> scope(Store.ServiceCategory named) {
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        if (named == null) {
            return open;
        }
        return open.contains(named) ? Set.of(named) : Set.of();
    }

    private static Pageable tieBroken(Pageable pageable) {
        if (pageable.isUnpaged() || pageable.getSort().getOrderFor("id") != null) {
            return pageable;
        }
        return PageRequest.of(pageable.getPageNumber(), pageable.getPageSize(),
                pageable.getSort().and(Sort.by(Sort.Direction.ASC, "id")));
    }
}

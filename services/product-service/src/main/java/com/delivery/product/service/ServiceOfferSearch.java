package com.delivery.product.service;

import java.util.Set;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.Store;

/**
 * The search of service offers.
 *
 * <p>It lists only what a customer may be shown: live offers of listed service shops in open service
 * categories. Never a goods product, a paused offer, or an offer of a draft or suspended shop; the query
 * pins that ({@link ProductRepository#findListedServiceOffers}). Which categories a read may show is
 * decided here, as {@code StoreService} decides it for shops: every open one, or the one the read names
 * when that one is open, or none. A closed category is never shown, even when asked for by name.
 *
 * <p>The Services tab's "Popular near you" row ranks shops rather than offers, and is
 * {@link PopularServiceShops}.
 */
@Service
public class ServiceOfferSearch {

    private final ProductRepository products;
    private final ServiceCategories serviceCategories;

    public ServiceOfferSearch(ProductRepository products, ServiceCategories serviceCategories) {
        this.products = products;
        this.serviceCategories = serviceCategories;
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

    /** Which categories one read may show: every open one, or the one it names when that is open. */
    Set<Store.ServiceCategory> scope(Store.ServiceCategory named) {
        Set<Store.ServiceCategory> open = serviceCategories.enabled();
        if (named == null) {
            return open;
        }
        return open.contains(named) ? Set.of(named) : Set.of();
    }

    /**
     * The caller's page with the id added as the last sort key, unless it is there already. Shared with
     * back office's offer list ({@code OfferModerationService}), which pages the same rows.
     */
    static Pageable tieBroken(Pageable pageable) {
        if (pageable.isUnpaged() || pageable.getSort().getOrderFor("id") != null) {
            return pageable;
        }
        return PageRequest.of(pageable.getPageNumber(), pageable.getPageSize(),
                pageable.getSort().and(Sort.by(Sort.Direction.ASC, "id")));
    }
}

package com.delivery.product.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ServiceTermsRequest;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductOptionGroup;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.domain.ServiceTerms;
import com.delivery.product.domain.ServiceTermsRepository;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreDeliveryZoneRepository;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.event.CatalogEvents;

/**
 * Catalog reads and writes.
 *
 * <p>Every mutating method takes the caller's id explicitly rather than reaching into the
 * SecurityContext. That makes the ownership rule a visible parameter of the operation instead of
 * ambient state, and it means the rule is testable without a mocked security context.
 *
 * <p>A product in a {@link Store.Vertical#SERVICES} shop is a service offer. It carries
 * {@link ServiceTerms}, which no other product may carry; it can be paused and resumed, which no goods
 * product can; and one that customers can have delivered is published only by a shop with delivery
 * areas or a pin. Each of those rules is decided here, from the shop the product sits in, never from
 * what the request claims.
 *
 * <p>A live offer is shown only while its shop is listed. While a service shop is a draft, is
 * suspended or sits in a closed category, each offer, its options and price, and the shop's shelf are
 * its provider's alone ({@link #read}, {@link #browseStore}), just as its offers are absent from the
 * services search.
 */
@Service
public class CatalogService {

    private static final Logger log = LoggerFactory.getLogger(CatalogService.class);

    private final ProductRepository products;
    private final CategoryRepository categories;
    private final StoreService storeService;
    private final OutboxRecorder outbox;
    private final StoreRepository stores;
    private final ServiceTermsRepository serviceTerms;
    private final StoreDeliveryZoneRepository storeZones;
    private final ProductOptionGroupRepository optionGroups;

    /**
     * Which service categories are open. Consulted only about a service shop, so a mistake in that
     * setting can never hide a goods product.
     */
    private final ServiceCategories serviceCategories;

    public CatalogService(ProductRepository products, CategoryRepository categories,
                          StoreService storeService, OutboxRecorder outbox, StoreRepository stores,
                          ServiceTermsRepository serviceTerms, StoreDeliveryZoneRepository storeZones,
                          ProductOptionGroupRepository optionGroups,
                          ServiceCategories serviceCategories) {
        this.products = products;
        this.categories = categories;
        this.storeService = storeService;
        this.outbox = outbox;
        this.stores = stores;
        this.serviceTerms = serviceTerms;
        this.storeZones = storeZones;
        this.optionGroups = optionGroups;
        this.serviceCategories = serviceCategories;
    }

    /**
     * A product with what its response adds: a service offer's terms and its "From" price.
     *
     * <p>Built by {@link #views(List)} for a whole page at once, inside a transaction, for the reason
     * {@code StoreService.StoreView} gives: the option groups a "From" price counts are read lazily,
     * and nothing lazy may escape to a controller. A goods product carries neither.
     *
     * @param service   the offer's terms, or null for a goods product
     * @param fromPrice the least one pack can cost ({@link #fromPrice}), or null for a goods product
     */
    public record ProductView(Product product, ServiceTerms service, BigDecimal fromPrice) {
    }

    // ---------------------------------------------------------------- reads

    @Transactional(readOnly = true)
    public Page<Product> browseCatalog(UUID categoryId, String search, Pageable pageable) {
        return products.findActiveCatalog(categoryId, SearchPatterns.like(search), pageable);
    }

    /**
     * A store's shelf, as {@code viewerId} may see it. The store landing page's main query.
     *
     * <p>A service shop that is not listed ({@link #hidesItsOffers}) shows its shelf to its provider
     * only, and anybody else is told the shop is not found: each of its offers is not found either
     * ({@link #read}), and a shelf that listed them would undo that. A goods shop's shelf is served as
     * it always was.
     */
    @Transactional(readOnly = true)
    public Page<Product> browseStore(UUID storeId, String viewerId, UUID categoryId, String search,
                                     Pageable pageable) {
        requireShelfShownTo(storeId, viewerId);
        if (search == null || search.isBlank()) {
            return products.findActiveInStore(storeId, categoryId, SearchPatterns.like(search), pageable);
        }
        // A search matches as the customer item search does, so a shop it found for "احمد" or
        // "nescafe" opens onto the same products (ProductRepository#findActiveInStoreMatching). That
        // query orders by how well each product matches, so the page is passed on unsorted.
        return products.findActiveInStoreMatching(storeId, categoryId != null,
                categoryId == null ? storeId : categoryId, search.trim(), SearchPatterns.like(search),
                PageRequest.of(pageable.getPageNumber(), pageable.getPageSize()));
    }

    /**
     * A page of specific products from one store, as {@code viewerId} may see them.
     *
     * <p>Backs Buy Again: it knows the ids it wants from order history, and needs them re-read from
     * the live catalog so the price and description are today's. Store-scoped as well as id-scoped,
     * so a caller cannot use it to read another shop's rows, and refused as {@link #browseStore}
     * refuses the shelf.
     */
    @Transactional(readOnly = true)
    public Page<Product> browseStoreByIds(UUID storeId, String viewerId, java.util.List<UUID> ids,
                                          Pageable pageable) {
        requireShelfShownTo(storeId, viewerId);
        return products.findActiveInStoreByIds(storeId, ids, pageable);
    }

    /**
     * Re-reads a set of products by id, for "Buy Again".
     *
     * <p>Order history stores what was bought at the time; this resolves those ids back to live
     * catalog rows so a repeat order is priced and described as it is today, not as it was. Products
     * that have since been archived simply do not come back, which is the correct outcome — the
     * alternative is offering a customer something the shop no longer sells.
     */
    @Transactional(readOnly = true)
    public java.util.List<Product> readAllActive(java.util.Collection<UUID> ids) {
        if (ids == null || ids.isEmpty()) {
            return java.util.List.of();
        }
        return products.findByIdIn(ids).stream()
                .filter(p -> p.getStatus() == Product.Status.ACTIVE)
                .toList();
    }

    /**
     * The merchant's own products, in any status or in the one asked for, from every shop they own or
     * from the one named.
     *
     * <p>{@code storeId} and {@code status} are how the provider dashboard counts "Active offers": the
     * live offers of its service shop, not of every shop the account owns, which may include a goods
     * shop. Both narrow a list the merchant may already read in full, so they reveal nothing new, and
     * it is never another merchant's list: the merchant comes from the token, and a shop they do not
     * own is "not found", as every store-scoped read and write answers.
     */
    @Transactional(readOnly = true)
    public Page<Product> listOwnedBy(String merchantId, UUID storeId, Product.Status status,
                                     Pageable pageable) {
        if (storeId == null) {
            return status == null
                    ? products.findByMerchantId(merchantId, pageable)
                    : products.findByMerchantIdAndStatus(merchantId, status, pageable);
        }
        requireOwnedStore(merchantId, storeId);
        return status == null
                ? products.findByMerchantIdAndStoreId(merchantId, storeId, pageable)
                : products.findByMerchantIdAndStoreIdAndStatus(merchantId, storeId, status, pageable);
    }

    /**
     * Reads one product for a viewer.
     *
     * <p>A DRAFT, PAUSED or ARCHIVED product is visible only to the merchant that owns it — otherwise
     * a customer could enumerate ids and read unpublished pricing. Order Manager reads a product
     * through here before pricing a line, so a paused offer is also one nobody can order.
     *
     * <p>So is a live offer of a service shop that is not listed ({@link #hidesItsOffers}): a draft or
     * suspended shop, or one in a closed category. The search leaves those offers out, but an id
     * outlives a list (a bookmark, a shared link, a basket built last week), and nothing on Order
     * Manager's side knows a category. This read is therefore where such an offer stops being
     * readable, and with it priceable ({@code ProductController#price}) and orderable. Its provider
     * still reads it. A goods product is read as it always was.
     */
    @Transactional(readOnly = true)
    public Product read(UUID id, String viewerId) {
        Product product = products.findById(id)
                .orElseThrow(() -> new ProductNotFoundException(id));
        if (product.isOwnedBy(viewerId)) {
            return product;
        }
        // Deliberately "not found" rather than "forbidden": a 403 would confirm the id exists.
        if (product.getStatus() != Product.Status.ACTIVE
                || stores.findById(product.getStoreId()).filter(this::hidesItsOffers).isPresent()) {
            throw new ProductNotFoundException(id);
        }
        return product;
    }

    // ---------------------------------------------------------------- views

    /** One product's view. See {@link #views(List)}. */
    @Transactional(readOnly = true)
    public ProductView view(Product product) {
        return views(List.of(product)).get(0);
    }

    /** A page of views, keeping the page's numbering. See {@link #views(List)}. */
    @Transactional(readOnly = true)
    public Page<ProductView> views(Page<Product> page) {
        return new PageImpl<>(views(page.getContent()), page.getPageable(), page.getTotalElements());
    }

    /**
     * Views for a list of products, in the same order.
     *
     * <p>The terms of every service offer among them in one query, and the option groups of those
     * offers in one more. A page of goods costs the first query alone, which finds nothing, and never
     * reads an option.
     */
    @Transactional(readOnly = true)
    public List<ProductView> views(List<Product> page) {
        if (page.isEmpty()) {
            return List.of();
        }
        Map<UUID, ServiceTerms> termsById = new HashMap<>();
        serviceTerms.findAllById(page.stream().map(Product::getId).toList())
                .forEach(terms -> termsById.put(terms.getProductId(), terms));
        Map<UUID, List<ProductOptionGroup>> groupsById = termsById.isEmpty()
                ? Map.of()
                : optionGroups.findByProductIdInOrderByPositionAsc(termsById.keySet()).stream()
                        .collect(Collectors.groupingBy(ProductOptionGroup::getProductId));
        return page.stream()
                .map(product -> {
                    ServiceTerms terms = termsById.get(product.getId());
                    if (terms == null) {
                        return new ProductView(product, null, null);
                    }
                    return new ProductView(product, terms, fromPrice(product.getPrice(),
                            groupsById.getOrDefault(product.getId(), List.of())));
                })
                .toList();
    }

    /**
     * The least one pack of an offer can cost: its price plus the cheapest selection each option group
     * allows ({@link ProductOptionGroup#minimumDelta}), never below zero, because a line never pays the
     * customer ({@code ProductOptionService#price} floors the same sum at zero).
     *
     * <p>Exact: prices and deltas are numeric(12,2), so the sum has two decimals and nothing rounds.
     */
    static BigDecimal fromPrice(BigDecimal price, List<ProductOptionGroup> groups) {
        BigDecimal least = price;
        for (ProductOptionGroup group : groups) {
            least = least.add(group.minimumDelta());
        }
        return least.max(BigDecimal.ZERO).setScale(2, RoundingMode.UNNECESSARY);
    }

    // ---------------------------------------------------------------- writes

    /**
     * Adds a product to one of the merchant's stores.
     *
     * @param firstShop what {@link StoreService#firstShopFor} answered for this request, asked by the
     *                  caller before this transaction began — so a merchant with no shop yet is given
     *                  one, or refused one, without this transaction waiting on Onboarding
     */
    @Transactional
    public Product create(String merchantId, ProductRequest request,
                          StoreService.FirstShop firstShop) {
        // Every product lives in a store. A merchant who has not set one up yet gets one created
        // here rather than a not-null violation, so "add your first product" never needs "but first
        // go and create a store" wired into the client.
        Store store = request.storeId() != null
                ? requireOwnedStore(merchantId, request.storeId())
                : storeService.requireStoreFor(merchantId, firstShop);

        // After the store is known, not before: a shop section is only valid for its own store, and
        // whether this is a service offer is its shop's to say.
        validateCategory(request.categoryId(), store.getId());
        requireTermsMatchShop(store, request.service());

        Product product = new Product(
                merchantId,
                store.getId(),
                request.name(),
                request.description(),
                request.price(),
                request.categoryId());
        product.assignCodes(request.sku(), request.barcode());
        // Built before anything is saved, so terms that break a rule refuse the whole offer.
        ServiceTerms terms = request.service() == null
                ? null
                : newTerms(product.getId(), request.service());

        // The saved instance, whatever save() did with the one handed in: the managed one is the only
        // one the database writes back into, timestamps included. The id is assigned here, so Spring
        // Data tells a new product by its version, which is null until the first save, and persists it.
        Product saved = products.save(product);
        // After the product, whose row the terms reference.
        ServiceTerms savedTerms = terms == null ? null : serviceTerms.save(terms);

        // Same transaction as the insert above: the event and the row commit together or not at
        // all, which is the whole point of the outbox (Section 7).
        outbox.record(CatalogEvents.AGGREGATE_TYPE, saved.getId().toString(),
                CatalogEvents.PRODUCT_CREATED, CatalogEvents.ProductSnapshot.of(saved, savedTerms));

        log.info("Merchant {} created product {}", merchantId, saved.getId());
        return saved;
    }

    @Transactional
    public Product update(UUID id, String merchantId, ProductRequest request) {
        Product product = requireOwned(id, merchantId);
        Store store = storeOf(product);
        validateCategory(request.categoryId(), product.getStoreId());
        requireTermsMatchShop(store, request.service());

        ServiceTerms terms = null;
        if (request.service() != null) {
            ServiceTerms existing = serviceTerms.findById(product.getId()).orElse(null);
            if (product.getStatus() == Product.Status.ACTIVE && !offersDelivery(existing)) {
                // A live offer switched to delivery meets the rule publishing it would have met. Only a
                // switch: an offer that already offered delivery met the rule when it was published or
                // resumed, and a shop that has since cleared its pin or its areas must still be able to
                // fix a typo in it without pausing it first. Resuming checks again, as publishing does.
                requireDeliveryReach(store, request.service().fulfilmentModes());
            }
            terms = reviseTerms(product, existing, request.service());
        }

        product.update(request.name(), request.description(), request.price(), request.categoryId(),
                request.sku(), request.barcode());

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED, CatalogEvents.ProductSnapshot.of(product, terms));
        return product;
    }

    @Transactional
    public Product publish(UUID id, String merchantId) {
        Product product = requireOwned(id, merchantId);
        Store store = storeOf(product);
        ServiceTerms terms = null;
        if (store.isServices()) {
            terms = requireTerms(product);
            requireDeliveryReach(store, terms.getFulfilmentModes());
        }
        try {
            product.publish();
        } catch (IllegalStateException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_PUBLISHED, CatalogEvents.ProductSnapshot.of(product, terms));
        return product;
    }

    /**
     * Withdraws a product from sale.
     *
     * <p>There is no hard delete. Past orders reference products, and an order history that cannot
     * name what was bought is useless for support or for the accounting reconciliation in Phase 4.
     */
    @Transactional
    public Product archive(UUID id, String merchantId) {
        Product product = requireOwned(id, merchantId);
        product.archive();

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_ARCHIVED,
                CatalogEvents.ProductSnapshot.of(product, serviceTerms.findById(id).orElse(null)));
        return product;
    }

    /**
     * Takes a live service offer off sale for now: ACTIVE to PAUSED.
     *
     * <p>The owner's offers only; anybody else's is "not found", as for every other write. Pausing is
     * for service offers: a goods product is taken off sale by archiving, which is what the goods apps'
     * switch already sends, and those apps would draw a PAUSED product they have never heard of as a
     * draft. Recorded as {@code product.updated}, whose snapshot says PAUSED.
     */
    @Transactional
    public Product pause(UUID id, String merchantId) {
        Product product = requireOwned(id, merchantId);
        if (!storeOf(product).isServices()) {
            throw new CatalogRuleViolationException(
                    "Only a service offer can be paused. Take a product off sale by archiving it.");
        }
        try {
            product.pause();
        } catch (IllegalStateException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED,
                CatalogEvents.ProductSnapshot.of(product, serviceTerms.findById(id).orElse(null)));
        log.info("Merchant {} paused offer {}", merchantId, id);
        return product;
    }

    /**
     * Puts a paused service offer back on sale: PAUSED to ACTIVE.
     *
     * <p>Resuming puts the offer in front of customers again, so it meets every rule publishing does:
     * its terms, a photo, and delivery areas or a pin when it can be delivered. Something may have
     * changed while it was paused, such as the last photo removed or the shop's pin cleared.
     */
    @Transactional
    public Product resume(UUID id, String merchantId) {
        Product product = requireOwned(id, merchantId);
        Store store = storeOf(product);
        if (!store.isServices()) {
            throw new CatalogRuleViolationException(
                    "Only a service offer can be resumed. Put a product back on sale by publishing it.");
        }
        ServiceTerms terms = requireTerms(product);
        if (product.getStatus() == Product.Status.PAUSED) {
            // Only once the offer is known to be paused, so a resume of a live or draft offer is told
            // what it actually got wrong.
            requireDeliveryReach(store, terms.getFulfilmentModes());
        }
        try {
            product.resume();
        } catch (IllegalStateException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }

        outbox.record(CatalogEvents.AGGREGATE_TYPE, product.getId().toString(),
                CatalogEvents.PRODUCT_UPDATED, CatalogEvents.ProductSnapshot.of(product, terms));
        log.info("Merchant {} resumed offer {}", merchantId, id);
        return product;
    }

    // ---------------------------------------------------------------- categories

    @Transactional(readOnly = true)
    public java.util.List<Category> rootCategories() {
        return categories.findByParentIdIsNullOrderByName();
    }

    @Transactional(readOnly = true)
    public java.util.List<Category> childrenOf(UUID parentId) {
        return categories.findByParentIdOrderByName(parentId);
    }

    /**
     * The platform taxonomy — deliberately NOT every row.
     *
     * <p>Merchants author their own sections against the same table (V26). Returning those here
     * would put one shop's shelf in every client's category picker, so this reads only the rows
     * with no owning store.
     */
    @Transactional(readOnly = true)
    public java.util.List<Category> allCategories() {
        return categories.findByStoreIdIsNull();
    }

    @Transactional
    public Category createCategory(String name, UUID parentId) {
        if (parentId != null && !categories.existsById(parentId)) {
            throw new CategoryNotFoundException(parentId);
        }
        return categories.save(new Category(name, parentId));
    }

    // ---------------------------------------------------------------- internals

    /**
     * The one place the ownership rule is applied to a write.
     *
     * <p>Loads by id AND merchant id in a single query, so a merchant asking for someone else's
     * product gets an empty result rather than a row this code then has to remember to check.
     */
    private Product requireOwned(UUID id, String merchantId) {
        return products.findByIdAndMerchantId(id, merchantId)
                .orElseThrow(() -> {
                    // Distinguish the two cases in the log (useful for support) while returning the
                    // same 404 to the caller either way.
                    if (products.existsById(id)) {
                        log.warn("Merchant {} attempted to modify product {} they do not own",
                                merchantId, id);
                    }
                    return new ProductNotFoundException(id);
                });
    }

    /**
     * Checks the merchant owns the store they are filing a product under.
     *
     * <p>Without this a merchant could put products into a competitor's storefront by passing their
     * store id — the same class of hole that keeping {@code merchantId} out of the request body
     * closes for products themselves.
     */
    private Store requireOwnedStore(String merchantId, UUID storeId) {
        return storeService.ownedBy(merchantId).stream()
                .filter(s -> s.getId().equals(storeId))
                .findFirst()
                // "Not found", the same answer every other store-scoped write gives, and for the
                // same reason: "that store is not yours" confirms the id belongs to somebody, which
                // is a fact about a competitor obtainable by guessing.
                .orElseThrow(() -> new StoreService.StoreNotFoundException(storeId.toString()));
    }

    /** The shop a product sits in, which decides whether the product is a service offer. */
    private Store storeOf(Product product) {
        return stores.findById(product.getStoreId())
                .orElseThrow(() -> new StoreService.StoreNotFoundException(
                        product.getStoreId().toString()));
    }

    /**
     * Whether a shop's live offers are withheld from everyone but its provider: a service shop that is
     * not listed, because it is a draft, is suspended, or sits in a category the platform has closed
     * ({@link ServiceCategories}). The shops the services search leaves out
     * ({@code ProductRepository#findListedServiceOffers}), judged here on the row.
     *
     * <p>Never a goods shop. The open categories are read only about a service shop, so a mistake in
     * that setting cannot take a goods product off anybody's screen.
     */
    private boolean hidesItsOffers(Store store) {
        return store.isServices()
                && (store.getStatus() != Store.Status.ACTIVE
                        || !serviceCategories.enabled().contains(store.getServiceCategory()));
    }

    /**
     * Refuses, as "not found", a shelf its shop hides from this viewer ({@link #browseStore}). An id
     * that names no shop still answers the empty shelf it always did.
     */
    private void requireShelfShownTo(UUID storeId, String viewerId) {
        Optional<Store> store = stores.findById(storeId);
        if (store.isPresent() && !store.get().isOwnedBy(viewerId) && hidesItsOffers(store.get())) {
            throw new StoreService.StoreNotFoundException(storeId.toString());
        }
    }

    /**
     * A product in a service shop must carry service terms, and a product anywhere else must not.
     *
     * <p>The shop decides, never the body. A goods form that has never heard of terms keeps working
     * in a goods shop; a service offer can never be saved without the terms an order for it needs; and
     * no restaurant's dish can pick up a turnaround.
     */
    private static void requireTermsMatchShop(Store store, ServiceTermsRequest service) {
        if (store.isServices() && service == null) {
            throw new CatalogRuleViolationException("An offer in a service shop needs its service "
                    + "terms: how it is priced, how long it takes and how customers get it.");
        }
        if (!store.isServices() && service != null) {
            throw new CatalogRuleViolationException(
                    "Service terms are for offers in a service shop, and this product is in a goods shop.");
        }
    }

    /**
     * A service offer's terms, required before it goes in front of customers. A service shop's product
     * saved before terms existed has none, and must be given them by an update first.
     */
    private ServiceTerms requireTerms(Product product) {
        return serviceTerms.findById(product.getId())
                .orElseThrow(() -> new CatalogRuleViolationException("This offer has no service terms "
                        + "yet. Say how it is priced, how long it takes and how customers get it first."));
    }

    /**
     * An offer customers can have delivered is published only by a shop that says where it reaches:
     * delivery areas, or a pin to deliver from.
     *
     * <p>Without either, nothing tells a customer where the shop delivers or a rider where to collect
     * the work, and the provider would find out from a failed order. A pickup-only offer needs neither.
     */
    private void requireDeliveryReach(Store store, ServiceTerms.Fulfilment fulfilment) {
        if (fulfilment == null || !fulfilment.includesDelivery()) {
            return;
        }
        boolean pinned = store.getLatitude() != null && store.getLongitude() != null;
        if (pinned || storeZones.existsByStoreId(store.getId())) {
            return;
        }
        throw new CatalogRuleViolationException("Set your delivery areas or drop your shop's pin "
                + "before offering YouDrop delivery, or offer this for pickup only.");
    }

    private static ServiceTerms newTerms(UUID productId, ServiceTermsRequest request) {
        try {
            return new ServiceTerms(productId, request.pricingType(), request.unitLabel(),
                    request.unitSize(), request.turnaroundMinHours(), request.turnaroundMaxHours(),
                    request.fulfilmentModes(), request.attachmentPolicy(),
                    request.instructionsPrompt());
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
    }

    /** Whether saved terms already let customers have the offer delivered. No terms saved is no. */
    private static boolean offersDelivery(ServiceTerms terms) {
        return terms != null && terms.getFulfilmentModes() != null
                && terms.getFulfilmentModes().includesDelivery();
    }

    /**
     * The offer's terms revised to the request, or created for a service shop's product that was saved
     * before terms existed ({@code existing} is null). A refused revision changes nothing
     * ({@link ServiceTerms#revise}).
     */
    private ServiceTerms reviseTerms(Product product, ServiceTerms existing,
                                     ServiceTermsRequest request) {
        if (existing == null) {
            return serviceTerms.save(newTerms(product.getId(), request));
        }
        try {
            existing.revise(request.pricingType(), request.unitLabel(), request.unitSize(),
                    request.turnaroundMinHours(), request.turnaroundMaxHours(),
                    request.fulfilmentModes(), request.attachmentPolicy(),
                    request.instructionsPrompt());
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(e.getMessage());
        }
        return existing;
    }

    /**
     * A product may sit in a platform category, or in a section owned by its own store — never in
     * another shop's section.
     *
     * <p>Without the store check a merchant could file their goods under a competitor's shelf by
     * pasting an id, and that shelf's product count would then include stock its owner cannot see.
     */
    private void validateCategory(UUID categoryId, UUID storeId) {
        if (categoryId == null) {
            return;
        }
        Category category = categories.findById(categoryId)
                .orElseThrow(() -> new CategoryNotFoundException(categoryId));
        if (!category.isPlatformOwned() && !category.isOwnedByStore(storeId)) {
            // The identical refusal, so a competitor's shelf is indistinguishable from an id that
            // was never issued.
            throw new CategoryNotFoundException(categoryId);
        }
    }

    // ---------------------------------------------------------------- exceptions

    public static class ProductNotFoundException extends RuntimeException {
        public ProductNotFoundException(UUID id) {
            super("Product " + id + " was not found");
        }
    }

    /**
     * A category id that names nothing this caller may file under. Mapped to 404.
     *
     * <p>Its own type rather than a rule violation, because that is what it is: every other unknown
     * id in this service answers "not found", and a 422 on this one alone left a client unable to
     * tell a mistyped id from a payload it had to rewrite.
     */
    public static class CategoryNotFoundException extends RuntimeException {
        public CategoryNotFoundException(UUID id) {
            super("Category " + id + " was not found");
        }
    }

    public static class CatalogRuleViolationException extends RuntimeException {
        public CatalogRuleViolationException(String message) {
            super(message);
        }
    }
}

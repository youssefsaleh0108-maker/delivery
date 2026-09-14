package com.delivery.product.api;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import jakarta.validation.Valid;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.product.api.dto.CatalogDtos.PageResponse;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ProductResponse;
import com.delivery.product.api.dto.GeoDtos.CrossSellResponse;
import com.delivery.product.api.dto.OptionDtos.ChosenOptionResponse;
import com.delivery.product.api.dto.OptionDtos.OptionGroupRequest;
import com.delivery.product.api.dto.OptionDtos.OptionGroupResponse;
import com.delivery.product.api.dto.OptionDtos.OptionResponse;
import com.delivery.product.api.dto.OptionDtos.PriceRequest;
import com.delivery.product.api.dto.OptionDtos.PriceResponse;
import com.delivery.product.domain.ProductOptionGroup;
import com.delivery.product.domain.Store;
import com.delivery.product.service.ProductOptionService;
import com.delivery.product.service.ProductOptionService.PricedSelection;
import com.delivery.product.domain.Product;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.ProductView;
import com.delivery.product.service.CrossSellService;
import com.delivery.product.service.ProductImageService;
import com.delivery.product.service.ServiceOfferSearch;
import com.delivery.product.service.StoreService;

/**
 * The catalog API.
 *
 * <p>Two layers of authorisation, and both are needed. {@code @PreAuthorize} answers "may this kind
 * of user call this endpoint at all" from the realm role. The service layer then answers "may
 * <em>this</em> user touch <em>this</em> row" from the {@code sub} claim. Role alone would let any
 * merchant edit any merchant's catalog (Section 3).
 */
@RestController
@RequestMapping("/api/products")
public class ProductController {

    /**
     * The most suggestions one cross-sell request may ask for.
     *
     * <p>A rail shows four to six. Bounded so a caller cannot turn a recommendation endpoint into a
     * way to page a shop's whole shelf in one call, sorted by something that looks like popularity.
     */
    private static final int MAX_CROSS_SELL = 20;

    private final CatalogService catalog;
    private final ProductImageService images;
    private final ProductOptionService optionService;
    private final CrossSellService crossSell;
    private final ServiceOfferSearch serviceOffers;
    private final StoreService stores;

    public ProductController(CatalogService catalog, ProductImageService images,
                             ProductOptionService optionService, CrossSellService crossSell,
                             ServiceOfferSearch serviceOffers, StoreService stores) {
        this.catalog = catalog;
        this.images = images;
        this.optionService = optionService;
        this.crossSell = crossSell;
        this.serviceOffers = serviceOffers;
        this.stores = stores;
    }

    /** Customer-facing browse. ACTIVE products only, from every merchant. */
    @GetMapping
    public PageResponse<ProductResponse> browse(
            @RequestParam(required = false) UUID categoryId,
            @RequestParam(required = false) String search,
            @PageableDefault(size = 20, sort = "createdAt", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<Product> page = catalog.browseCatalog(categoryId, search, pageable);
        return PageResponse.of(catalog.views(page).map(this::toResponse));
    }

    /**
     * The Merchant Portal's list: everything the caller owns, in any status or in the one asked for,
     * from every shop they own or from the one named.
     *
     * <p>{@code storeId} and {@code status} are how the provider dashboard counts "Active offers":
     * {@code ?storeId=<its service shop>&status=ACTIVE} with {@code size=1}, then the page's
     * {@code totalElements}. Per shop, because one account may own a goods shop and a service shop.
     * A shop the caller does not own is a 404, and a status this service does not have is a 400,
     * rather than an unfiltered list either way.
     *
     * <p>Declared before {@code /{id}} would otherwise be ambiguous — Spring resolves the literal
     * path first, but keeping them adjacent makes the intent obvious to the next reader.
     */
    @GetMapping("/mine")
    @PreAuthorize("hasRole('MERCHANT')")
    public PageResponse<ProductResponse> mine(
            @RequestParam(required = false) UUID storeId,
            @RequestParam(required = false) Product.Status status,
            @PageableDefault(size = 20, sort = "createdAt", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<Product> page = catalog.listOwnedBy(CurrentUser.requireId(), storeId, status, pageable);
        return PageResponse.of(catalog.views(page).map(this::toResponse));
    }

    /**
     * The services offer search: live offers of listed service shops in open categories, by name.
     *
     * <p>Never a goods product, a paused offer, or an offer of a draft, suspended or closed-category
     * shop ({@link ServiceOfferSearch}). A category the platform does not have is a 400; one it has
     * but has closed answers an empty page, as a category with no offers does.
     *
     * <p>Any signed-in caller, like every other catalogue read (the browse, a product, a shop's
     * shelf): the customer app's Services tab, a merchant-only or back-office-only account, and back
     * office's catalogue, which reads offers here. It returns nothing a customer may not see. A
     * literal path, resolved before {@code /{id}}.
     */
    @GetMapping("/services")
    @PreAuthorize("isAuthenticated()")
    public PageResponse<ProductResponse> services(
            @RequestParam(required = false) String search,
            @RequestParam(required = false) Store.ServiceCategory serviceCategory,
            @PageableDefault(size = 20, sort = "createdAt", direction = Sort.Direction.DESC)
            Pageable pageable) {

        Page<Product> page = serviceOffers.search(search, serviceCategory, pageable);
        return PageResponse.of(catalog.views(page).map(this::toResponse));
    }

    @GetMapping("/{id}")
    public ProductResponse read(@PathVariable UUID id) {
        // The viewer id is passed in so the service can decide whether a DRAFT is visible; an
        // anonymous-but-authenticated customer simply won't match the owner.
        return toResponse(catalog.view(catalog.read(id, CurrentUser.id().orElse(null))));
    }

    /**
     * The "People Also Ordered" rail.
     *
     * <p>Named for what it computes. This counts how often two products shared a <em>delivered</em>
     * basket — item co-occurrence — and it is not collaborative filtering: there is no model of who
     * the caller is, no similarity between shoppers, and no attempt at one. Calling the path
     * {@code /recommendations} would have implied all three.
     *
     * <p>Every item carries a {@code basis} saying how it was arrived at, and clients should not
     * ignore it. {@code BOUGHT_TOGETHER} comes with a real count of delivered baskets;
     * {@code SAME_AISLE} is fill from the same shop with no count, because nothing was measured.
     * Until the delivered-basket projection has accumulated data — it cannot be backfilled, see
     * {@link com.delivery.product.service.CrossSellService} — every item will be the latter.
     *
     * <p>Open to any authenticated caller, like the rest of browsing. It returns nothing the store's
     * own product list does not already return.
     */
    @GetMapping("/{id}/bought-together")
    public List<CrossSellResponse> boughtTogether(
            @PathVariable UUID id,
            @RequestParam(defaultValue = "8") int limit) {

        // Read through the same path as any other product view, so a DRAFT or archived product 404s
        // for a customer rather than quietly seeding a rail from a shelf they may not see.
        Product product = catalog.read(id, CurrentUser.id().orElse(null));

        var suggestions = crossSell.boughtTogetherWith(
                product, Math.min(Math.max(limit, 1), MAX_CROSS_SELL));
        // The whole rail's views at once, rather than one read per tile.
        Map<UUID, ProductView> views = viewsById(suggestions.stream().map(s -> s.product()).toList());
        return suggestions.stream()
                .map(s -> new CrossSellResponse(
                        toResponse(views.get(s.product().getId())), s.basis(), s.ordersTogether()))
                .toList();
    }

    /**
     * Adds a product.
     *
     * <p>What a merchant's first product may open is asked here, before the catalogue's transaction
     * begins, and handed in: Onboarding can take seconds to answer, and inside the transaction that
     * wait held a pooled connection and the merchant's lock (see {@link StoreService#firstShopFor}).
     */
    @PostMapping
    @PreAuthorize("hasRole('MERCHANT')")
    public ResponseEntity<ProductResponse> create(@Valid @RequestBody ProductRequest request) {
        String merchantId = CurrentUser.requireId();
        Product product = catalog.create(merchantId, request,
                stores.firstShopFor(merchantId, request.storeId()));
        return ResponseEntity.status(HttpStatus.CREATED).body(toResponse(catalog.view(product)));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('MERCHANT')")
    public ProductResponse update(@PathVariable UUID id, @Valid @RequestBody ProductRequest request) {
        return toResponse(catalog.view(catalog.update(id, CurrentUser.requireId(), request)));
    }

    @PostMapping("/{id}/publish")
    // Explorable before approval, not publishable. A pending merchant carries MERCHANT so they can
    // set the shop up and see every screen, and APPLICANT until somebody approves them — so the one
    // thing gated is the act that puts goods in front of customers.
    @PreAuthorize("hasRole('MERCHANT') and !hasRole('APPLICANT')")
    public ProductResponse publish(@PathVariable UUID id) {
        return toResponse(catalog.view(catalog.publish(id, CurrentUser.requireId())));
    }

    /**
     * Takes a live service offer off sale for now (ACTIVE to PAUSED).
     *
     * <p>The provider's own offers only: anybody else's is a 404, like an id that was never issued. A
     * goods product is a 422, because goods are taken off sale by archiving. Never gated on approval:
     * stopping sales must always be possible.
     */
    @PostMapping("/{id}/pause")
    @PreAuthorize("hasRole('MERCHANT')")
    public ProductResponse pause(@PathVariable UUID id) {
        return toResponse(catalog.view(catalog.pause(id, CurrentUser.requireId())));
    }

    /**
     * Puts a paused service offer back on sale (PAUSED to ACTIVE), under publishing's rules: a photo,
     * and delivery areas or a pin for an offer that can be delivered (422).
     *
     * <p>Gated exactly like publish, because it is the same act: putting an offer in front of
     * customers.
     */
    @PostMapping("/{id}/resume")
    @PreAuthorize("hasRole('MERCHANT') and !hasRole('APPLICANT')")
    public ProductResponse resume(@PathVariable UUID id) {
        return toResponse(catalog.view(catalog.resume(id, CurrentUser.requireId())));
    }

    /** Archive, not delete — past orders still reference this product. */
    @DeleteMapping("/{id}")
    @PreAuthorize("hasRole('MERCHANT')")
    public ProductResponse archive(@PathVariable UUID id) {
        return toResponse(catalog.view(catalog.archive(id, CurrentUser.requireId())));
    }

    // ---------------------------------------------------------------- options

    /**
     * The questions to ask before this product can go in a basket.
     *
     * <p>Behind the rule reading the product follows ({@link CatalogService#read}): the choices and
     * what each adds are part of the product, so a draft, a paused offer or an offer of a shop that is
     * not listed keeps them to its owner, and anybody else is told the product is not found.
     */
    @GetMapping("/{id}/options")
    public List<OptionGroupResponse> options(@PathVariable UUID id) {
        catalog.read(id, CurrentUser.id().orElse(null));
        return optionService.forProduct(id).stream().map(ProductController::toGroup).toList();
    }

    /**
     * Prices a selection.
     *
     * <p>Open to any authenticated caller because the customer app needs it to show a running total
     * as options are ticked — and because it is a read that reveals nothing the menu does not.
     * Order Manager calls the same endpoint at checkout, so the price shown and the price charged
     * come from one implementation.
     *
     * <p>Which is why it follows reading the product ({@link CatalogService#read}). A product the
     * caller may not read is "not found" here too: a draft, paused or archived product, or a live
     * offer of a shop that is a draft, suspended or in a closed category, is quoted to its owner only.
     * No quote is given for a line nobody could order, and Order Manager, which prices with the
     * customer's token, is refused at the price as well as at the read.
     */
    @PostMapping("/{id}/price")
    public PriceResponse price(@PathVariable UUID id, @RequestBody(required = false) PriceRequest request) {
        Product product = catalog.read(id, CurrentUser.id().orElse(null));
        PricedSelection priced = optionService.price(
                product, request == null ? List.of() : request.optionIds());
        return new PriceResponse(
                priced.basePrice(),
                priced.unitPrice(),
                priced.options().stream()
                        .map(o -> new ChosenOptionResponse(
                                o.groupName(), o.optionName(), o.priceDelta()))
                        .toList());
    }

    /** Replaces the product's whole option structure. */
    @PutMapping("/{id}/options")
    @PreAuthorize("hasRole('MERCHANT')")
    public List<OptionGroupResponse> setOptions(
            @PathVariable UUID id,
            @Valid @RequestBody List<OptionGroupRequest> groups) {
        return optionService.replace(id, CurrentUser.requireId(), groups).stream()
                .map(ProductController::toGroup)
                .toList();
    }

    private static OptionGroupResponse toGroup(ProductOptionGroup group) {
        return new OptionGroupResponse(
                group.getId(),
                group.getName(),
                group.getMinSelect(),
                group.getMaxSelect(),
                group.isRequired(),
                group.isSingleChoice(),
                group.getOptions().stream()
                        .map(o -> new OptionResponse(o.getId(), o.getName(), o.getPriceDelta(),
                                o.isDefault(), o.isAvailable()))
                        .toList());
    }

    /** Views for a list of products, by id, read in one go. */
    private Map<UUID, ProductView> viewsById(List<Product> products) {
        return catalog.views(products).stream()
                .collect(Collectors.toMap(view -> view.product().getId(), Function.identity(),
                        (first, repeated) -> first));
    }

    private ProductResponse toResponse(ProductView view) {
        return ProductResponses.of(view, images);
    }
}

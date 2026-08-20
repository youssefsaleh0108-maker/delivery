package com.delivery.product.service;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.product.api.dto.OptionDtos.OptionGroupRequest;
import com.delivery.product.api.dto.OptionDtos.OptionRequest;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.ProductOption;
import com.delivery.product.domain.ProductOptionGroup;
import com.delivery.product.domain.ProductOptionGroupRepository;
import com.delivery.product.domain.ProductRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;

/**
 * Product options, and the pricing that depends on them.
 *
 * <p>The important method here is {@link #price}. Order Manager must not add up option deltas
 * itself: the catalog owns prices, and a second implementation of the sum is a second thing that
 * can disagree with the menu. So the order path sends the chosen option ids and is told what the
 * line costs, exactly as it already asks for a product's base price rather than trusting the client.
 */
@Service
public class ProductOptionService {

    private final ProductRepository products;
    private final ProductOptionGroupRepository groups;

    public ProductOptionService(ProductRepository products, ProductOptionGroupRepository groups) {
        this.products = products;
        this.groups = groups;
    }

    // ---------------------------------------------------------------- reads

    @Transactional(readOnly = true)
    public List<ProductOptionGroup> forProduct(UUID productId) {
        return groups.findByProductIdOrderByPositionAsc(productId);
    }

    /**
     * Groups for many products at once, grouped by product id.
     *
     * <p>One query for a whole shelf rather than one per card.
     */
    @Transactional(readOnly = true)
    public Map<UUID, List<ProductOptionGroup>> forProducts(Collection<UUID> productIds) {
        if (productIds.isEmpty()) {
            return Map.of();
        }
        return groups.findByProductIdInOrderByPositionAsc(productIds).stream()
                .collect(Collectors.groupingBy(ProductOptionGroup::getProductId));
    }

    // ---------------------------------------------------------------- pricing

    /**
     * Validates a selection and prices it.
     *
     * <p>Every group is checked, not just the ones the customer answered — that is what catches a
     * missing required choice. Duplicate ids are collapsed first, so sending the same option twice
     * cannot be used to apply its discount twice.
     */
    @Transactional(readOnly = true)
    public PricedSelection price(UUID productId, List<UUID> optionIds) {
        Product product = products.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException(productId));

        Collection<UUID> distinct = new LinkedHashSet<>(optionIds == null ? List.of() : optionIds);

        List<ProductOptionGroup> productGroups = groups.findByProductIdOrderByPositionAsc(productId);
        Map<UUID, ProductOption> chosenById = new HashMap<>();
        List<ChosenOption> chosen = new ArrayList<>();
        BigDecimal delta = BigDecimal.ZERO;

        for (ProductOptionGroup group : productGroups) {
            List<ProductOption> inThisGroup = group.getOptions().stream()
                    .filter(o -> distinct.contains(o.getId()))
                    .toList();
            try {
                group.validateSelection(inThisGroup);
            } catch (IllegalArgumentException e) {
                throw new CatalogRuleViolationException(e.getMessage());
            }
            for (ProductOption option : inThisGroup) {
                chosenById.put(option.getId(), option);
                chosen.add(new ChosenOption(group.getName(), option.getName(),
                        option.getPriceDelta()));
                delta = delta.add(option.getPriceDelta());
            }
        }

        // An id that matched no group at all would otherwise be silently ignored, and a client
        // sending stale option ids after a menu change deserves to be told.
        for (UUID id : distinct) {
            if (!chosenById.containsKey(id)) {
                throw new CatalogRuleViolationException(
                        "Option " + id + " does not belong to this product");
            }
        }

        BigDecimal unit = product.getPrice().add(delta);
        if (unit.signum() < 0) {
            // Only reachable through negative deltas that overshoot; a line cannot pay the customer.
            unit = BigDecimal.ZERO;
        }
        return new PricedSelection(product.getPrice(), unit, chosen);
    }

    public record ChosenOption(String groupName, String optionName, BigDecimal priceDelta) {
    }

    public record PricedSelection(BigDecimal basePrice, BigDecimal unitPrice,
                                  List<ChosenOption> options) {
    }

    // ---------------------------------------------------------------- writes

    /**
     * Replaces a product's whole option structure.
     *
     * <p>Replace rather than merge, for the same reason as a store's opening hours: a menu's
     * options are edited as a set, and merging would put the "which of these did you mean to
     * delete" bookkeeping on every caller.
     */
    @Transactional
    public List<ProductOptionGroup> replace(UUID productId, String merchantId,
                                            List<OptionGroupRequest> requested) {
        products.findByIdAndMerchantId(productId, merchantId)
                .orElseThrow(() -> new ProductNotFoundException(productId));

        groups.deleteByProductId(productId);
        // Flushed before the inserts so the delete and the re-insert cannot interleave into a
        // unique-constraint collision within the same transaction.
        groups.flush();

        List<ProductOptionGroup> saved = new ArrayList<>();
        int groupPosition = 0;
        for (OptionGroupRequest groupRequest : requested) {
            ProductOptionGroup group;
            try {
                group = new ProductOptionGroup(productId, groupRequest.name(),
                        groupRequest.minSelect(), groupRequest.maxSelect(), groupPosition++);
            } catch (IllegalArgumentException e) {
                throw new CatalogRuleViolationException(e.getMessage());
            }

            List<ProductOption> options = new ArrayList<>();
            int optionPosition = 0;
            for (OptionRequest optionRequest : groupRequest.options()) {
                options.add(new ProductOption(optionRequest.name(), optionRequest.priceDelta(),
                        optionRequest.isDefault(), optionPosition++));
            }
            if (options.isEmpty()) {
                throw new CatalogRuleViolationException(
                        "Group \"" + groupRequest.name() + "\" needs at least one option");
            }
            if (options.size() < groupRequest.minSelect()) {
                throw new CatalogRuleViolationException(
                        "Group \"" + groupRequest.name() + "\" asks for "
                                + groupRequest.minSelect() + " choices but offers "
                                + options.size());
            }
            group.replaceOptions(options);
            saved.add(group);
        }

        // The join column is written by the parent side; setting product_id happens through the
        // @JoinColumn on Product's collection, so groups are attached explicitly here.
        for (ProductOptionGroup group : saved) {
            groups.save(group);
        }
        // Re-read so the generated product_id fields are populated on the returned objects.
        return groups.findByProductIdOrderByPositionAsc(productId);
    }
}

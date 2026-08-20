package com.delivery.whatsapp.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.whatsapp.client.OrderClient;
import com.delivery.whatsapp.client.ProductClient;
import com.delivery.whatsapp.domain.Conversation;
import com.delivery.whatsapp.domain.DraftLine;
import com.delivery.whatsapp.domain.DraftLineOption;
import com.delivery.whatsapp.domain.DraftOrder;
import com.delivery.whatsapp.repo.DraftOrderRepository;

/**
 * Turning a conversation into an order — the step a merchant makes, not the platform.
 *
 * <p>The temptation this service exists to resist is parsing the message and placing the order. That
 * is wrong in a way that shows up on the first day: "hi", "are you open?" and "the usual" would all
 * become purchases, and a mis-parsed quantity is money the customer pays. So the merchant reads what
 * was actually written, picks the products from their own catalog, types the address, and confirms.
 *
 * <p>The platform's contribution is the part merchants genuinely do badly by hand: pricing it from
 * the real catalog, applying the shop's fee and minimum, and getting a rider to it.
 */
@Service
public class DraftOrderService {

    private static final Logger log = LoggerFactory.getLogger(DraftOrderService.class);

    /**
     * How a WhatsApp customer is identified on the order.
     *
     * <p>Prefixed so it can never collide with a Keycloak subject. That is the whole point: a
     * merchant places these orders, and if the reference could look like a real account holder's id
     * then a merchant could place an order in a real customer's name.
     */
    static final String CUSTOMER_PREFIX = "wa:";

    private final DraftOrderRepository drafts;
    private final ConversationService conversations;
    private final ProductClient products;
    private final OrderClient orders;

    public DraftOrderService(DraftOrderRepository drafts,
                             ConversationService conversations,
                             ProductClient products,
                             OrderClient orders) {
        this.drafts = drafts;
        this.conversations = conversations;
        this.products = products;
        this.orders = orders;
    }

    /** Thrown when the merchant asks for something the draft cannot do. */
    public static class DraftRuleViolationException extends RuntimeException {
        public DraftRuleViolationException(String message) {
            super(message);
        }
    }

    // ---------------------------------------------------------------- opening one

    /**
     * Opens a draft against a conversation, or returns the one already open.
     *
     * <p>Idempotent on purpose, and enforced by a partial unique index underneath. A merchant
     * tapping "start an order" twice — on a slow connection, or on two devices — must not end up
     * with the customer's request split across two half-orders, neither of which is right.
     */
    @Transactional
    public DraftOrder openFor(UUID conversationId, String merchantRef, String requestText) {
        Conversation conversation = conversations.find(conversationId, merchantRef)
                .orElseThrow(() -> new DraftRuleViolationException("no such conversation"));

        return drafts.findByConversationIdAndStatus(conversationId, DraftOrder.Status.OPEN)
                .orElseGet(() -> drafts.save(
                        new DraftOrder(conversation.getId(), merchantRef, requestText)));
    }

    // ---------------------------------------------------------------- building it

    @Transactional
    public DraftOrder addLine(UUID draftId, String merchantRef, UUID productId, int qty,
                              List<UUID> optionIds) {
        DraftOrder draft = require(draftId, merchantRef);

        ProductClient.CatalogProduct product = products.fetch(productId);
        // The merchant's own catalog only. Without this a merchant could build a draft from a
        // competitor's menu and discover it at the moment of placing, after telling the customer a
        // price — and Order Manager's own check would then refuse the whole thing.
        if (!merchantRef.equals(product.merchantId())) {
            throw new DraftRuleViolationException("that product is not yours to sell");
        }
        if (!product.isSellable()) {
            // Caught here rather than at placement so the merchant learns it while they are still
            // talking to the customer and can offer something else.
            throw new DraftRuleViolationException(product.name() + " is not currently available");
        }

        // The catalog prices the selection and validates it, exactly as it does for the app. Doing
        // it now rather than at placement means a missing required group — "Choose Size" needs a
        // selection — reaches the merchant while the customer is still on the other end.
        ProductClient.PricedLine priced = products.price(productId, optionIds);

        draft.addLine(product.id(), product.name(), priced.unitPrice(), qty,
                DraftLine.normalise(optionIds), chosenOptions(productId, optionIds));
        return drafts.save(draft);
    }

    /**
     * Pairs the chosen option ids with their names.
     *
     * <p>The pricing response carries the names but not the ids, and the ids are what get sent to
     * Order Manager — so the two have to be matched up here. An id the catalog does not recognise
     * cannot happen (pricing would have refused it first), but if it somehow did, it is skipped from
     * the display rather than shown as a UUID.
     */
    private List<DraftLineOption> chosenOptions(UUID productId, List<UUID> optionIds) {
        List<UUID> chosen = DraftLine.normalise(optionIds);
        if (chosen.isEmpty()) {
            return List.of();
        }
        List<DraftLineOption> snapshot = new ArrayList<>();
        for (ProductClient.OptionGroup group : products.options(productId)) {
            for (ProductClient.Option option : group.options()) {
                if (chosen.contains(option.id())) {
                    snapshot.add(new DraftLineOption(
                            option.id(), group.name(), option.name(), option.priceDelta()));
                }
            }
        }
        return snapshot;
    }

    @Transactional
    public DraftOrder removeLine(UUID draftId, String merchantRef, UUID lineId) {
        DraftOrder draft = require(draftId, merchantRef);
        if (!draft.removeLine(lineId)) {
            throw new DraftRuleViolationException("that item is not in this request");
        }
        return drafts.save(draft);
    }

    @Transactional
    public DraftOrder setDelivery(UUID draftId, String merchantRef, String address, UUID zoneId,
                                  String contactPhone, String notes) {
        DraftOrder draft = require(draftId, merchantRef);
        draft.setDelivery(address, zoneId, contactPhone, notes);
        return drafts.save(draft);
    }

    // ---------------------------------------------------------------- resolving it

    /**
     * Confirms the draft: the moment a request becomes an order.
     *
     * <p>Order Manager does the actual work — it prices the basket from the catalog, applies the
     * shop's fee and minimum, checks the area is served, publishes the event and dispatches a rider.
     * Nothing about a WhatsApp order is priced or settled differently, which is the only way it
     * stays in step with orders from the app.
     *
     * <p>The draft is marked PLACED only after Order Manager has accepted it. If placement fails the
     * draft stays open with everything the merchant typed still in it, so they can fix the one thing
     * that was wrong rather than start again.
     */
    @Transactional
    public DraftOrder place(UUID draftId, String merchantRef) {
        DraftOrder draft = require(draftId, merchantRef);

        if (draft.getLines().isEmpty()) {
            throw new DraftRuleViolationException("add at least one item before placing this");
        }
        if (draft.getDeliveryAddress() == null || draft.getDeliveryAddress().isBlank()) {
            throw new DraftRuleViolationException("this needs a delivery address");
        }

        Conversation conversation = conversations.find(draft.getConversationId(), merchantRef)
                .orElseThrow(() -> new DraftRuleViolationException("no such conversation"));

        OrderClient.PlacedOrder placed = orders.place(new OrderClient.PlaceOnBehalf(
                CUSTOMER_PREFIX + conversation.getCustomerWaId(),
                conversation.displayName(),
                draft.getLines().stream()
                        .map(line -> new OrderClient.Line(
                                line.getProductId(), line.getQty(), line.chosenOptionIds()))
                        .toList(),
                draft.getDeliveryAddress(),
                draft.getDeliveryZoneId(),
                // The customer's WhatsApp id is their phone number, and it is the number the rider
                // will actually call. Falls back to it rather than leaving the rider with nothing.
                draft.getContactPhone() == null || draft.getContactPhone().isBlank()
                        ? conversation.getCustomerWaId()
                        : draft.getContactPhone(),
                draft.getNotes(),
                // Cash, always. A customer ordering over chat has entered card details nowhere.
                "CASH"));

        draft.placedAs(placed.id());
        log.info("Draft {} became order {} for merchant {}", draftId, placed.id(), merchantRef);
        DraftOrder saved = drafts.save(draft);

        confirmToCustomer(conversation, merchantRef, placed);
        return saved;
    }

    /**
     * Tells the customer their order is in.
     *
     * <p>The thing they are sitting there waiting for, and the thing a merchant most often forgets
     * to do by hand. It carries the total, because "how much is it" is the next message otherwise.
     *
     * <p>Best effort, deliberately. The order exists and the kitchen has it; a messaging outage must
     * not undo that, and must not make the merchant think the placement failed. The failure is
     * logged and the unsent reply is still recorded in the thread, so the merchant can see it did
     * not go and say so themselves.
     */
    private void confirmToCustomer(Conversation conversation, String merchantRef,
                                   OrderClient.PlacedOrder placed) {
        try {
            conversations.reply(conversation.getId(), merchantRef,
                    "Your order is confirmed. Total " + placed.totalAmount()
                            + " (including " + placed.deliveryFee() + " delivery), paid in cash "
                            + "on arrival. We will message you when it is on the way.");
        } catch (Exception e) {
            log.error("Order {} was placed but the customer could not be told", placed.id(), e);
        }
    }

    @Transactional
    public DraftOrder discard(UUID draftId, String merchantRef) {
        DraftOrder draft = require(draftId, merchantRef);
        draft.discard();
        return drafts.save(draft);
    }

    // ---------------------------------------------------------------- reading

    /**
     * The option groups a merchant picks from when adding a product.
     *
     * <p>Ownership-checked here rather than relying on the catalog: a merchant browsing options is
     * reading a competitor's menu structure otherwise, which is commercially their business and not
     * ours to hand over.
     */
    @Transactional(readOnly = true)
    public List<ProductClient.OptionGroup> optionsFor(UUID productId, String merchantRef) {
        ProductClient.CatalogProduct product = products.fetch(productId);
        if (!merchantRef.equals(product.merchantId())) {
            throw new DraftRuleViolationException("that product is not yours");
        }
        return products.options(productId);
    }

    /** Everything still waiting to become an order. The merchant's work list. */
    @Transactional(readOnly = true)
    public List<DraftOrder> open(String merchantRef) {
        return drafts.findByMerchantRefAndStatusOrderByCreatedAtAsc(
                merchantRef, DraftOrder.Status.OPEN);
    }

    @Transactional(readOnly = true)
    public Optional<DraftOrder> find(UUID draftId, String merchantRef) {
        return drafts.findByIdAndMerchantRef(draftId, merchantRef);
    }

    /** Every draft this conversation has produced, newest first — including the ones placed. */
    @Transactional(readOnly = true)
    public List<DraftOrder> forConversation(UUID conversationId, String merchantRef) {
        return conversations.find(conversationId, merchantRef)
                .map(conversation -> drafts.findByConversationIdOrderByCreatedAtDesc(conversationId))
                .orElse(List.of());
    }

    /**
     * The draft, or a refusal. Scoped by merchant in the query, so a row belonging to another shop
     * is never loaded and then checked — that ordering is what leaks one merchant's data to another.
     */
    private DraftOrder require(UUID draftId, String merchantRef) {
        DraftOrder draft = drafts.findByIdAndMerchantRef(draftId, merchantRef)
                .orElseThrow(() -> new DraftRuleViolationException("no such request"));
        if (draft.getStatus() != DraftOrder.Status.OPEN) {
            throw new DraftRuleViolationException(
                    "this request has already been " + draft.getStatus().name().toLowerCase());
        }
        return draft;
    }
}

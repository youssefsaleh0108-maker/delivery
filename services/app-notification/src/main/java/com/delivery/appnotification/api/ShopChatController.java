package com.delivery.appnotification.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.appnotification.domain.ChatShopThread;
import com.delivery.appnotification.service.ChatDisplayName;
import com.delivery.appnotification.service.ShopChatService;
import com.delivery.appnotification.service.ShopMessageView;
import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.security.CurrentUser;

/**
 * Chat between a customer and a shop.
 *
 * <p>Each endpoint states who may call it. Opening a thread with a shop is a CUSTOMER action, and
 * opening one for an order a MERCHANT's; the inbox is a MERCHANT's; reading, posting and read receipts
 * are open to both roles and then decided by the thread — the caller's own customer thread, or a shop
 * Product Service confirms is theirs. As in every chat controller here, no parameter names a user or a
 * side; an order id names an order, which Order Manager must show to the caller before it counts.
 */
@RestController
@RequestMapping("/api/chat")
public class ShopChatController {

    private final ShopChatService shops;

    public ShopChatController(ShopChatService shops) {
        this.shops = shops;
    }

    /**
     * Get-or-create the caller's conversation with a shop. Idempotent; 404 for a shop the caller
     * cannot see.
     *
     * <p>{@code orderId}, when the chat is opened from one of the caller's orders, labels the thread
     * with that order once Order Manager confirms it is theirs and was placed with this shop. Any other
     * order is the same 404 as an unknown shop; 503 when orders cannot be checked. Without it, nothing
     * about opening changes.
     */
    @PostMapping("/stores/{storeId}/thread")
    @PreAuthorize("hasRole('CUSTOMER')")
    public ThreadView open(@PathVariable UUID storeId, @RequestParam(required = false) UUID orderId) {
        return ThreadView.of(shops.openForCustomer(storeId, CurrentUser.requireId(),
                ChatDisplayName.from(CurrentUser.jwt().orElse(null)), orderId), Instant.now());
    }

    /**
     * Get-or-create the conversation between an order's shop and the customer who placed it, labelled
     * with that order — a provider's "chat with the customer". Idempotent.
     *
     * <p>MERCHANT, for an order of a shop they answer for; any other order is a 404, as one that does
     * not exist. 409 with {@code closedAt} once the order was delivered or cancelled longer ago than a
     * shop may open a chat about it; 503 when orders or shops cannot be checked. The view names the
     * customer only as the order's card does, and never by user id.
     */
    @PostMapping("/orders/{orderId}/shop-thread")
    @PreAuthorize("hasRole('MERCHANT')")
    public ThreadView openForOrder(@PathVariable UUID orderId) {
        return ThreadView.of(shops.openForOrder(orderId, CurrentUser.requireId()), Instant.now());
    }

    /** The shops' conversations the calling merchant answers, newest first. */
    @GetMapping("/shop-threads/inbox")
    @PreAuthorize("hasRole('MERCHANT')")
    public List<ThreadView> inbox() {
        Instant now = Instant.now();
        return shops.inbox(CurrentUser.requireId()).stream()
                .map(state -> ThreadView.of(state, now))
                .toList();
    }

    @GetMapping("/shop-threads/{threadId}/messages")
    @PreAuthorize("hasAnyRole('CUSTOMER','MERCHANT')")
    public PageView messages(@PathVariable UUID threadId,
                             @RequestParam(defaultValue = "0") @Min(0) long afterSequence) {
        String me = CurrentUser.requireId();
        ShopChatService.ThreadPage page =
                shops.history(threadId, me, CurrentUser.hasRole("MERCHANT"), afterSequence);
        UUID storeId = page.state().thread().getStoreId();
        return new PageView(
                ThreadView.of(page.state(), Instant.now()),
                page.messages().stream().map(message -> ShopMessageView.of(message, storeId, me)).toList(),
                page.more());
    }

    /** 201 with the stored message; 409 once the thread has gone idle; 422 / 429 as in rooms. */
    @PostMapping("/shop-threads/{threadId}/messages")
    @PreAuthorize("hasAnyRole('CUSTOMER','MERCHANT')")
    public ResponseEntity<ShopMessageView> post(@PathVariable UUID threadId,
                                                @Valid @RequestBody PostMessageRequest request) {
        String me = CurrentUser.requireId();
        ShopChatService.Posted posted = shops.post(threadId, me, CurrentUser.hasRole("MERCHANT"),
                request.text(), request.clientMessageId(), MDC.get(CorrelationIdFilter.MDC_KEY));
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ShopMessageView.of(posted.message(), posted.storeId(), me));
    }

    @PostMapping("/shop-threads/{threadId}/read")
    @PreAuthorize("hasAnyRole('CUSTOMER','MERCHANT')")
    public Map<String, Integer> markRead(@PathVariable UUID threadId,
                                         @Valid @RequestBody MarkReadRequest request) {
        return Map.of("updated", shops.markRead(threadId, CurrentUser.requireId(),
                CurrentUser.hasRole("MERCHANT"), request.upToSequence()));
    }

    /**
     * No order reference is accepted on a message: one a client could type would let a customer
     * present somebody else's order to a shop. A thread is labelled with an order only by opening it
     * ({@link #open}, {@link #openForOrder}), and only once Order Manager has confirmed that order to
     * the caller.
     */
    public record PostMessageRequest(
            @NotBlank @Size(max = 4000) String text,
            @Size(max = 64) String clientMessageId) {
    }

    public record MarkReadRequest(@Min(0) long upToSequence) {
    }

    /**
     * A thread as the caller's side sees it.
     *
     * <p>Deliberately without the customer's user id, on either side: the shop is told who it is
     * talking to only as {@code customerName}, and the customer already knows who they are.
     *
     * @param customerName what the shop sees of the customer — a first name and an initial, no phone
     *                     number and no address
     * @param yourSide     CUSTOMER or SHOP; the client draws the thread from it
     * @param open         whether the composer should be enabled
     * @param orderId      the order the thread was last opened from or for, as Order Manager confirmed
     *                     it; null when there is none
     * @param orderShortId that order's number as every order screen shows it, the id's first eight
     *                     characters; null when there is no order
     * @param orderKind    that order's kind (CATALOG, SERVICE, ...); null when there is no order
     */
    public record ThreadView(
            UUID id,
            UUID storeId,
            String storeName,
            String customerName,
            String yourSide,
            boolean open,
            Instant closesAt,
            Instant lastMessageAt,
            long lastSequence,
            long unread,
            UUID orderId,
            String orderShortId,
            String orderKind,
            String lastMessagePreview,
            String lastMessageSide) {

        static ThreadView of(ShopChatService.ThreadState state, Instant now) {
            ChatShopThread thread = state.thread();
            UUID orderId = thread.getOrderId();
            return new ThreadView(
                    thread.getId(),
                    thread.getStoreId(),
                    thread.getStoreName(),
                    thread.getCustomerName(),
                    state.side().name(),
                    thread.isOpenAt(now),
                    thread.getClosesAt(),
                    thread.getLastMessageAt(),
                    thread.getNextSequence() - 1,
                    state.unread(),
                    orderId,
                    orderId == null ? null : orderId.toString().substring(0, 8),
                    orderId == null ? null : thread.getOrderKind(),
                    state.latestPreview(),
                    state.latest() == null ? null : state.latest().getSenderSide().name());
        }
    }

    public record PageView(ThreadView thread, List<ShopMessageView> messages, boolean more) {
    }
}

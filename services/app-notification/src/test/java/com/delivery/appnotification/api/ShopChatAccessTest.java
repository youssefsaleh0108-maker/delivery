package com.delivery.appnotification.api;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.RequestBuilder;

import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ChatShopThread;
import com.delivery.appnotification.domain.ShopThreadSide;
import com.delivery.appnotification.service.ConversationClosedException;
import com.delivery.appnotification.service.RoomExceptions.OrderChatClosedException;
import com.delivery.appnotification.service.RoomExceptions.OrderUnavailableException;
import com.delivery.appnotification.service.RoomExceptions.RoomNotFoundException;
import com.delivery.appnotification.service.ShopChatService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Who may open, list, read and answer shop threads — every endpoint, every refusal.
 */
@DisplayName("shop thread endpoints")
class ShopChatAccessTest {

    private static final UUID STORE = UUID.randomUUID();
    private static final UUID ORDER = UUID.fromString("5f0c2a9e-1111-4222-8333-444455556666");
    private static final String CUSTOMER = "customer-sub";
    private static final String MERCHANT = "merchant-sub";

    private ShopChatService shops;
    private MockMvc mvc;
    private ChatShopThread thread;

    @BeforeEach
    void setUp() {
        shops = mock(ShopChatService.class);
        mvc = SecuredMvc.of(new ShopChatController(shops));
        thread = new ChatShopThread(STORE, CUSTOMER, "Tania K.", "Abu Hassan Mini Market",
                Instant.now().plus(Duration.ofDays(14)));
    }

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private RequestBuilder open() {
        return post("/api/chat/stores/" + STORE + "/thread");
    }

    private RequestBuilder openFromOrder() {
        return post("/api/chat/stores/" + STORE + "/thread").param("orderId", ORDER.toString());
    }

    private RequestBuilder openForOrder(UUID orderId) {
        return post("/api/chat/orders/" + orderId + "/shop-thread");
    }

    private RequestBuilder inbox() {
        return get("/api/chat/shop-threads/inbox");
    }

    private List<RequestBuilder> threadEndpoints() {
        String base = "/api/chat/shop-threads/" + thread.getId();
        return List.of(
                get(base + "/messages"),
                post(base + "/messages").contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"hello\"}"),
                post(base + "/read").contentType(MediaType.APPLICATION_JSON).content("{\"upToSequence\":3}"));
    }

    @Test
    @DisplayName("without a token, every endpoint is a 401")
    void no_token() throws Exception {
        mvc.perform(open()).andExpect(status().isUnauthorized());
        mvc.perform(openFromOrder()).andExpect(status().isUnauthorized());
        mvc.perform(openForOrder(ORDER)).andExpect(status().isUnauthorized());
        mvc.perform(inbox()).andExpect(status().isUnauthorized());
        for (RequestBuilder request : threadEndpoints()) {
            mvc.perform(request).andExpect(status().isUnauthorized());
        }
        verifyNoInteractions(shops);
    }

    @Test
    @DisplayName("only a CUSTOMER opens a thread with a shop; a merchant or rider is refused")
    void opening_is_for_customers() throws Exception {
        for (String role : List.of("MERCHANT", "RIDER", "BACKOFFICE")) {
            SecuredMvc.signedInAs("work-sub", role);
            mvc.perform(open()).andExpect(status().isForbidden());
            mvc.perform(openFromOrder()).andExpect(status().isForbidden());
        }
        verifyNoInteractions(shops);

        SecuredMvc.signedInAs(CUSTOMER, Map.of("given_name", "Tania", "family_name", "Khoury"), "CUSTOMER");
        when(shops.openForCustomer(STORE, CUSTOMER, "Tania K.", null))
                .thenReturn(new ShopChatService.ThreadState(thread, ShopThreadSide.CUSTOMER, 0L, null));

        mvc.perform(open())
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(thread.getId().toString()))
                .andExpect(jsonPath("$.yourSide").value("CUSTOMER"))
                .andExpect(jsonPath("$.open").value(true))
                .andExpect(jsonPath("$.orderId").doesNotExist());
    }

    @Test
    @DisplayName("opened from an order, the customer's own thread is asked for with that order, and shows its label")
    void opening_from_an_order() throws Exception {
        SecuredMvc.signedInAs(CUSTOMER, "CUSTOMER");
        thread.attachOrder(ORDER, "SERVICE");
        when(shops.openForCustomer(STORE, CUSTOMER, null, ORDER))
                .thenReturn(new ShopChatService.ThreadState(thread, ShopThreadSide.CUSTOMER, 0L, null));

        mvc.perform(openFromOrder())
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.orderId").value(ORDER.toString()))
                .andExpect(jsonPath("$.orderShortId").value("5f0c2a9e"))
                .andExpect(jsonPath("$.orderKind").value("SERVICE"));
        verify(shops).openForCustomer(STORE, CUSTOMER, null, ORDER);
    }

    @Test
    @DisplayName("an order that is not the customer's for this shop is refused byte for byte as an unknown shop")
    void a_refused_order_reads_as_an_unknown_shop() throws Exception {
        SecuredMvc.signedInAs(CUSTOMER, "CUSTOMER");
        when(shops.openForCustomer(eq(STORE), eq(CUSTOMER), any(), any()))
                .thenThrow(new RoomNotFoundException(STORE));

        String fromTheOrder = mvc.perform(openFromOrder())
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();
        String unknownShop = mvc.perform(open())
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        assertThat(fromTheOrder).isEqualTo(unknownShop);
    }

    @Test
    @DisplayName("with orders unreachable, opening from an order is a 503")
    void opening_from_an_order_while_orders_are_down() throws Exception {
        SecuredMvc.signedInAs(CUSTOMER, "CUSTOMER");
        when(shops.openForCustomer(STORE, CUSTOMER, null, ORDER))
                .thenThrow(new OrderUnavailableException("Orders cannot be checked right now", null));

        mvc.perform(openFromOrder()).andExpect(status().isServiceUnavailable());
    }

    @Test
    @DisplayName("only a MERCHANT opens a thread for an order; customers, riders, carriers and Backoffice are refused")
    void opening_for_an_order_is_for_merchants() throws Exception {
        for (String role : List.of("CUSTOMER", "RIDER", "CARRIER", "BACKOFFICE")) {
            SecuredMvc.signedInAs("someone-sub", role);
            mvc.perform(openForOrder(ORDER)).andExpect(status().isForbidden());
        }
        verifyNoInteractions(shops);
    }

    @Test
    @DisplayName("a merchant gets the thread for an order as the shop, labelled with the order, and never a user id")
    void a_merchant_opens_for_an_order() throws Exception {
        SecuredMvc.signedInAs(MERCHANT, "MERCHANT");
        thread.attachOrder(ORDER, "SERVICE");
        when(shops.openForOrder(ORDER, MERCHANT))
                .thenReturn(new ShopChatService.ThreadState(thread, ShopThreadSide.SHOP, 1L, null));

        mvc.perform(openForOrder(ORDER))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.yourSide").value("SHOP"))
                .andExpect(jsonPath("$.customerName").value("Tania K."))
                .andExpect(jsonPath("$.orderId").value(ORDER.toString()))
                .andExpect(jsonPath("$.orderShortId").value("5f0c2a9e"))
                .andExpect(jsonPath("$.orderKind").value("SERVICE"))
                .andExpect(jsonPath("$.customerId").doesNotExist())
                .andExpect(content().string(not(containsString(CUSTOMER))));
        verify(shops).openForOrder(ORDER, MERCHANT);
    }

    @Test
    @DisplayName("for an order: not the merchant's is a 404, past its window a 409 with when it closed, unreachable a 503")
    void refusals_for_an_order() throws Exception {
        SecuredMvc.signedInAs(MERCHANT, "MERCHANT");
        UUID notTheirs = UUID.randomUUID();
        UUID longDone = UUID.randomUUID();
        UUID unknowable = UUID.randomUUID();
        when(shops.openForOrder(notTheirs, MERCHANT)).thenThrow(new RoomNotFoundException(notTheirs));
        when(shops.openForOrder(longDone, MERCHANT))
                .thenThrow(new OrderChatClosedException(longDone, Instant.parse("2026-09-01T10:00:00Z")));
        when(shops.openForOrder(unknowable, MERCHANT))
                .thenThrow(new OrderUnavailableException("Orders cannot be checked right now", null));

        mvc.perform(openForOrder(notTheirs)).andExpect(status().isNotFound());
        mvc.perform(openForOrder(longDone))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.title").value("Order chat closed"))
                // Present, not its format: this standalone MockMvc writes instants as epoch seconds,
                // where Spring Boot's mapper writes ISO-8601, as for every instant this service returns.
                .andExpect(jsonPath("$.closedAt").exists());
        mvc.perform(openForOrder(unknowable)).andExpect(status().isServiceUnavailable());
    }

    @Test
    @DisplayName("only a MERCHANT has an inbox, and it is asked for as the token's subject")
    void the_inbox_is_for_merchants() throws Exception {
        for (String role : List.of("CUSTOMER", "RIDER", "BACKOFFICE")) {
            SecuredMvc.signedInAs("someone-sub", role);
            mvc.perform(inbox()).andExpect(status().isForbidden());
        }
        verifyNoInteractions(shops);

        SecuredMvc.signedInAs(MERCHANT, "MERCHANT");
        thread.attachOrder(ORDER, "SERVICE");
        when(shops.inbox(MERCHANT)).thenReturn(List.of(
                new ShopChatService.ThreadState(thread, ShopThreadSide.SHOP, 2L, null)));

        mvc.perform(inbox())
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].customerName").value("Tania K."))
                .andExpect(jsonPath("$[0].unread").value(2))
                .andExpect(jsonPath("$[0].orderShortId").value("5f0c2a9e"))
                .andExpect(jsonPath("$[0].orderKind").value("SERVICE"))
                .andExpect(jsonPath("$[0].customerId").doesNotExist())
                .andExpect(content().string(not(containsString(CUSTOMER))));
    }

    @Test
    @DisplayName("riders, carriers and Backoffice cannot read or post in a shop thread")
    void other_roles_are_refused_on_threads() throws Exception {
        for (String role : List.of("RIDER", "CARRIER", "BACKOFFICE")) {
            SecuredMvc.signedInAs("someone-sub", role);
            for (RequestBuilder request : threadEndpoints()) {
                mvc.perform(request).andExpect(status().isForbidden());
            }
        }
        verifyNoInteractions(shops);
    }

    @Test
    @DisplayName("a customer reads as a customer and a merchant as a merchant — the flag comes from the token")
    void the_merchant_flag_comes_from_the_token() throws Exception {
        thread.attachOrder(ORDER, "SERVICE");
        ShopChatService.ThreadPage page = new ShopChatService.ThreadPage(
                new ShopChatService.ThreadState(thread, ShopThreadSide.CUSTOMER, 0L, null), List.of(), false);
        when(shops.history(eq(thread.getId()), anyString(), anyBoolean(), anyLong())).thenReturn(page);

        SecuredMvc.signedInAs(CUSTOMER, "CUSTOMER");
        mvc.perform(get("/api/chat/shop-threads/" + thread.getId() + "/messages")).andExpect(status().isOk());
        verify(shops).history(thread.getId(), CUSTOMER, false, 0L);

        SecuredMvc.signedInAs(MERCHANT, "MERCHANT");
        mvc.perform(get("/api/chat/shop-threads/" + thread.getId() + "/messages"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.thread.orderKind").value("SERVICE"))
                .andExpect(content().string(not(containsString(CUSTOMER))));
        verify(shops).history(thread.getId(), MERCHANT, true, 0L);
    }

    @Test
    @DisplayName("somebody else's thread is a 404, the same as no thread at all")
    void not_your_thread_is_a_404() throws Exception {
        SecuredMvc.signedInAs("other-customer-sub", "CUSTOMER");
        when(shops.history(eq(thread.getId()), eq("other-customer-sub"), eq(false), anyLong()))
                .thenThrow(new RoomNotFoundException(thread.getId()));
        when(shops.post(eq(thread.getId()), eq("other-customer-sub"), eq(false), anyString(), any(), any()))
                .thenThrow(new RoomNotFoundException(thread.getId()));

        mvc.perform(get("/api/chat/shop-threads/" + thread.getId() + "/messages"))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/chat/shop-threads/" + thread.getId() + "/messages")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"hello\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("posting into an idle thread is a 409, and a post is a 201 with the stored message")
    void closed_and_posted() throws Exception {
        SecuredMvc.signedInAs(MERCHANT, "MERCHANT");
        when(shops.post(eq(thread.getId()), eq(MERCHANT), eq(true), eq("late reply"), any(), any()))
                .thenThrow(new ConversationClosedException(thread.getId(), Instant.now()));
        ChatShopMessage stored = new ChatShopMessage(thread.getId(), 4L, MERCHANT, ShopThreadSide.SHOP,
                "Yes, fresh today", "c-9", Instant.now());
        when(shops.post(eq(thread.getId()), eq(MERCHANT), eq(true), eq("Yes, fresh today"), eq("c-9"), any()))
                .thenReturn(new ShopChatService.Posted(stored, STORE));

        mvc.perform(post("/api/chat/shop-threads/" + thread.getId() + "/messages")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"text\":\"late reply\"}"))
                .andExpect(status().isConflict());
        mvc.perform(post("/api/chat/shop-threads/" + thread.getId() + "/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"text\":\"Yes, fresh today\",\"clientMessageId\":\"c-9\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.side").value("SHOP"))
                .andExpect(jsonPath("$.storeId").value(STORE.toString()))
                .andExpect(jsonPath("$.mine").value(true))
                .andExpect(jsonPath("$.senderId").doesNotExist());
    }
}

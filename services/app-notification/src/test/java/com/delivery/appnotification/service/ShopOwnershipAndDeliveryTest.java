package com.delivery.appnotification.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.delivery.appnotification.client.ProductDirectory;
import com.delivery.appnotification.domain.ChatShopMessage;
import com.delivery.appnotification.domain.ChatStoreOwner;
import com.delivery.appnotification.domain.ChatStoreOwnerRepository;
import com.delivery.appnotification.domain.ShopThreadSide;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Who answers for a shop, and who a shop-thread frame reaches.
 */
class ShopOwnershipAndDeliveryTest {

    private static final UUID STORE = UUID.randomUUID();
    private static final String MERCHANT = "merchant-sub";
    private static final String FORMER_OWNER = "former-owner-sub";
    private static final String CUSTOMER = "customer-sub";

    private ProductDirectory directory;
    private ChatStoreOwnerRepository owners;
    private ShopOwnership ownership;

    @BeforeEach
    void setUp() {
        directory = mock(ProductDirectory.class);
        owners = mock(ChatStoreOwnerRepository.class);
        ownership = new ShopOwnership(directory, owners, new ShopChatProperties());
    }

    @Nested
    @DisplayName("ownership")
    class Ownership {

        @Test
        @DisplayName("trusts a confirmation minutes old, for the merchant it names, without asking again")
        void a_fresh_confirmation_is_trusted() {
            when(owners.findById(STORE)).thenReturn(Optional.of(
                    new ChatStoreOwner(STORE, MERCHANT, Instant.now().minus(Duration.ofMinutes(2)))));

            assertThat(ownership.owns(MERCHANT, STORE)).isTrue();
            verifyNoInteractions(directory);
        }

        @Test
        @DisplayName("asks Product Service again once the confirmation is stale, and records the answer")
        void a_stale_confirmation_is_rechecked() {
            when(owners.findById(STORE)).thenReturn(Optional.of(
                    new ChatStoreOwner(STORE, MERCHANT, Instant.now().minus(Duration.ofHours(1)))));
            when(directory.storesOwnedByCaller()).thenReturn(Set.of(STORE));

            assertThat(ownership.owns(MERCHANT, STORE)).isTrue();
            verify(owners).confirm(eq(STORE), eq(MERCHANT), any(Instant.class));
        }

        /** A cached row for somebody else must never answer "yes" for this caller. */
        @Test
        @DisplayName("never lets a confirmation for one merchant vouch for another")
        void another_merchants_confirmation_does_not_count() {
            when(owners.findById(STORE)).thenReturn(Optional.of(
                    new ChatStoreOwner(STORE, FORMER_OWNER, Instant.now())));
            when(directory.storesOwnedByCaller()).thenReturn(Set.of());

            assertThat(ownership.owns(MERCHANT, STORE)).isFalse();
            verify(owners, never()).confirm(any(), any(), any());
        }
    }

    @Nested
    @DisplayName("live delivery")
    class Delivery {

        private SimpMessagingTemplate websocket;
        private ShopDelivery delivery;

        @BeforeEach
        void setUp() {
            websocket = mock(SimpMessagingTemplate.class);
            delivery = new ShopDelivery(websocket, ownership);
        }

        @Test
        @DisplayName("sends a customer's message to the shop's confirmed owner")
        void customer_to_shop() {
            when(owners.findById(STORE)).thenReturn(Optional.of(new ChatStoreOwner(STORE, MERCHANT, Instant.now())));
            ChatShopMessage message = new ChatShopMessage(UUID.randomUUID(), 1L, CUSTOMER,
                    ShopThreadSide.CUSTOMER, "Do you have halloumi?", null, Instant.now());

            delivery.deliver(message, STORE, CUSTOMER);

            ArgumentCaptor<ShopMessageView> frame = ArgumentCaptor.forClass(ShopMessageView.class);
            verify(websocket).convertAndSendToUser(eq(MERCHANT), eq(ShopDelivery.SHOP_DESTINATION), frame.capture());
            assertThat(frame.getValue().side()).isEqualTo("CUSTOMER");
            assertThat(frame.getValue().mine()).isFalse();
            assertThat(frame.getValue().storeId()).isEqualTo(STORE);
        }

        /**
         * A confirmation an hour old may name somebody who has sold the shop since. Pushing to them
         * would give a former owner every new message the moment it is written.
         */
        @Test
        @DisplayName("sends nothing live on a stale confirmation, which may name a former owner")
        void a_stale_owner_gets_no_frame() {
            when(owners.findById(STORE)).thenReturn(Optional.of(
                    new ChatStoreOwner(STORE, FORMER_OWNER, Instant.now().minus(Duration.ofHours(1)))));
            ChatShopMessage message = new ChatShopMessage(UUID.randomUUID(), 1L, CUSTOMER,
                    ShopThreadSide.CUSTOMER, "My address is 12 Armenia Street", null, Instant.now());

            delivery.deliver(message, STORE, CUSTOMER);

            verifyNoInteractions(websocket);
        }

        @Test
        @DisplayName("sends nothing live when no owner has been confirmed; the inbox shows it")
        void no_owner_no_frame() {
            when(owners.findById(STORE)).thenReturn(Optional.empty());
            ChatShopMessage message = new ChatShopMessage(UUID.randomUUID(), 1L, CUSTOMER,
                    ShopThreadSide.CUSTOMER, "hello", null, Instant.now());

            delivery.deliver(message, STORE, CUSTOMER);

            verifyNoInteractions(websocket);
        }

        @Test
        @DisplayName("sends the shop's reply to the thread's customer")
        void shop_to_customer() {
            ChatShopMessage reply = new ChatShopMessage(UUID.randomUUID(), 2L, MERCHANT,
                    ShopThreadSide.SHOP, "Yes, fresh today", null, Instant.now());

            delivery.deliver(reply, STORE, CUSTOMER);

            verify(websocket).convertAndSendToUser(eq(CUSTOMER), eq(ShopDelivery.SHOP_DESTINATION), any());
            verifyNoInteractions(owners);
        }
    }
}

package com.delivery.whatsapp.domain;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;

import org.junit.jupiter.api.Test;

/**
 * The inbox behaviours a merchant actually notices.
 */
class ConversationTest {

    private static final String SHOP = "merchant-a";
    private static final String CUSTOMER = "96171234567";
    private static final String NUMBER = "PN-1";

    private Conversation conversation() {
        return new Conversation(SHOP, CUSTOMER, "Rana", NUMBER);
    }

    @Test
    void aNewConversationHasNothingUnreadUntilSomebodySpeaks() {
        Conversation conversation = conversation();

        assertThat(conversation.getUnreadCount()).isZero();
        assertThat(conversation.isArchived()).isFalse();
    }

    @Test
    void eachInboundMessageAddsToTheBadge() {
        Conversation conversation = conversation();

        conversation.customerSpoke(Instant.now(), "Rana", NUMBER);
        conversation.customerSpoke(Instant.now(), "Rana", NUMBER);

        assertThat(conversation.getUnreadCount()).isEqualTo(2);
    }

    @Test
    void ourOwnReplyDoesNotMakeItLookUnanswered() {
        Conversation conversation = conversation();
        conversation.customerSpoke(Instant.now(), "Rana", NUMBER);
        conversation.markRead();

        Instant when = Instant.now().plusSeconds(60);
        conversation.weReplied(when);

        // It moves up the list, because something happened — but a merchant's own message is not
        // something waiting for them.
        assertThat(conversation.getLastMessageAt()).isEqualTo(when);
        assertThat(conversation.getUnreadCount()).isZero();
    }

    @Test
    void aNewMessageUnArchivesIt() {
        Conversation conversation = conversation();
        conversation.archive();

        conversation.customerSpoke(Instant.now(), "Rana", NUMBER);

        // A merchant who tidied this away last week has a new question in front of them now.
        // Leaving it archived hides the one thing that changed.
        assertThat(conversation.isArchived()).isFalse();
        assertThat(conversation.getUnreadCount()).isEqualTo(1);
    }

    @Test
    void takesTheLatestNameTheCustomerIsUsing() {
        Conversation conversation = conversation();

        conversation.customerSpoke(Instant.now(), "Rana K.", NUMBER);

        assertThat(conversation.getCustomerName()).isEqualTo("Rana K.");
    }

    @Test
    void keepsTheOldNameWhenTheProviderReportsNone() {
        Conversation conversation = conversation();

        // Absent surprisingly often. Blanking a name we already had would make the inbox worse.
        conversation.customerSpoke(Instant.now(), null, NUMBER);
        conversation.customerSpoke(Instant.now(), "   ", NUMBER);

        assertThat(conversation.getCustomerName()).isEqualTo("Rana");
    }

    @Test
    void fallsBackToTheNumberWhenThereIsNoNameAtAll() {
        Conversation anonymous = new Conversation(SHOP, CUSTOMER, null, NUMBER);

        assertThat(anonymous.displayName()).isEqualTo(CUSTOMER);
    }

    @Test
    void repliesFollowWhicheverOfTheShopsNumbersTheyLastWroteTo() {
        Conversation conversation = conversation();

        conversation.customerSpoke(Instant.now(), "Rana", "PN-branch");

        // A shop with a branch line has two numbers. Answering on the one they are not looking at
        // is the same as not answering.
        assertThat(conversation.getPhoneNumberId()).isEqualTo("PN-branch");
    }

    @Test
    void keepsTheKnownNumberWhenACallbackCarriesNone() {
        Conversation conversation = conversation();

        conversation.customerSpoke(Instant.now(), "Rana", null);

        assertThat(conversation.getPhoneNumberId()).isEqualTo(NUMBER);
    }
}

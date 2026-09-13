package com.delivery.appnotification.service;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/** The knobs on customer-to-shop threads. Policy, gathered where it can be read together. */
@Component
@ConfigurationProperties(prefix = "delivery.chat.shop-threads")
public class ShopChatProperties {

    /**
     * How long after the customer's last activity a thread keeps accepting posts.
     *
     * <p>Two weeks. A question to a shop ("do you have halloumi on Friday?", later "can you set one
     * aside?") plays out over days, not the hours an order chat lives for; but a shop must not keep a
     * private line to a customer who stopped asking months ago. Only the customer restarts the clock
     * — see {@code ChatShopThread}.
     */
    private Duration idleCloseAfter = Duration.ofDays(14);

    private int historyPageSize = 100;

    private int inboxPageSize = 100;

    private Duration sendWindow = Duration.ofMinutes(1);

    /**
     * Messages one person may send per {@link #sendWindow} across all shop threads. Higher than a
     * room's limit because a shop answering a queue of customers legitimately types fast; still far
     * below anything a script would need.
     */
    private int maxMessagesPerWindow = 20;

    /**
     * How long Product Service's "this merchant owns this shop" is trusted before it is asked again.
     *
     * <p>Minutes, so a merchant working an inbox does not cost a cross-service call per message, and
     * so a shop that changes hands stops answering for its old owner within the same coffee break.
     */
    private Duration ownerConfirmationTtl = Duration.ofMinutes(10);

    public Duration getIdleCloseAfter() {
        return idleCloseAfter;
    }

    public void setIdleCloseAfter(Duration idleCloseAfter) {
        this.idleCloseAfter = idleCloseAfter;
    }

    public int getHistoryPageSize() {
        return historyPageSize;
    }

    public void setHistoryPageSize(int historyPageSize) {
        this.historyPageSize = historyPageSize;
    }

    public int getInboxPageSize() {
        return inboxPageSize;
    }

    public void setInboxPageSize(int inboxPageSize) {
        this.inboxPageSize = inboxPageSize;
    }

    public Duration getSendWindow() {
        return sendWindow;
    }

    public void setSendWindow(Duration sendWindow) {
        this.sendWindow = sendWindow;
    }

    public int getMaxMessagesPerWindow() {
        return maxMessagesPerWindow;
    }

    public void setMaxMessagesPerWindow(int maxMessagesPerWindow) {
        this.maxMessagesPerWindow = maxMessagesPerWindow;
    }

    public Duration getOwnerConfirmationTtl() {
        return ownerConfirmationTtl;
    }

    public void setOwnerConfirmationTtl(Duration ownerConfirmationTtl) {
        this.ownerConfirmationTtl = ownerConfirmationTtl;
    }
}

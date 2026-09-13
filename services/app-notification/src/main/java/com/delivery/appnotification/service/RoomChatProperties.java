package com.delivery.appnotification.service;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * The knobs on neighbourhood rooms, gathered for the same reason {@link ChatProperties} gathers order
 * chat's: they are policy a person may have to defend, not tuning.
 *
 * <p>A class of its own rather than more fields on {@code ChatProperties}, so that a change to room
 * policy cannot be mistaken in review for a change to the private two-party chat.
 */
@Component
@ConfigurationProperties(prefix = "delivery.chat.rooms")
public class RoomChatProperties {

    /**
     * How long a neighbour stays in a room before they may move to another.
     *
     * <p>The room follows the zone of the customer's delivery address, and that address is the
     * customer's own statement — nothing on the platform can prove where a person lives. What the
     * server can do is make that statement expensive to abuse: without a cooldown one account could
     * change its address and walk through every neighbourhood in the city in an afternoon, posting in
     * each. A week lets somebody who genuinely moved (or first picked the wrong area) settle, while
     * turning room-hopping into a campaign of months.
     */
    private Duration moveCooldown = Duration.ofDays(7);

    /** Messages per history page. A screen and a half on a phone. */
    private int historyPageSize = 50;

    /** The window the send rate limit counts over. */
    private Duration sendWindow = Duration.ofMinutes(1);

    /**
     * How many messages one person may post in {@link #sendWindow}, across every room.
     *
     * <p>Eight a minute is faster than anybody converses and slower than anybody floods: a neighbour
     * replying to three people in quick succession never meets it, a script pasting an advert into
     * the room meets it on the ninth line. Counted in the database rather than in memory, so a
     * restart or a second instance does not hand a spammer a fresh allowance.
     */
    private int maxMessagesPerWindow = 8;

    public Duration getMoveCooldown() {
        return moveCooldown;
    }

    public void setMoveCooldown(Duration moveCooldown) {
        this.moveCooldown = moveCooldown;
    }

    public int getHistoryPageSize() {
        return historyPageSize;
    }

    public void setHistoryPageSize(int historyPageSize) {
        this.historyPageSize = historyPageSize;
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
}

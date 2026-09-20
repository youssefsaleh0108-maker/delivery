package com.delivery.tracking.service;

import java.time.Duration;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import com.delivery.tracking.domain.OrderParticipantsRepository;

/**
 * Whether a checkout's rider has deliveries that are not this checkout's — once yes, yes until the
 * rider's orders here are finished.
 *
 * <p>The raw answer ({@link OrderParticipantsRepository#riderHasOtherLiveOrders}) turns back to no
 * the moment the rider hands over their last outside order: at somebody else's door, with the
 * rider's next fix a few metres from it. A customer watching the flag flip on the map, and the
 * marker that appears soon after, would learn roughly where that other customer lives. So it is
 * latched per (checkout, rider): the first time it is seen true it is remembered, and from then on
 * the map says yes whatever the query says. The rider leaves the map when their orders in the
 * checkout are finished, so nobody reads the latch after that; the TTL only reclaims the key.
 *
 * <p>Redis unreachable: yes. A "no" that might have been latched could be exactly the flip this
 * exists to hide, while a spurious "your rider has other deliveries" costs nothing.
 */
@Component
public class OtherDeliveriesLatch {

    private static final Logger log = LoggerFactory.getLogger(OtherDeliveriesLatch.class);

    static final String KEY_PREFIX = "delivery:tracking:checkout-map:other-deliveries:";

    private final OrderParticipantsRepository participants;
    private final StringRedisTemplate redis;
    private final Duration ttl;

    public OtherDeliveriesLatch(OrderParticipantsRepository participants,
                                StringRedisTemplate redis,
                                // Far longer than any delivery takes: the latch must outlast the
                                // rider's orders in the checkout, and nothing reads it after them.
                                @Value("${delivery.tracking.checkout-map.other-deliveries-latch-ttl:12h}")
                                Duration ttl) {
        this.participants = participants;
        this.redis = redis;
        this.ttl = ttl;
    }

    /** Whether this rider of this checkout has, at any point it was asked, had other deliveries. */
    public boolean hasOtherDeliveries(UUID checkoutId, String riderId) {
        String key = KEY_PREFIX + checkoutId + ":" + riderId;
        boolean now = participants.riderHasOtherLiveOrders(riderId, checkoutId);
        try {
            if (now) {
                redis.opsForValue().set(key, "1", ttl);
                return true;
            }
            return Boolean.TRUE.equals(redis.hasKey(key));
        } catch (RuntimeException e) {
            log.warn("Could not read or write the checkout map's other-deliveries latch; "
                    + "answering yes rather than risk the flip it hides", e);
            return true;
        }
    }
}

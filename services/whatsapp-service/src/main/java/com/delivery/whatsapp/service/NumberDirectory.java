package com.delivery.whatsapp.service;

import java.util.List;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.whatsapp.domain.ConnectedNumber;
import com.delivery.whatsapp.repo.ConnectedNumberRepository;

/**
 * Who owns which number.
 *
 * <p>The routing table for the whole feature. Everything else depends on getting this right: an
 * incorrect answer here does not lose a message, it delivers one shop's customer to a different
 * shop.
 */
@Service
public class NumberDirectory {

    private static final Logger log = LoggerFactory.getLogger(NumberDirectory.class);

    private final ConnectedNumberRepository numbers;

    public NumberDirectory(ConnectedNumberRepository numbers) {
        this.numbers = numbers;
    }

    /** The merchant a message to this number belongs to, or empty if nobody has claimed it. */
    @Transactional(readOnly = true)
    public Optional<String> merchantFor(String phoneNumberId) {
        if (phoneNumberId == null || phoneNumberId.isBlank()) {
            return Optional.empty();
        }
        return numbers.findById(phoneNumberId).map(ConnectedNumber::getMerchantRef);
    }

    /**
     * Claims a number for a merchant.
     *
     * <p>Refuses one already claimed by someone else rather than reassigning it. Silently moving a
     * number would hand a competitor's live conversations — customers, phone numbers, order history
     * — to whoever claimed it second, and the request that did it would look like a success.
     *
     * @throws NumberAlreadyConnectedException if another merchant holds it
     */
    @Transactional
    public ConnectedNumber connect(String merchantRef, String phoneNumberId, String label,
                                   String displayNumber) {
        Optional<ConnectedNumber> existing = numbers.findById(phoneNumberId);
        if (existing.isPresent()) {
            ConnectedNumber current = existing.get();
            if (!current.belongsTo(merchantRef)) {
                log.warn("Merchant {} tried to connect number {}, already held by another merchant",
                        merchantRef, phoneNumberId);
                throw new NumberAlreadyConnectedException(
                        "That number is already connected to another shop");
            }
            // Their own number, connected again. Treated as an edit rather than an error: the
            // merchant is almost certainly fixing the label.
            current.rename(label, displayNumber);
            return numbers.save(current);
        }
        return numbers.save(new ConnectedNumber(phoneNumberId, merchantRef, label, displayNumber));
    }

    @Transactional(readOnly = true)
    public List<ConnectedNumber> of(String merchantRef) {
        return numbers.findByMerchantRefOrderByConnectedAtAsc(merchantRef);
    }

    /**
     * Releases a number.
     *
     * <p>Conversations survive. Disconnecting means "stop routing new messages here", not "delete
     * the history" — a merchant switching providers would otherwise lose every customer they have
     * ever spoken to, from a button labelled "disconnect".
     *
     * @return whether anything was released
     */
    @Transactional
    public boolean disconnect(String merchantRef, String phoneNumberId) {
        return numbers.findById(phoneNumberId)
                .filter(number -> number.belongsTo(merchantRef))
                .map(number -> {
                    numbers.delete(number);
                    return true;
                })
                .orElse(false);
    }

    /** Thrown when a merchant tries to claim a number another shop already holds. */
    public static class NumberAlreadyConnectedException extends RuntimeException {
        public NumberAlreadyConnectedException(String message) {
            super(message);
        }
    }
}

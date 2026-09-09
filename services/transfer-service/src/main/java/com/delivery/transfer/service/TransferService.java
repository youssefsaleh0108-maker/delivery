package com.delivery.transfer.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.client.OrderManagerClient;
import com.delivery.transfer.connector.ConnectorRegistry;
import com.delivery.transfer.connector.MoneyTransferConnector;
import com.delivery.transfer.domain.Money;
import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.MoneyTransferRepository;
import com.delivery.transfer.domain.TransferMethod;

/**
 * The transfer manager: quotes, records, and hands to a connector.
 *
 * <p>The platform rate lives HERE because this service is the one that promises it. A quote locks
 * today's rate into the numbers the customer approves, and initiate re-derives nothing — it
 * stores exactly the approved split with the rate that produced it. The market/config endpoint
 * the storefront shows is display; this is the rate that binds.
 */
@Service
public class TransferService {

    private final MoneyTransferRepository transfers;
    private final ConnectorRegistry registry;
    private final OrderManagerClient orders;
    private final BigDecimal lbpPerUsd;
    private final BigDecimal riderChangeLimitLbp;

    public TransferService(MoneyTransferRepository transfers,
                           ConnectorRegistry registry,
                           OrderManagerClient orders,
                           // One platform-wide display-and-collection rate, operator-set. The same
                           // default the storefront's market config carries, on purpose.
                           @Value("${delivery.market.lbp-per-usd:90000}") BigDecimal lbpPerUsd,
                           // How much lira change a rider is asked to carry. A promise printed on
                           // the checkout, so it comes from config, not a client's imagination.
                           @Value("${delivery.transfer.rider-change-limit-lbp:100000}") BigDecimal riderChangeLimitLbp) {
        this.transfers = transfers;
        this.registry = registry;
        this.orders = orders;
        // Normalised once, here, so no caller has to care whether the operator wrote 90000 or
        // 90000.00 in config: every figure derived from the rate then has one shape.
        this.lbpPerUsd = Money.lbp(lbpPerUsd);
        this.riderChangeLimitLbp = Money.lbp(riderChangeLimitLbp);
    }

    public BigDecimal rate() {
        return lbpPerUsd;
    }

    public BigDecimal riderChangeLimitLbp() {
        return riderChangeLimitLbp;
    }

    public List<TransferMethod> availableMethods() {
        return registry.availableMethods();
    }

    /** A priced split: what the customer is asked to approve, and what initiate will store. */
    public record Quote(BigDecimal amountUsd, BigDecimal splitUsd, BigDecimal splitLbpInUsd,
                        BigDecimal lbpPerUsd, BigDecimal splitLbpFace) {
    }

    /**
     * The split arithmetic behind {@code POST /quote} — and, because initiate calls it too, the
     * money rules in one place so both endpoints answer the same way.
     *
     * <p>They did not: quote took any numbers at all and returned a 200 for a negative amount or a
     * USD part larger than the whole, which the POST behind it then refused with a 422. A quote
     * whose figures cannot be paid is worse than a refusal — the customer approves it and the
     * refusal arrives at the last screen.
     *
     * <p>Rounding comes before the checks, not after: the columns hold two decimals, so $0.001 is
     * $0.00 by the time it is stored and must be refused as the zero amount it becomes rather than
     * pass as positive and record an obligation for nothing.
     */
    public Quote quote(BigDecimal amountUsd, BigDecimal splitUsd) {
        BigDecimal amount = Money.usd(amountUsd);
        if (amount == null || amount.signum() <= 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "amountUsd must be positive");
        }
        BigDecimal usdPart = splitUsd == null ? amount : Money.usd(splitUsd);
        if (usdPart.signum() < 0 || usdPart.compareTo(amount) > 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "splitUsd must be between 0 and amountUsd");
        }
        BigDecimal lbpInUsd = amount.subtract(usdPart);
        return new Quote(amount, usdPart, lbpInUsd, lbpPerUsd,
                MoneyTransfer.lbpFaceOf(lbpInUsd, lbpPerUsd));
    }

    @Transactional
    public MoneyTransfer record(UUID orderId, String payerRef, TransferMethod method,
                                BigDecimal amountUsd, BigDecimal splitUsd) {
        Quote quote = quote(amountUsd, splitUsd);
        MoneyTransferConnector connector = registry.forMethod(method)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "No provider currently carries " + method));

        // Before anything is written: an order id is only a UUID until Order Manager says whose it
        // is. Unasked, this recorded an intent — and issued a connector reference — against orders
        // that existed nowhere, and let whoever recorded first lock the real customer out of
        // paying for their own order, since one order holds one intent.
        OrderManagerClient.OrderSummary order = orders.fetch(orderId);
        if (!payerRef.equals(order.customerId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your order");
        }

        // One payment intent per order: re-choosing a method before the rider leaves replaces the
        // old intent rather than stacking a second obligation on the same order.
        transfers.findByOrderId(orderId).ifPresent(existing -> {
            if (!existing.getPayerRef().equals(payerRef)) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your order");
            }
            transfers.delete(existing);
            transfers.flush();
        });

        MoneyTransfer transfer = new MoneyTransfer(
                orderId, payerRef, method, quote.amountUsd(), quote.splitUsd(),
                quote.splitLbpInUsd(), lbpPerUsd);
        connector.initiate(transfer);
        return transfers.save(transfer);
    }

    @Transactional(readOnly = true)
    public MoneyTransfer mineForOrder(UUID orderId, String payerRef) {
        MoneyTransfer transfer = transfers.findByOrderId(orderId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "No transfer for that order"));
        if (!transfer.getPayerRef().equals(payerRef)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not your order");
        }
        return transfer;
    }

    @Transactional(readOnly = true)
    public List<MoneyTransfer> mine(String payerRef, int limit) {
        return transfers.findByPayerRefOrderByCreatedAtDesc(
                payerRef, PageRequest.of(0, Math.min(limit, 100)));
    }
}

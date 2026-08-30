package com.delivery.transfer.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.connector.ConnectorRegistry;
import com.delivery.transfer.connector.MoneyTransferConnector;
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
    private final BigDecimal lbpPerUsd;
    private final BigDecimal riderChangeLimitLbp;

    public TransferService(MoneyTransferRepository transfers,
                           ConnectorRegistry registry,
                           // One platform-wide display-and-collection rate, operator-set. The same
                           // default the storefront's market config carries, on purpose.
                           @Value("${delivery.market.lbp-per-usd:90000}") BigDecimal lbpPerUsd,
                           // How much lira change a rider is asked to carry. A promise printed on
                           // the checkout, so it comes from config, not a client's imagination.
                           @Value("${delivery.transfer.rider-change-limit-lbp:100000}") BigDecimal riderChangeLimitLbp) {
        this.transfers = transfers;
        this.registry = registry;
        this.lbpPerUsd = lbpPerUsd;
        this.riderChangeLimitLbp = riderChangeLimitLbp;
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

    /** What a USD split leaves to pay in lira, at the locked rate, rounded to the 1,000 note. */
    public BigDecimal lbpFaceFor(BigDecimal usdPart) {
        return usdPart.multiply(lbpPerUsd)
                .divide(BigDecimal.valueOf(1000), 0, RoundingMode.HALF_UP)
                .multiply(BigDecimal.valueOf(1000));
    }

    @Transactional
    public MoneyTransfer record(UUID orderId, String payerRef, TransferMethod method,
                                BigDecimal amountUsd, BigDecimal splitUsd) {
        if (amountUsd == null || amountUsd.signum() <= 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "amountUsd must be positive");
        }
        BigDecimal usdPart = splitUsd == null ? amountUsd : splitUsd;
        if (usdPart.signum() < 0 || usdPart.compareTo(amountUsd) > 0) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "splitUsd must be between 0 and amountUsd");
        }
        MoneyTransferConnector connector = registry.forMethod(method)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "No provider currently carries " + method));

        BigDecimal lbpInUsd = amountUsd.subtract(usdPart);

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
                orderId, payerRef, method, amountUsd, usdPart, lbpInUsd, lbpPerUsd);
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

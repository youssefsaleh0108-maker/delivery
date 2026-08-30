package com.delivery.transfer.connector;

import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.TransferMethod;
import com.delivery.transfer.domain.TransferStatus;

/**
 * Cash at the door — the connector with no wire behind it.
 *
 * <p>Initiating cash is a bookkeeping act: the split and the locked rate are already on the row,
 * which is precisely what the rider flow needs to collect the right notes in each currency. It
 * goes straight to INITIATED (there is no provider to wait for) and completes when the delivery
 * flow confirms collection.
 */
@Component
@Order(10)
public class CashOnDeliveryConnector implements MoneyTransferConnector {

    @Override
    public String name() {
        return "cash";
    }

    @Override
    public boolean supports(TransferMethod method) {
        return method == TransferMethod.CASH_ON_DELIVERY;
    }

    @Override
    public boolean ready() {
        return true;
    }

    @Override
    public void initiate(MoneyTransfer transfer) {
        transfer.carriedBy(name(), null, TransferStatus.INITIATED);
    }
}

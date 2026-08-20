package com.delivery.platform.notifications;

import org.springframework.amqp.rabbit.annotation.RabbitListener;

/**
 * Consumes this worker's channel queue.
 *
 * <p>Thin on purpose — everything that could go wrong is handled inside
 * {@link WorkerDispatchService}, which never throws. A listener that let an exception escape would
 * have the broker redeliver, and a deterministic failure would then loop forever and block the
 * channel behind it.
 */
public class NotificationCommandListener {

    private final WorkerDispatchService dispatch;

    public NotificationCommandListener(WorkerDispatchService dispatch) {
        this.dispatch = dispatch;
    }

    @RabbitListener(queues = "#{workerChannelQueue.name}")
    public void onCommand(String payload) {
        dispatch.handle(payload);
    }
}

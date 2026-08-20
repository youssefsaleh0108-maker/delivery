package com.delivery.worker.sms;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The SMS channel (Section 7).
 *
 * <p>Consumes {@code notification.dispatch.sms} and nothing else. One worker per channel, each with
 * its own queue, so a wedged SMS route cannot delay an email — a single shared queue would put all
 * three channels behind whichever one is slowest.
 *
 * <p>Separate from the SMS connector because the two fail differently: this process does cheap
 * CPU-bound work and scales with message volume, while the connector blocks on a vendor whose
 * latency nobody here controls. Merged, you could only scale the pair.
 */
@SpringBootApplication
public class SmsWorkerApplication {

    public static void main(String[] args) {
        SpringApplication.run(SmsWorkerApplication.class, args);
    }
}

package com.delivery.worker.push;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The push channel (Section 7).
 *
 * <p>Consumes {@code notification.dispatch.push} and nothing else. Its own deployable for the same
 * reason as the other two workers: a bad release stops one channel rather than every channel at
 * once.
 */
@SpringBootApplication
public class PushWorkerApplication {

    public static void main(String[] args) {
        SpringApplication.run(PushWorkerApplication.class, args);
    }
}

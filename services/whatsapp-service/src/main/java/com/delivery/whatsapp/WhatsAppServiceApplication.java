package com.delivery.whatsapp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.retry.annotation.EnableRetry;

import com.delivery.whatsapp.config.WhatsAppProperties;

/**
 * WhatsApp ordering.
 *
 * <p>Almost every small shop in this market already takes orders on WhatsApp — a name, a voice note,
 * a dropped pin. Asking them to move to a portal is asking them to change how they work. This meets
 * them where they already are: the conversation stays on WhatsApp, and what the platform adds is the
 * part they do badly by hand — turning a message into a priced order with a rider attached.
 *
 * <p>The service owns conversations and drafts, and no orders at all. Placing one goes through Order
 * Manager exactly like an app order, so a WhatsApp order settles, dispatches and is tracked by the
 * same code as every other order rather than by a parallel implementation that would drift.
 */
@SpringBootApplication
@EnableRetry
@EnableConfigurationProperties(WhatsAppProperties.class)
public class WhatsAppServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(WhatsAppServiceApplication.class, args);
    }
}

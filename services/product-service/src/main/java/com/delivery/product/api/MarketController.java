package com.delivery.product.api;

import java.math.BigDecimal;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Market-wide display facts the clients render prices with — today, the LBP rate.
 *
 * <p>Every price in the platform is stored and settled in USD; the Lebanese market frames draw
 * each one twice — "$3.50 / 315,000 LBP" — and the second figure is a CONVERSION at one
 * platform-wide rate, not a second price anybody set. The design's own numbers are consistent
 * with exactly that (each LBP figure is the dollar figure at one rate, rounded to the thousand),
 * which is why this is a config value and not a column on products.
 *
 * <p>Served from the storefront service because every surface that shows a price already talks to
 * it. The rate comes from configuration (`delivery.market.lbp-per-usd`, bound to
 * `MARKET_LBP_PER_USD`) so an operator moves it without a build; zero means "do not show LBP at
 * all", which is also what a client that never managed to fetch this renders.
 *
 * <p>That key and that variable are the SAME ones transfer-service locks a checkout quote's rate
 * from — one rate for the whole platform, displayed here and charged there. The default below is
 * a last resort for a service started with no configuration at all, not the value the platform
 * runs on: while this service alone left the key unbound, moving the rate moved what checkout
 * collected and left every displayed lira figure at 90000.
 */
@RestController
@RequestMapping("/api/market")
public class MarketController {

    private final BigDecimal lbpPerUsd;

    public MarketController(
            @Value("${delivery.market.lbp-per-usd:90000}") BigDecimal lbpPerUsd) {
        this.lbpPerUsd = lbpPerUsd;
    }

    @GetMapping("/config")
    public Map<String, Object> config() {
        return Map.of("lbpPerUsd", lbpPerUsd);
    }
}

package com.delivery.corebanking.simulator.api;

import java.time.Duration;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.corebanking.simulator.service.FaultInjector;

/**
 * Turns the bank's misbehaviour on and off.
 *
 * <p>Under {@code /test/} rather than {@code /api/} so it is obvious at a glance in a route table
 * and in an access log that this is not part of the bank's contract. Nothing in the platform calls
 * it; only a human or a smoke test does.
 *
 * <p>It is safe for it to be unauthenticated for the same reason the rest of this service is: the
 * simulator only ever exists in dev, is not routed by the API Gateway, and holds no real money. If
 * this service ever appears in an environment where that is not true, the deployment is the bug.
 */
@RestController
@RequestMapping("/test/faults")
public class FaultInjectionController {

    private final FaultInjector faults;

    public FaultInjectionController(FaultInjector faults) {
        this.faults = faults;
    }

    @GetMapping
    public Map<String, Object> current() {
        return Map.of(
                "enabled", faults.isEnabled(),
                "mode", faults.mode().name(),
                "latencyMs", faults.latency().toMillis());
    }

    @PostMapping
    public ResponseEntity<Map<String, Object>> set(@RequestBody FaultRequest request) {
        if (!faults.isEnabled()) {
            // Explicit rather than a silent no-op: a test that thinks it broke the bank and did
            // not would then assert the happy path and pass for the wrong reason.
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("error", "fault injection is disabled in this environment"));
        }

        faults.set(
                request.mode() == null ? FaultInjector.Mode.HEALTHY : request.mode(),
                Duration.ofMillis(request.latencyMs()),
                request.callCount());
        return ResponseEntity.ok(current());
    }

    /**
     * @param callCount how many calls the fault survives; 0 keeps it until reset. Prefer a count —
     *                  a fault that expires itself cannot leak into whatever runs next.
     */
    public record FaultRequest(FaultInjector.Mode mode, long latencyMs, int callCount) {
    }
}

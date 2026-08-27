package com.delivery.tracking.api;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.service.EtaService;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.TrackingService;
import com.delivery.tracking.service.TrackingService.Position;
import com.delivery.tracking.service.TrackingService.TrackingNotFoundException;

@RestController
@RequestMapping("/api/tracking")
public class TrackingController {

    private final TrackingService tracking;
    private final EtaService eta;

    public TrackingController(TrackingService tracking, EtaService eta) {
        this.tracking = tracking;
        this.eta = eta;
    }

    /**
     * A rider reports their position.
     *
     * <p>Called every few seconds per active rider — the highest-frequency write in the platform.
     * Returns 202 rather than a body: the client has nothing to do with the response, and keeping
     * it empty keeps the payload off the mobile data plan.
     */
    @PostMapping("/orders/{orderId}/ping")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<Void> ping(@PathVariable UUID orderId,
                                     @Valid @RequestBody PingRequest request) {
        tracking.ping(orderId, CurrentUser.requireId(),
                request.lat(), request.lng(), request.accuracyM());
        return ResponseEntity.accepted().build();
    }

    /** "Where is my rider right now" — served from Redis. */
    @GetMapping("/orders/{orderId}")
    public ResponseEntity<PositionResponse> current(@PathVariable UUID orderId) {
        return tracking.currentPosition(orderId, CurrentUser.requireId(), isBackoffice())
                .map(TrackingController::toResponse)
                .map(ResponseEntity::ok)
                // 204: the order exists and you may see it, but the rider has not pinged yet.
                // Distinct from 404, which means the order is unknown or not yours.
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    /**
     * How far the rider still has to go, and when they are expected.
     *
     * <p>Always 200 with a body, never 204, because the interesting cases here are the ones with no
     * number in them. A screen that got an empty response could only show a spinner; a body saying
     * {@code available: false, reason: NO_FIX} lets it say "waiting for the rider's first GPS fix",
     * which is true and is what the customer wants to know. The reasons are enumerated in
     * {@link EtaService.Reason}.
     *
     * <p>Authorisation is identical to the live position — customer, merchant or assigned rider, or
     * backoffice — and is applied before any of those reasons can be observed.
     *
     * <p>{@code provider} is on every response, including the unavailable ones. Until a routing key
     * is provisioned it reads {@code HAVERSINE_DEV}, which is the dev straight-line estimator, and
     * a client is expected to show that number with rather less confidence than a routed one.
     */
    @GetMapping("/orders/{orderId}/eta")
    public EtaResult eta(@PathVariable UUID orderId) {
        return eta.estimateFor(orderId, CurrentUser.requireId(), isBackoffice());
    }

    @GetMapping("/orders/{orderId}/history")
    public List<PositionResponse> history(@PathVariable UUID orderId) {
        return tracking.history(orderId, CurrentUser.requireId(), isBackoffice()).stream()
                .map(TrackingController::toResponse)
                .toList();
    }

    private static boolean isBackoffice() {
        return CurrentUser.hasRole("BACKOFFICE");
    }

    private static PositionResponse toResponse(Position p) {
        return new PositionResponse(p.orderId(), p.riderId(), p.lat(), p.lng(),
                p.accuracyM(), p.recordedAt());
    }

    @ExceptionHandler(TrackingNotFoundException.class)
    public ProblemDetail onNotFound(TrackingNotFoundException e) {
        return TrackingProblems.of(HttpStatus.NOT_FOUND, "Tracking not found", e.getMessage());
    }

    public record PingRequest(
            @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng,
            Float accuracyM) {
    }

    public record PositionResponse(
            UUID orderId,
            String riderId,
            double lat,
            double lng,
            Float accuracyM,
            Instant recordedAt) {
    }
}

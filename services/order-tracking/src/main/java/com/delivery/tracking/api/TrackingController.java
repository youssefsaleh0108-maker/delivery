package com.delivery.tracking.api;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

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

import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.service.EtaService;
import com.delivery.tracking.service.EtaService.EtaResult;
import com.delivery.tracking.service.Fix;
import com.delivery.tracking.service.RiderSighting;
import com.delivery.tracking.service.TrackingService;
import com.delivery.tracking.service.TrackingService.Position;
import com.delivery.tracking.service.TrackingService.TrackingClosedException;
import com.delivery.tracking.service.TrackingService.TrackingNotFoundException;

@RestController
@RequestMapping("/api/tracking")
public class TrackingController {

    private final TrackingService tracking;
    private final EtaService eta;
    private final SimpMessagingTemplate live;

    public TrackingController(TrackingService tracking, EtaService eta,
                              SimpMessagingTemplate live) {
        this.tracking = tracking;
        this.eta = eta;
        this.live = live;
    }

    /**
     * A rider reports their position.
     *
     * <p>Called every few seconds per active rider — the highest-frequency write in the platform.
     * Returns 202 rather than a body: the client has nothing to do with the response, and keeping
     * it empty keeps the payload off the mobile data plan.
     *
     * <p>Refusals are mapped in {@link PingProblems}: 422 with a {@code reason} for a fix that is
     * not believable, 401/403 for a caller who is not a signed-in rider. A fix that adds nothing
     * new — not newer than the rider's last one, or too soon after it — is also answered 202, and
     * is neither recorded nor pushed: the handset did nothing wrong and has nothing to change.
     */
    @PostMapping("/orders/{orderId}/ping")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<Void> ping(@PathVariable UUID orderId,
                                     @Valid @RequestBody PingRequest request) {
        tracking.ping(orderId, PingProblems.rider(), request.fix())
                // The topic reaches the order's customer (the shop may not subscribe), so it only
                // carries a fix the customer may see — TrackingService#sightingFor, applied to it.
                .filter(TrackingService.Recorded::live)
                .ifPresent(recorded -> {
                    Position p = recorded.position();
                    // The live push. Fire-and-forget by design: the position is already durable,
                    // and a subscriber that misses this frame gets it on its next read.
                    live.convertAndSend("/topic/orders/" + orderId + "/position",
                            new LiveFrame(p.orderId(), p.riderId(), p.lat(), p.lng(),
                                    p.accuracyM(), p.recordedAt(), recorded.onTrail()));
                });
        return ResponseEntity.accepted().build();
    }

    /**
     * "Where is my rider right now", as the rider-visibility rule allows it.
     *
     * <p>200 with the position when the caller may see the rider; 204 when there is nothing they
     * may see — no fix yet, or a position the rule withholds from them. {@code GET .../rider} says
     * which. Distinct from 404, which means the order is unknown or not yours.
     */
    @GetMapping("/orders/{orderId}")
    public ResponseEntity<PositionResponse> current(@PathVariable UUID orderId) {
        return tracking.currentPosition(orderId, CurrentUser.requireId(), isBackoffice())
                .map(TrackingController::toResponse)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    /**
     * What the caller may know of where the rider is, and why when it is not a position:
     * {@code VISIBLE} with the position, or {@code HEADING_TO_SHOP}, {@code ON_ANOTHER_DELIVERY},
     * {@code AFTER_PICKUP}, {@code NO_FIX} or {@code CLOSED} with none (see
     * {@link com.delivery.tracking.service.RiderSighting.State}). Always 200 with a body, like the
     * ETA, because the states without a position are the ones a screen has to put into words.
     */
    @GetMapping("/orders/{orderId}/rider")
    public SightingResponse rider(@PathVariable UUID orderId) {
        RiderSighting sighting = tracking.sightingFor(orderId, CurrentUser.requireId(),
                isBackoffice());
        return new SightingResponse(orderId, sighting.state().name(),
                sighting.shown().map(TrackingController::toResponse).orElse(null));
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

    /**
     * The trail: all of it for the back office and the rider; for the customer only from pickup,
     * only while the order is live and the rider visible to them, and without the points at other
     * customers' doors; none for the shop. See {@link TrackingService#history}.
     */
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

    /**
     * 409, not 404 and not a silent 202. The rider's app is entitled to learn that its pings are
     * being dropped so it can stop sending them; an accepted response would keep a finished
     * delivery's ping queue draining for as long as the handset stayed awake, and a 404 would
     * claim the rider's own delivery had vanished.
     */
    @ExceptionHandler(TrackingClosedException.class)
    public ProblemDetail onClosed(TrackingClosedException e) {
        return TrackingProblems.of(HttpStatus.CONFLICT, "Delivery complete", e.getMessage());
    }

    /**
     * @param accuracyM  the handset's radius of uncertainty in metres; optional, as it always was,
     *                   but never negative
     * @param recordedAt when the phone took the fix, by its own clock (ISO-8601). Required: a body
     *                   without it is well formed, so it is not a 400, and is refused with a 422 and
     *                   {@code reason: FIX_TIME_MISSING} (see {@link com.delivery.tracking.service.FixPolicy}).
     *                   App builds that predate the field swallow ping errors, so refusing their
     *                   simulated London positions changes nothing a rider sees
     */
    public record PingRequest(
            @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng,
            @PositiveOrZero Float accuracyM,
            Instant recordedAt) {

        Fix fix() {
            return new Fix(lat, lng, accuracyM, recordedAt);
        }
    }

    public record PositionResponse(
            UUID orderId,
            String riderId,
            double lat,
            double lng,
            Float accuracyM,
            Instant recordedAt) {
    }

    /**
     * A frame on an order's live topic: the position, and whether it is on the trail. A fix on an
     * order not yet collected moves the rider's dot and is never part of the trail, so a map must
     * not draw a line through it.
     */
    public record LiveFrame(
            UUID orderId,
            String riderId,
            double lat,
            double lng,
            Float accuracyM,
            Instant recordedAt,
            boolean onTrail) {
    }

    /**
     * @param state    the {@link com.delivery.tracking.service.RiderSighting.State} name
     * @param position present exactly when {@code state} is {@code VISIBLE}
     */
    public record SightingResponse(UUID orderId, String state, PositionResponse position) {
    }
}

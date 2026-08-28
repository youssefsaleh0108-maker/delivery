package com.delivery.tracking.api;

import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.tracking.domain.DutyState;
import com.delivery.tracking.domain.RiderDutyEvent;
import com.delivery.tracking.service.DutySessionService;
import com.delivery.tracking.service.DutySessionService.HoursOnline;
import com.delivery.tracking.service.PresenceService;
import com.delivery.tracking.service.PresenceService.NoCarrierException;
import com.delivery.tracking.service.PresenceService.PresenceNotFoundException;
import com.delivery.tracking.service.PresenceService.RiderPresenceView;

/**
 * Duty, presence and rider location that is not attached to an order.
 *
 * <p>Separate from {@link TrackingController} because the subject is different. That controller
 * answers questions about a delivery; this one answers questions about a person, and the
 * authorisation rules are correspondingly tighter — see {@link PresenceService#locationOf}.
 *
 * <p>Every write path takes the rider id from the access token and none of them accept it in the
 * body or the path. The endpoints are literally {@code /riders/me/...} so there is no request shape
 * in which a rider names somebody else, which is a stronger guarantee than checking that they did
 * not: a check can be forgotten when a new endpoint is added, a missing parameter cannot.
 */
@RestController
@RequestMapping("/api/tracking/riders")
public class RiderPresenceController {

    private final PresenceService presence;
    private final DutySessionService dutySessions;

    public RiderPresenceController(PresenceService presence, DutySessionService dutySessions) {
        this.presence = presence;
        this.dutySessions = dutySessions;
    }

    /**
     * A rider reports where they are while holding no job.
     *
     * <p>The roster in the design shows online riders on a map, and a rider between deliveries is
     * exactly the one a dispatcher most wants to see. The order-scoped ping cannot serve this: it
     * requires an order id, and there isn't one.
     *
     * <p>202 with no body, matching the order ping, and for the same reason — the handset has
     * nothing to do with a response and this is the most frequently called route in the platform.
     *
     * <p>Nothing durable grows per call. The fix updates one row per rider in place; it is
     * deliberately not appended to a history table. See V12 for why an idle rider's trail is not
     * something this platform keeps.
     */
    @PostMapping("/me/ping")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<Void> ping(@Valid @RequestBody PingRequest request) {
        presence.recordFix(CurrentUser.requireId(),
                request.lat(), request.lng(), request.accuracyM());
        return ResponseEntity.accepted().build();
    }

    /**
     * A rider goes on or off duty.
     *
     * <p>Returns the resulting presence, including the effective state, so the app can show what
     * the platform actually thinks rather than assuming the tap worked. That distinction is real: a
     * rider who goes on duty before their phone has a GPS fix comes back {@code STALE}, and the app
     * should tell them so instead of showing them as available for work they will not receive.
     */
    @PostMapping("/me/duty")
    @PreAuthorize("hasRole('DELIVERY')")
    public RiderPresenceView setDuty(@Valid @RequestBody DutyRequest request) {
        return presence.declare(CurrentUser.requireId(), request.state(),
                RiderDutyEvent.Source.RIDER);
    }

    /** A rider's own state, for an app that has just been reopened. */
    @GetMapping("/me/duty")
    @PreAuthorize("hasRole('DELIVERY')")
    public ResponseEntity<RiderPresenceView> ownDuty() {
        return presence.ownPresence(CurrentUser.requireId())
                .map(ResponseEntity::ok)
                // 204: a rider who has never declared duty or pinged has no presence yet. Not an
                // error, and not an invented OFF_DUTY row either — nothing has happened.
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    /**
     * Where one rider is.
     *
     * <p>Open to any authenticated caller at the routing layer and then narrowed sharply in
     * {@link PresenceService#locationOf} — self, backoffice, the employing fleet, or a customer
     * with a live order in that rider's hands. A caller outside that set gets 404, identical to the
     * answer for a rider who does not exist, so the endpoint cannot be used to enumerate the fleet.
     *
     * <p>A role check here instead would be wrong: the four groups who may ask hold four different
     * roles, and three of them may only ask about particular riders.
     */
    @GetMapping("/{riderId}/location")
    public RiderPresenceView location(@PathVariable String riderId) {
        return presence.locationOf(riderId, CurrentUser.requireId(),
                CurrentUser.hasRole("BACKOFFICE"));
    }

    /**
     * The fleet roster the backoffice and carrier consoles poll.
     *
     * <p>A carrier's scope comes from their own membership row and the {@code carrierId} parameter
     * is ignored for them entirely — a carrier cannot name a company, so no request reads a
     * competitor's fleet. Backoffice may name one, and sees every fleet when they do not.
     *
     * <p>{@code onDutyOnly} filters on the declared state, not the effective one, and that is on
     * purpose: a rider who declared duty and then went quiet is precisely who a dispatcher needs to
     * see, and filtering them out would hide the problem. They come back marked {@code STALE}.
     */
    @GetMapping("/roster")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public List<RiderPresenceView> roster(
            @RequestParam(required = false) UUID carrierId,
            @RequestParam(defaultValue = "true") boolean onDutyOnly) {
        return presence.roster(CurrentUser.requireId(), CurrentUser.hasRole("BACKOFFICE"),
                carrierId, onDutyOnly);
    }

    /**
     * A rider's own hours online per day — the stat tile in the rider app.
     *
     * <p>DELIVERY only, and only ever about the caller: the id comes from the token and no request
     * shape names anybody else, same rule as every other {@code /me} route here.
     *
     * <p>{@code days} is capped at 30. The window is bounded because the query walks every session
     * in it; a rider wanting their quarter belongs in a payroll export, not a tile poll.
     */
    @GetMapping("/me/duty/hours")
    @PreAuthorize("hasRole('DELIVERY')")
    public HoursOnline ownHours(
            @RequestParam(defaultValue = "7") @Min(1) @Max(30) int days) {
        return dutySessions.ownHours(CurrentUser.requireId(), days);
    }

    /**
     * One rider's hours online per day — the hours column in the backoffice and carrier consoles.
     *
     * <p>BACKOFFICE may ask about any rider. CARRIER is scoped exactly as the roster is: their
     * fleet comes from their own membership row, never from the request, and the rider must belong
     * to that fleet by the same {@code rider_presence.carrier_id} linkage the roster filters on.
     * A rider outside that fleet — or an id that does not exist — gets the same 404, so this
     * endpoint cannot enumerate riders any more than the location one can.
     */
    @GetMapping("/{riderId}/duty/hours")
    @PreAuthorize("hasAnyRole('BACKOFFICE','CARRIER')")
    public HoursOnline riderHours(
            @PathVariable String riderId,
            @RequestParam(defaultValue = "7") @Min(1) @Max(30) int days) {
        return dutySessions.riderHours(riderId, CurrentUser.requireId(),
                CurrentUser.hasRole("BACKOFFICE"), days);
    }

    @ExceptionHandler(PresenceNotFoundException.class)
    public ProblemDetail onNotFound(PresenceNotFoundException e) {
        return TrackingProblems.of(HttpStatus.NOT_FOUND, "Rider not found", e.getMessage());
    }

    /**
     * 403 rather than 404: unlike the rider lookups above there is nothing to hide here. The caller
     * holds the CARRIER role and belongs to no fleet, which is a provisioning mistake, and telling
     * them so is the only way it gets fixed.
     */
    @ExceptionHandler(NoCarrierException.class)
    public ProblemDetail onNoCarrier(NoCarrierException e) {
        return TrackingProblems.of(HttpStatus.FORBIDDEN, "No delivery company", e.getMessage());
    }

    /** Same shape and same bounds as the order-scoped ping — one handset sends both. */
    public record PingRequest(
            @NotNull @DecimalMin("-90") @DecimalMax("90") Double lat,
            @NotNull @DecimalMin("-180") @DecimalMax("180") Double lng,
            Float accuracyM) {
    }

    /**
     * @param state ON_DUTY or OFF_DUTY. An unknown value is rejected by Jackson as a 400 rather
     *              than being coerced to a default — silently reading "ONDUTY" as off duty would
     *              take a working rider off the roster with no error anywhere.
     */
    public record DutyRequest(@NotNull DutyState state) {
    }
}

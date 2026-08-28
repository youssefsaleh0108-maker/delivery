package com.delivery.product.api;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.product.service.ThumbnailBackfillService;

/**
 * One-off: create the image derivatives that predate derivatives existing.
 *
 * <p>New uploads are thumbnailed on confirm. Everything already in the catalogue is not, and it
 * degrades to the full-size image — which is correct, and is also the three-second wait for an 80dp
 * square that thumbnails exist to remove. This is how an operator closes that gap once.
 *
 * <p>BACKOFFICE only. It is expensive by nature — every image in the catalogue read out of object
 * storage, decoded and re-encoded — so it must not be reachable by a merchant, and certainly not by
 * an unauthenticated caller who could turn it into an amplification attack against the platform's
 * own storage bill.
 *
 * <p>Synchronous, and that is deliberate for the size of catalogue this platform has: the caller
 * gets the counts rather than a job id and a polling endpoint to go with it. If the catalogue grows
 * to where the request times out, that is the signal to make it a job — not something to
 * pre-engineer now.
 */
@RestController
@RequestMapping("/api/admin/thumbnails")
public class ThumbnailBackfillController {

    private final ThumbnailBackfillService backfill;

    public ThumbnailBackfillController(ThumbnailBackfillService backfill) {
        this.backfill = backfill;
    }

    /**
     * @return how many images were looked at, how many gained a derivative, how many already had
     *         one, and how many could not be done — the last is the number worth reading, and it is
     *         reported rather than thrown so one unreadable image does not hide the other successes
     */
    @PostMapping("/backfill")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<ThumbnailBackfillService.Result> backfill() {
        return ResponseEntity.ok(backfill.run());
    }
}

package com.delivery.onboarding.api;

import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.PlatformClient;
import com.delivery.onboarding.service.HiringCompanies;

/**
 * Who is hiring riders, and where each company works — the list the rider wizard offers.
 *
 * <p>Order Manager has an open list of who is hiring too, with each company's zone names, and
 * installed copies of the app still read that one. This is the one the app reads now, because a
 * company with no zones shows the regions it registered with (owner, 2026-09), and only this service
 * holds those. Both this list and the region an application records come out of
 * {@link HiringCompanies}, so what a rider is shown is what their application is recorded with.
 */
@RestController
@RequestMapping("/api/onboarding")
public class HiringCompaniesController {

    private final HiringCompanies hiring;

    public HiringCompaniesController(HiringCompanies hiring) {
        this.hiring = hiring;
    }

    /**
     * The companies taking riders, each with an id, a name and its region.
     *
     * <p><strong>Open to anybody</strong> (it is on {@code delivery.security.permit-all}), and it has to
     * be: a rider chooses a company before they have an account, because applying is how they get one.
     * It names no person — company names and place names, both of which the companies advertise.
     * Being open to anybody is also why it is served from memory for half a minute at a time
     * ({@link HiringCompanies#FORM_FRESH_FOR}): each read is a call to Order Manager. The application
     * itself is judged against who is hiring at the moment it is sent.
     */
    @GetMapping("/hiring-companies")
    public List<HiringCompanies.Company> hiringCompanies() {
        return hiring.forTheForm();
    }

    /**
     * 503: Order Manager could not say who is hiring. The wizard says so in the reader's language and
     * offers a retry; riding for YouDrop needs no company and stays open meanwhile.
     */
    @ExceptionHandler(PlatformClient.CompaniesUnavailableException.class)
    public ResponseEntity<Map<String, String>> companiesUnavailable(
            PlatformClient.CompaniesUnavailableException e) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of(
                "message", e.getMessage(),
                "code", PlatformClient.CompaniesUnavailableException.CODE));
    }
}

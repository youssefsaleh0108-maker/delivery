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
import com.delivery.onboarding.service.ServiceProviderAnswers;

/**
 * What the services signup form (Figma 126:11) offers somebody applying to offer services.
 *
 * <p>A controller of its own because it is the one read on the open side of onboarding that is not
 * about an application: it answers the form's two pickers, the service category and the area, and
 * nothing else. The application itself goes through the endpoints every shop uses —
 * {@code POST /applications} for a stranger, {@code POST /applications/mine} for a signed-in account.
 */
@RestController
@RequestMapping("/api/onboarding")
public class ServiceSignupController {

    private final ServiceProviderAnswers answers;

    public ServiceSignupController(ServiceProviderAnswers answers) {
        this.answers = answers;
    }

    /** One area the form offers: a live delivery zone, by id and by name. */
    public record AreaOption(String zoneId, String name) {
    }

    /**
     * @param categories the open service categories, as wire names in taxonomy order
     * @param areas      the live delivery zones, in the order the zone picker lists them
     */
    public record ServiceOptions(List<String> categories, List<AreaOption> areas) {
    }

    /**
     * The categories open right now and the areas to choose from — the same two lists the intake
     * checks an application against, so the form cannot offer an answer the server would refuse.
     *
     * <p><strong>Open to anybody</strong> (it is on {@code delivery.security.permit-all}), and it has
     * to be: the open application form runs before the applicant has an account. It names no shop
     * and no person — a list of category names, and the zone names a customer's address picker
     * already shows. Product Service is asked on every call rather than cached here, because a
     * category opened there should be on the form at once, the way it is accepted at once.
     */
    @GetMapping("/service-options")
    public ServiceOptions options() {
        ServiceProviderAnswers.Options options = answers.options();
        return new ServiceOptions(options.categories(), options.areas().stream()
                .map(area -> new AreaOption(area.zoneId().toString(), area.name()))
                .toList());
    }

    /** 503: Product Service could not answer. The form offers a retry, in the reader's language. */
    @ExceptionHandler(PlatformClient.CatalogUnavailableException.class)
    public ResponseEntity<Map<String, String>> catalogUnavailable(
            PlatformClient.CatalogUnavailableException e) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of(
                "message", e.getMessage(),
                "code", PlatformClient.CatalogUnavailableException.CODE));
    }
}

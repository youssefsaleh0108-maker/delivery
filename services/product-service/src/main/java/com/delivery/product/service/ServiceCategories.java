package com.delivery.product.service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import com.delivery.product.domain.Store.ServiceCategory;

/**
 * Which service categories are open: offered to a provider setting up a shop, and shown to customers
 * wherever service shops are listed.
 *
 * <p>The taxonomy is {@link ServiceCategory}; this is the switch. At launch Printing, Tailoring,
 * Repairs and Photography are open. Cleaning, Beauty and Tutoring are appointments at the customer's
 * place, which the order flow (make it, then collect or deliver it) does not model, so they stay
 * closed until it does (owner default 1, docs/figma-services-designs.md).
 *
 * <p>A closed category can neither be chosen for a shop nor shown in a list. A shop that chose it
 * while it was open keeps its category and simply stops being listed. Closing a category and opening
 * it again therefore loses nothing, and closing one never has to rewrite a shop.
 *
 * <p>Read per call from the {@link Environment}, exactly as {@code GeocodingProviders} reads its
 * provider and for the same reason: a Config Server change plus {@code /actuator/busrefresh} opens a
 * category without a redeploy, which a value captured at startup would not.
 */
@Component
public class ServiceCategories {

    static final String PROPERTY = "delivery.product.services.enabled-categories";

    /** What is open when nothing is configured: the four launch categories. */
    static final Set<ServiceCategory> LAUNCH = Collections.unmodifiableSet(EnumSet.of(
            ServiceCategory.PRINTING, ServiceCategory.TAILORING, ServiceCategory.REPAIRS,
            ServiceCategory.PHOTOGRAPHY));

    private final Environment environment;

    public ServiceCategories(Environment environment) {
        this.environment = environment;
    }

    /**
     * The open categories, in taxonomy order.
     *
     * <p>The property is a comma-separated list ({@code PRINTING,TAILORING}), or a YAML list. Present
     * but blank closes every category, which is a decision somebody wrote down; absent is the launch
     * set, which is the decision the owner made.
     *
     * @throws IllegalStateException when the property names something that is not a category.
     *         Deliberately loud rather than skipped: a typo that quietly dropped "PRINTNG" would take
     *         every print shop off the Services tab with nothing anywhere saying why. Goods reads never
     *         ask this question, so a typo here cannot take Home down with it.
     */
    public Set<ServiceCategory> enabled() {
        List<String> names = configuredNames();
        if (names == null) {
            return LAUNCH;
        }
        EnumSet<ServiceCategory> open = EnumSet.noneOf(ServiceCategory.class);
        for (String name : names) {
            String trimmed = name == null ? "" : name.trim();
            if (trimmed.isEmpty()) {
                continue;
            }
            try {
                open.add(ServiceCategory.valueOf(trimmed.toUpperCase(Locale.ROOT)));
            } catch (IllegalArgumentException notACategory) {
                throw new IllegalStateException("'" + trimmed + "' in " + PROPERTY
                        + " is not a service category. The categories are "
                        + Arrays.toString(ServiceCategory.values()) + ".");
            }
        }
        return Collections.unmodifiableSet(open);
    }

    /**
     * The configured names, or null when nothing is configured. A comma-separated value and a YAML
     * list arrive differently: the first as the property itself, the second as indexed keys, which
     * {@link Environment#getProperty(String)} does not see. Reading only the first would silently put
     * a YAML list back to the launch set.
     */
    private List<String> configuredNames() {
        String flat = environment.getProperty(PROPERTY);
        if (flat != null) {
            return Arrays.asList(flat.split(","));
        }
        if (!environment.containsProperty(PROPERTY + "[0]")) {
            return null;
        }
        List<String> listed = new ArrayList<>();
        for (int i = 0; environment.containsProperty(PROPERTY + "[" + i + "]"); i++) {
            listed.add(environment.getProperty(PROPERTY + "[" + i + "]"));
        }
        return listed;
    }
}

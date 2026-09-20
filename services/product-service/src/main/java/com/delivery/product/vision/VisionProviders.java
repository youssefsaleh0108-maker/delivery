package com.delivery.product.vision;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * Which vision provider answers right now.
 *
 * <p>The same runtime switch as {@code GeocodingProviders}: every provider is a bean, one property
 * names the active one, and it is read per call from the {@link Environment} so a Config Server
 * change plus {@code /actuator/busrefresh} moves a deployment between providers without a
 * redeploy.
 *
 * <p>Two failure modes, handled in opposite ways on purpose:
 * <ul>
 *   <li><strong>A name that matches no provider throws.</strong> A typo must not quietly mean
 *       "the fake" — an operator who configured a paid provider would believe it was live.</li>
 *   <li><strong>A real provider with no credential answers with the fake.</strong> That is the
 *       state of every environment until the owner provisions a key, and refusing every scan until
 *       then would make the feature undemonstrable. It is safe because it is never silent: the fake
 *       stamps its name on the scan, and the client labels those results as samples.</li>
 * </ul>
 */
@Component
public class VisionProviders {

    static final String PROPERTY = "delivery.catalog.scan.vision-provider";

    /** What runs when nobody has chosen: the one that costs nothing and sends nothing anywhere. */
    static final String DEFAULT = FakeVisionProvider.NAME;

    private static final Logger log = LoggerFactory.getLogger(VisionProviders.class);

    private final Map<String, VisionProvider> byName;
    private final Environment environment;

    public VisionProviders(List<VisionProvider> providers, Environment environment) {
        Map<String, VisionProvider> index = new LinkedHashMap<>();
        for (VisionProvider provider : providers) {
            index.put(provider.name().toUpperCase(Locale.ROOT), provider);
        }
        if (!index.containsKey(DEFAULT)) {
            throw new IllegalStateException("The " + DEFAULT + " vision provider must always exist");
        }
        this.byName = Map.copyOf(index);
        this.environment = environment;
    }

    /**
     * The provider that will actually answer.
     *
     * @throws VisionException when the configured name matches no provider
     */
    public VisionProvider active() {
        String configured = environment.getProperty(PROPERTY, DEFAULT).trim().toUpperCase(Locale.ROOT);

        VisionProvider provider = byName.get(configured);
        if (provider == null) {
            throw new VisionException(VisionException.Reason.NOT_CONFIGURED,
                    "No vision provider named '" + configured + "'. Set " + PROPERTY
                            + " to one of " + byName.keySet() + ".");
        }
        if (!provider.isReady()) {
            // Once per scan, which is rare enough to be worth the noise: this line is how an
            // operator finds out the key they thought they set never reached the pod.
            log.warn("Vision provider {} is selected but not ready (no credential in the pod's "
                    + "environment); answering with {} sample data instead", configured, DEFAULT);
            return byName.get(DEFAULT);
        }
        return provider;
    }

    /**
     * The configured provider when it actually reads photos: selected, not {@value #DEFAULT}, and
     * ready. Empty otherwise — and never the fake in its place, which is {@link #active}'s fallback.
     *
     * <p>For customer photo search, where a sample answer would be a lie with no label to carry it: a
     * shopper who photographs a jar of tahini must not be shown shops selling Pepsi because nobody
     * has provisioned a key. So until the owner switches real recognition on, the customer app is told
     * there is no photo search at all ({@code GET /api/products/search/capabilities}) and the endpoint
     * refuses. A name that matches no provider is empty here too: {@link #active} is the place that
     * complains about it, once per scan, and this is asked every time Home opens.
     */
    public Optional<VisionProvider> real() {
        String configured = environment.getProperty(PROPERTY, DEFAULT).trim().toUpperCase(Locale.ROOT);
        VisionProvider provider = byName.get(configured);
        if (provider == null || DEFAULT.equals(configured) || !provider.isReady()) {
            return Optional.empty();
        }
        return Optional.of(provider);
    }
}

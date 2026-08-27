package com.delivery.product.geocoding;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

/**
 * Which geocoder is in use right now.
 *
 * <p>The runtime switch, mirroring {@code delivery.connector.default-provider} in the SMS
 * connector: every provider is a bean, and one property decides which of them answers. Swapping
 * from the free dev geocoder to a paid one is then a config change and a
 * {@code /actuator/busrefresh}, not a redeploy.
 *
 * <p>The property is read <strong>per call</strong> from the {@link Environment} rather than
 * captured into a field at construction. That is what makes a Config Server refresh actually take
 * effect: a {@code @Value}-injected field is set once and a bus refresh would not touch it unless
 * this bean were {@code @RefreshScope}d, and a scoped proxy is a lot of machinery to read one
 * string. Reading it here costs a map lookup against an already-resolved property source.
 */
@Component
public class GeocodingProviders {

    static final String PROPERTY = "delivery.geocoding.provider";

    /**
     * What runs when nobody has chosen.
     *
     * <p>The free, keyless one. The same reasoning as the SMS connector's DEV_PASSTHROUGH default:
     * a wrong default that costs nothing and identifies itself is better than one that quietly
     * spends money, and a deployment that has not been configured should not be able to bill anyone.
     */
    static final String DEFAULT = NominatimGeocodingProvider.NAME;

    private final Map<String, GeocodingProvider> byName;
    private final Environment environment;

    public GeocodingProviders(List<GeocodingProvider> providers, Environment environment) {
        // LinkedHashMap so the "known providers" list in the error below reads in a stable order
        // rather than a different one on every boot.
        Map<String, GeocodingProvider> index = new LinkedHashMap<>();
        for (GeocodingProvider provider : providers) {
            index.put(provider.name().toUpperCase(Locale.ROOT), provider);
        }
        this.byName = Map.copyOf(index);
        this.environment = environment;
    }

    /**
     * The configured provider.
     *
     * @throws GeocodingException when the configured name matches no provider. Deliberately louder
     *         than falling back to the default: a typo in the property would otherwise mean a
     *         deployment that believes it is on a paid provider while quietly using the free one,
     *         which is the exact class of "it silently looks live" failure this seam exists to
     *         prevent. Refusing to answer gets noticed in minutes; a silent downgrade does not.
     */
    public GeocodingProvider active() {
        String configured = environment.getProperty(PROPERTY, DEFAULT).trim().toUpperCase(Locale.ROOT);

        GeocodingProvider provider = byName.get(configured);
        if (provider == null) {
            throw new GeocodingException(
                    "No geocoding provider named '" + configured + "'. Set " + PROPERTY
                            + " to one of " + byName.keySet() + ".");
        }
        return provider;
    }
}

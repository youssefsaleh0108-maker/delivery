package com.delivery.accounting.payout;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * The runtime switch: which payout provider is in use.
 *
 * <p>Named in configuration rather than chosen by profile, so switching a live environment to a
 * real processor is one property in the config repo and no rebuild — the same shape the SMS and
 * push connectors use for their vendors.
 *
 * <p><strong>An unknown name fails at startup, loudly, rather than falling back.</strong> That is
 * the important line in this class. A fallback to {@link ManualPayoutProvider} would mean an
 * environment configured for a real processor that had failed to load its bean would go on
 * "paying" riders by hand-entered reference and reporting success, and nobody would find out until
 * a rider asked where their money was. Refusing to start is a failure somebody notices in the
 * deployment rather than in a support ticket.
 */
@Component
public class RiderPayoutProviders {

    private final Map<String, RiderPayoutProvider> byName;
    private final RiderPayoutProvider selected;

    public RiderPayoutProviders(List<RiderPayoutProvider> providers,
                                // MANUAL by default and deliberately so: it is the only provider
                                // that exists, and a default naming one that does not would leave
                                // the service unable to start out of the box.
                                @Value("${delivery.rider-payout.provider:MANUAL}") String name) {
        this.byName = providers.stream()
                .collect(Collectors.toMap(RiderPayoutProvider::name, Function.identity()));

        RiderPayoutProvider provider = byName.get(name == null ? null : name.trim().toUpperCase());
        if (provider == null) {
            throw new IllegalStateException(
                    "delivery.rider-payout.provider is '" + name + "' but no such provider is on "
                            + "the classpath. Available: " + byName.keySet()
                            + ". Refusing to start rather than paying riders through a provider "
                            + "nobody asked for.");
        }
        this.selected = provider;
    }

    public RiderPayoutProvider current() {
        return selected;
    }

    /**
     * Whether the money genuinely leaves an account without a person doing it.
     *
     * <p>Read by the API so a rider's screen can say "we will send this within a day" rather than
     * implying an instant transfer that nothing here performs. It is a property of the provider,
     * not of the request, which is why it lives here.
     */
    public boolean isAutomated() {
        return !ManualPayoutProvider.NAME.equals(selected.name());
    }
}

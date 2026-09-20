package com.delivery.product.shoppage;

import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.io.ClassPathResource;

import com.delivery.platform.security.PlatformSecurityProperties;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The two settings that decide whether this page exists at all, read from the file this service
 * actually ships.
 *
 * <p>Both have a failure mode that no unit test of the controller would catch. The page is
 * anonymous, so it only works if {@code delivery.security.permit-all} names it — and that property
 * <em>replaces</em> the platform's default list rather than adding to it, so naming the page there
 * is also the moment the six actuator and API-doc paths can silently vanish. And the canonical URL,
 * the {@code og:} tags and the bytes inside every printed QR code are built from
 * {@code delivery.public.base-url}: bind it wrong and every shared link and every sign points
 * somewhere that is not the site.
 */
@DisplayName("the public page's configuration")
class PublicShopPageConfigurationTest {

    /** application.yml as the service ships it, resolved against a given process environment. */
    private static StandardEnvironment shipped(Map<String, Object> processEnvironment)
            throws Exception {
        StandardEnvironment environment = new StandardEnvironment();
        environment.getPropertySources()
                .addFirst(new MapPropertySource("test-process-environment", processEnvironment));
        List<PropertySource<?>> loaded = new YamlPropertySourceLoader()
                .load("application.yml", new ClassPathResource("application.yml"));
        assertThat(loaded).isNotEmpty();
        loaded.forEach(environment.getPropertySources()::addLast);
        return environment;
    }

    private static PlatformSecurityProperties security(StandardEnvironment environment) {
        return Binder.get(environment)
                .bind("delivery.security", PlatformSecurityProperties.class)
                .orElseGet(PlatformSecurityProperties::new);
    }

    @Test
    @DisplayName("the page and the sitemap are reachable without a token")
    void thePageIsAnonymous() throws Exception {
        assertThat(security(shipped(Map.of())).getPermitAll())
                .contains("/s/**", "/sitemap.xml");
    }

    @Test
    @DisplayName("opening the page did not close the actuator probes or the API docs")
    void theDefaultsSurvivedBeingOverridden() throws Exception {
        // permit-all REPLACES PlatformSecurityProperties' own list. Every entry it shipped has to
        // be repeated in application.yml, and this is what says so out loud: a readiness probe
        // answered 401 is a pod that never joins its Service, with nothing in the diff to explain
        // it.
        assertThat(security(shipped(Map.of())).getPermitAll())
                .containsAll(new PlatformSecurityProperties().getPermitAll());
    }

    @Test
    @DisplayName("nothing else was opened along with it")
    void nothingElseIsAnonymous() throws Exception {
        List<String> extra = security(shipped(Map.of())).getPermitAll().stream()
                .filter(path -> !new PlatformSecurityProperties().getPermitAll().contains(path))
                .toList();

        assertThat(extra).containsExactlyInAnyOrder("/s/**", "/sitemap.xml");
    }

    @Test
    @DisplayName("the page's own address is www by default and moves with one environment variable")
    void theBaseUrlIsConfigured() throws Exception {
        assertThat(shipped(Map.of()).getProperty("delivery.public.base-url"))
                .isEqualTo("https://www.youdrop.shop");
        assertThat(shipped(Map.of("PUBLIC_SITE_BASE_URL", "https://youdrop.shop"))
                .getProperty("delivery.public.base-url"))
                .isEqualTo("https://youdrop.shop");
    }
}

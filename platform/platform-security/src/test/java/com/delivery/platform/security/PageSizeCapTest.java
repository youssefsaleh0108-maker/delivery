package com.delivery.platform.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.FilteredClassLoader;
import org.springframework.boot.test.context.runner.WebApplicationContextRunner;
import org.springframework.data.web.config.PageableHandlerMethodArgumentResolverCustomizer;
import org.springframework.data.web.PageableHandlerMethodArgumentResolver;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * The platform-wide ceiling on how big a page anybody may ask for.
 *
 * <p>Spring Boot's default is 2000 and {@code @PageableDefault} sets only the default, so every
 * paginated endpoint would serve {@code ?size=2000} to any authenticated caller — roughly 2,001
 * statements on one order-board request, holding a connection from a pool of ten for the whole
 * walk.
 *
 * <p>The second test is the more important one, and it is here because the first shape of this fix
 * put {@code @ConditionalOnClass} on the bean METHOD. That condition is evaluated only after the
 * declaring class's methods have been introspected, and introspecting a method resolves its return
 * type — so the three connector services that carry no Spring Data died on
 * {@code NoClassDefFoundError} before the condition they relied on ever ran. It reached the cluster
 * and crash-looped two pods. Guarding the enclosing class is what makes the reference genuinely
 * optional, and this test is what keeps it that way.
 */
@DisplayName("the platform page-size ceiling")
class PageSizeCapTest {

    private final WebApplicationContextRunner contexts = new WebApplicationContextRunner()
            .withUserConfiguration(ServletSecurityAutoConfiguration.PageableDefaults.class);

    @Test
    void is_applied_wherever_spring_data_web_is_present() {
        contexts.run(context -> {
            assertThat(context).hasSingleBean(PageableHandlerMethodArgumentResolverCustomizer.class);

            PageableHandlerMethodArgumentResolver resolver =
                    new PageableHandlerMethodArgumentResolver();
            context.getBean(PageableHandlerMethodArgumentResolverCustomizer.class)
                    .customize(resolver);

            assertThat(ReflectionTestUtils.getField(resolver, "maxPageSize")).isEqualTo(200);
        });
    }

    @Test
    @DisplayName("does not stop a service that has no Spring Data from starting at all")
    void is_absent_rather_than_fatal_without_spring_data() {
        contexts.withClassLoader(
                        new FilteredClassLoader(PageableHandlerMethodArgumentResolverCustomizer.class))
                .run(context -> {
                    // Starting is the assertion. The failure this guards against was not a missing
                    // bean, it was the whole context dying while working out whether to make one.
                    assertThat(context).hasNotFailed();
                    assertThat(context)
                            .doesNotHaveBean("platformPageSizeCap");
                });
    }
}

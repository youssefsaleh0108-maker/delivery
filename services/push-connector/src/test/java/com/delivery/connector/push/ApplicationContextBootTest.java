package com.delivery.connector.push;

import java.util.ArrayList;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.beans.factory.config.ConfigurableListableBeanFactory;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.ActiveProfiles;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.Mockito.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * The service's own Spring context, started the way the pod starts it.
 *
 * <p>This is the test the estate did not have. Every other test in this module builds the class it
 * is testing with {@code new}, or mocks its collaborators, so the suite never asked the one
 * question the container asks at start-up: given this component scan and this configuration, can
 * Spring actually construct everything? On 2026-09-21 the answer was no in product-service —
 * {@code DemandWeeks} had two public constructors and no {@code @Autowired}, Spring declined to
 * guess, and the pod crash-looped on dev behind a completely green build. Nothing about that
 * mistake was particular to that service; only the absence of this test was.
 *
 * <p>So this boots the REAL application — {@link PushConnectorApplication}, its real
 * {@code @SpringBootApplication} scan, its real {@code application.yml}, the real
 * auto-configurations the platform libraries contribute and a real embedded Tomcat on a random
 * port. Nothing is sliced and nothing of push-connector — the mobile push leg of the notification
 * fan-out — is mocked. The test that would catch the bug is the plain fact that the context
 * refreshes at all.
 *
 * <p><b>What it is allowed to touch.</b> Nothing. This service holds no database, so unlike the
 * rest of the estate's context tests there is no environment variable to gate it on and no reason
 * for it ever to skip: it runs in every build, everywhere, and its CI job fails the build if it did
 * not.
 *
 * <p><b>What it stubs.</b> The broker. {@link StubbedBroker} supplies the one
 * {@code ConnectionFactory} bean, which backs off exactly Spring Boot's own and leaves
 * {@code RabbitTemplate}, {@code RabbitAdmin} and every listener container real, auto-configured
 * and wired, over a socket that goes nowhere. Everything else this service would dial — Keycloak,
 * its sibling services and the trace collector — is pointed at a closed port by
 * {@code application-context-test.yml}. None of them is contacted at start-up, and aiming them at
 * port 1 means a bean that ever starts contacting them fails here rather than reaching a real one.
 */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        // Early enough to stop the configserver: import in application.yml being resolved at all.
        properties = "spring.cloud.config.enabled=false")
@ActiveProfiles("context-test")
@DisplayName("push-connector's own Spring context")
class ApplicationContextBootTest {

    @Autowired
    private ConfigurableApplicationContext context;

    @Test
    @DisplayName("starts, with the real component scan and the real configuration")
    void the_context_starts() {
        assertThat(context.isActive()).isTrue();
    }

    /**
     * The same question again for anything the container would not have asked on its own.
     *
     * <p>Refreshing the context builds every non-lazy singleton, which is what would have caught the
     * demand calendar. A bean marked {@code @Lazy} — or one only ever reached through an
     * {@code ObjectProvider} — is not built then, so its wiring would still be unproven by a context
     * that started cleanly. This asks for each of them by name. It is deliberately limited to this
     * platform's own beans: a framework bean that declines to be built early is the framework's
     * business, ours are ours.
     */
    @Test
    @DisplayName("can build every bean this platform declares, the lazy ones included")
    void every_bean_of_ours_can_be_built() {
        ConfigurableListableBeanFactory beans = context.getBeanFactory();
        List<String> unbuildable = new ArrayList<>();

        for (String name : beans.getBeanDefinitionNames()) {
            BeanDefinition definition = beans.getBeanDefinition(name);
            if (definition.isAbstract() || !definition.isSingleton()) {
                continue;
            }
            Class<?> type;
            try {
                type = beans.getType(name, false);
            } catch (RuntimeException cannotEvenResolveIt) {
                unbuildable.add(name + " -> " + cannotEvenResolveIt);
                continue;
            }
            if (type == null || !type.getName().startsWith("com.delivery.")) {
                continue;
            }
            try {
                beans.getBean(name);
            } catch (RuntimeException refused) {
                unbuildable.add(name + " -> " + refused);
            }
        }

        assertThat(unbuildable).isEmpty();
    }

    /**
     * The broker, and the only bean of this service's context the test replaces.
     *
     * <p>{@code @TestConfiguration} is additive: the application's configuration is loaded whole and
     * this is added to it, unlike a plain nested {@code @Configuration}, which would replace it and
     * turn this into exactly the sliced context the test exists not to be.
     *
     * <p>Spring Boot's {@code RabbitAutoConfiguration} declares its {@code CachingConnectionFactory}
     * {@code @ConditionalOnMissingBean(ConnectionFactory.class)}, so supplying this one backs that
     * single bean off and leaves {@code RabbitTemplate}, {@code RabbitAdmin}, the listener container
     * factory and every exchange, queue and binding bean real, auto-configured and wired — over a
     * connection that goes nowhere.
     */
    @TestConfiguration(proxyBeanMethods = false)
    static class StubbedBroker {

        @Bean
        ConnectionFactory rabbitConnectionFactory() {
            org.springframework.amqp.rabbit.connection.Connection connection =
                    mock(org.springframework.amqp.rabbit.connection.Connection.class);
            when(connection.isOpen()).thenReturn(true);
            when(connection.createChannel(anyBoolean()))
                    .thenReturn(mock(com.rabbitmq.client.Channel.class, RETURNS_DEEP_STUBS));

            ConnectionFactory factory = mock(ConnectionFactory.class);
            when(factory.createConnection()).thenReturn(connection);
            when(factory.getHost()).thenReturn("stub");
            when(factory.getPort()).thenReturn(0);
            when(factory.getVirtualHost()).thenReturn("/");
            when(factory.getUsername()).thenReturn("stub");
            return factory;
        }
    }
}

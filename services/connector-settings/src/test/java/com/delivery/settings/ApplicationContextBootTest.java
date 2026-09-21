package com.delivery.settings;

import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.beans.factory.config.ConfigurableListableBeanFactory;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

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
 * <p>So this boots the REAL application — {@link ConnectorSettingsApplication}, its real
 * {@code @SpringBootApplication} scan, its real {@code application.yml}, the real
 * auto-configurations the platform libraries contribute, real Flyway, real Hibernate validation and
 * a real embedded Tomcat on a random port. Nothing is sliced and nothing of connector-settings —
 * which provider each notification channel currently sends through — is mocked. The test that would
 * catch the bug is the plain fact that the context refreshes at all.
 *
 * <p><b>What it is allowed to touch.</b> One thing: a PostgreSQL named by
 * {@code SETTINGS_TEST_DB_URL}, the same switch every database test in this repository runs behind,
 * and the same throwaway {@code postgis/postgis:17-3.5} the CI job starts. Absent, the test skips —
 * and the workflow fails the build if it skipped, because a context test that did not run is
 * exactly the green build it exists to stop. It creates a database of its own with a random name
 * and drops only that.
 *
 * <p><b>What it stubs.</b> The broker. {@link StubbedBroker} supplies the one
 * {@code ConnectionFactory} bean, which backs off exactly Spring Boot's own and leaves
 * {@code RabbitTemplate}, {@code RabbitAdmin} and every listener container real, auto-configured
 * and wired, over a socket that goes nowhere. Everything else this service would dial — Keycloak,
 * its sibling services and the trace collector — is pointed at a closed port by
 * {@code application-context-test.yml}. None of them is contacted at start-up, and aiming them at
 * port 1 means a bean that ever starts contacting them fails here rather than reaching a real one.
 */
@EnabledIfEnvironmentVariable(named = "SETTINGS_TEST_DB_URL", matches = ".+")
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        // Early enough to stop the configserver: import in application.yml being resolved at all.
        properties = "spring.cloud.config.enabled=false")
@ActiveProfiles("context-test")
@DisplayName("connector-settings's own Spring context")
class ApplicationContextBootTest {

    private static final String ADMIN_URL = System.getenv("SETTINGS_TEST_DB_URL");
    private static final String USER = envOr("SETTINGS_TEST_DB_USER", "postgres");
    private static final String PASSWORD = envOr("SETTINGS_TEST_DB_PASSWORD", "postgres");
    private static final String DATABASE =
            "ctx_boot_" + UUID.randomUUID().toString().substring(0, 8);

    @Autowired
    private ConfigurableApplicationContext context;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    /**
     * Gives the real datasource a database of this run's own, and changes nothing else.
     *
     * <p>A throwaway DATABASE rather than a throwaway schema, which is what OneTimeCodesDatabaseTest
     * already does here and for the same reason: some migrations name their schema outright, so a
     * schema chosen by the test would not be the one they write into. It also leaves
     * {@code spring.flyway.schemas} and {@code hibernate.default_schema} exactly as the service
     * ships them, so the boot under test is the boot the pod does, into its own {@code settings}
     * schema and all.
     *
     * <p>Invoked by the TestContext framework immediately before the context is refreshed, and only
     * when it is going to be refreshed — so a skipped test creates nothing.
     */
    @DynamicPropertySource
    static void useAThrowawayDatabase(DynamicPropertyRegistry registry) throws SQLException {
        try (java.sql.Connection admin = DriverManager.getConnection(ADMIN_URL, USER, PASSWORD);
             Statement statement = admin.createStatement()) {
            statement.execute("CREATE DATABASE " + DATABASE);
        }
        // What infra/postgres/init provides on every environment, inside the new database.
        try (java.sql.Connection fresh = DriverManager.getConnection(plainUrl(), USER, PASSWORD);
             Statement statement = fresh.createStatement()) {
            statement.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            statement.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm");
            statement.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"");
        }
        registry.add("spring.datasource.url", ApplicationContextBootTest::serviceUrl);
        registry.add("spring.datasource.username", () -> USER);
        registry.add("spring.datasource.password", () -> PASSWORD);
    }

    /** The admin URL with the throwaway database swapped in for the one it names. */
    private static String plainUrl() {
        int slash = ADMIN_URL.lastIndexOf('/');
        int query = ADMIN_URL.indexOf('?', slash);
        return ADMIN_URL.substring(0, slash + 1) + DATABASE
                + (query < 0 ? "" : ADMIN_URL.substring(query));
    }

    /** The same, carrying the currentSchema the service's own DB_URL carries in every environment. */
    private static String serviceUrl() {
        String url = plainUrl();
        return url + (url.contains("?") ? "&" : "?") + "currentSchema=settings";
    }

    @AfterAll
    static void dropTheDatabase() throws SQLException {
        if (ADMIN_URL == null) {
            return;
        }
        try (java.sql.Connection admin = DriverManager.getConnection(ADMIN_URL, USER, PASSWORD);
             Statement statement = admin.createStatement()) {
            statement.execute("DROP DATABASE IF EXISTS " + DATABASE + " WITH (FORCE)");
        }
    }

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

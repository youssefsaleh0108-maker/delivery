package com.delivery.configserver;

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
import org.springframework.cloud.config.server.environment.EnvironmentRepository;
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
 * The Config Server's own Spring context, started the way the pod starts it.
 *
 * <p>This is the test the estate did not have. Every other module's suite builds the class it is
 * testing with {@code new}, or mocks its collaborators, so nothing ever asked the one question the
 * container asks at start-up: given this component scan and this configuration, can Spring actually
 * construct everything? On 2026-09-21 the answer was no in product-service — {@code DemandWeeks} had
 * two public constructors and no {@code @Autowired}, Spring declined to guess, and the pod
 * crash-looped on dev behind a completely green build.
 *
 * <p>This module had the furthest to fall: until now it held no test at all. It is also the service
 * whose start-up has the most to get wrong — the backend it serves configuration from is assembled
 * out of a profile and a list, and if it assembles wrongly every other service on the platform reads
 * its configuration from the wrong place or fails to start behind it.
 *
 * <p>So this boots the REAL application — {@link ConfigServerApplication}, {@code @EnableConfigServer}
 * and all, under the {@code composite} profile the pod runs under, with the real
 * {@code application.yml} and a real embedded Tomcat on a random port. The composite backend is
 * asserted to be there rather than merely assumed: a {@code composite} profile that stopped selecting
 * it would leave a server that starts cleanly and serves nothing, which is precisely the failure this
 * class of test is for.
 *
 * <p><b>What it is allowed to touch.</b> One thing: a PostgreSQL named by
 * {@code CONFIG_TEST_DB_URL}, the same switch every database test in this repository runs behind, and
 * the same throwaway {@code postgis/postgis:17-3.5} the CI job starts. This service has no Flyway and
 * no JPA, but it does have a JDBC config backend and therefore a Hikari pool, which validates a
 * connection while the context is still refreshing — so a database it is, or the context cannot
 * honestly be said to have started. Absent, the test skips, and the workflow fails the build if it
 * skipped. It creates a database of its own with a random name and drops only that.
 *
 * <p><b>What it stubs.</b> The broker, by bean — {@link StubbedBroker} supplies the one
 * {@code ConnectionFactory}, which backs off exactly Spring Boot's own and leaves the rest of the
 * AMQP wiring real over a socket that goes nowhere. Vault is stubbed by address, not by bean: the
 * environment repository is built and wired as it is in the pod and logs in only on the first request
 * for configuration, which this context never makes. Vault's AppRole credentials and the server's own
 * basic-auth password have no defaults in {@code application.yml}, on purpose; obvious non-secrets
 * stand in for them in {@code application-context-test.yml}.
 */
@EnabledIfEnvironmentVariable(named = "CONFIG_TEST_DB_URL", matches = ".+")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
// "composite" is not decoration: it is what gives this server a backend. @ActiveProfiles replaces
// spring.profiles.active outright, so leaving it out here would quietly test a different server.
@ActiveProfiles({"composite", "context-test"})
@DisplayName("config-server's own Spring context")
class ApplicationContextBootTest {

    private static final String ADMIN_URL = System.getenv("CONFIG_TEST_DB_URL");
    private static final String USER = envOr("CONFIG_TEST_DB_USER", "postgres");
    private static final String PASSWORD = envOr("CONFIG_TEST_DB_PASSWORD", "postgres");
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
     * <p>Unlike the rest of the estate this service migrates nothing, so the database starts and
     * stays empty. It still has to exist: the JDBC backend's pool opens a connection while the
     * context refreshes, and a context that could not get one has not started.
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
        registry.add("spring.datasource.url", ApplicationContextBootTest::serviceUrl);
        registry.add("spring.datasource.username", () -> USER);
        registry.add("spring.datasource.password", () -> PASSWORD);
    }

    /**
     * The admin URL with the throwaway database swapped in, carrying the currentSchema this
     * service's own CONFIG_DB_URL carries in every environment.
     */
    private static String serviceUrl() {
        int slash = ADMIN_URL.lastIndexOf('/');
        int query = ADMIN_URL.indexOf('?', slash);
        String url = ADMIN_URL.substring(0, slash + 1) + DATABASE
                + (query < 0 ? "" : ADMIN_URL.substring(query));
        return url + (url.contains("?") ? "&" : "?") + "currentSchema=config";
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

    @Test
    @DisplayName("has a backend to serve configuration from, which is the whole of its job")
    void the_composite_backend_is_assembled() {
        // A Config Server with no EnvironmentRepository starts perfectly and answers every service
        // on the platform with nothing. The bean's presence is the assertion; what it returns
        // depends on a database and a Vault this test is deliberately not given.
        assertThat(context.getBeanProvider(EnvironmentRepository.class).stream()).isNotEmpty();
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
     * single bean off and leaves the rest of the AMQP wiring real, auto-configured and connected to
     * nothing.
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

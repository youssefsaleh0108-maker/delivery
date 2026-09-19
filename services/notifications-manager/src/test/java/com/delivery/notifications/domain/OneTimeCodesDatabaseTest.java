package com.delivery.notifications.domain;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;

import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.notifications.service.TestCodeSink;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * V20 against a real PostgreSQL: the codes already in the log are masked, and the test code sink's
 * table refuses any address off the reserved domain whatever writes to it.
 *
 * <p>The rest of this module runs without a database, so the SQL here — a regexp_replace over the
 * log, a CHECK written as a regular expression — would otherwise be checked by nothing before it
 * reached dev. The entity manager validates every entity against the migrated schema, as the service
 * does at boot, so {@link TestCode} disagreeing with V20 would fail here rather than crash a pod.
 *
 * <p>Runs only when {@code NOTIFICATIONS_TEST_DB_URL} names a database a superuser may use, and is
 * skipped otherwise. The migrations name their schema ({@code notification}), so this creates a
 * database of its own with a random name and drops only that:
 *
 * <pre>
 * docker run -d --name notifications-it -e POSTGRES_PASSWORD=it -p 55436:5432 postgis/postgis:17-3.5
 * NOTIFICATIONS_TEST_DB_URL=jdbc:postgresql://localhost:55436/postgres NOTIFICATIONS_TEST_DB_PASSWORD=it \
 *     mvn -pl services/notifications-manager -am -Dtest=OneTimeCodesDatabaseTest \
 *     -Dsurefire.failIfNoSpecifiedTests=false test
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "NOTIFICATIONS_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("one-time codes, against a real database")
class OneTimeCodesDatabaseTest {

    private static final String CODE = "482913";

    private final String adminUrl = System.getenv("NOTIFICATIONS_TEST_DB_URL");
    private final String user = envOr("NOTIFICATIONS_TEST_DB_USER", "postgres");
    private final String password = envOr("NOTIFICATIONS_TEST_DB_PASSWORD", "postgres");
    private final String database = "notifications_it_" + UUID.randomUUID().toString().substring(0, 8);

    private final UUID codeRow = UUID.randomUUID();
    private final UUID orderRow = UUID.randomUUID();

    private EntityManagerFactory entityManagerFactory;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    @BeforeAll
    void migrateOverALogThatHeldCodes() throws SQLException {
        try (Connection admin = DriverManager.getConnection(adminUrl, user, password);
             Statement statement = admin.createStatement()) {
            statement.execute("CREATE DATABASE " + database);
        }

        // The log as it stood: a verification code in full, and an order message with a long number.
        flyway(MigrationVersion.fromVersion("19")).migrate();
        insertLog(codeRow, "onboarding.verification", CODE + " is your YouDrop verification code",
                CODE + "\n\nUse this code to confirm your email address. It expires in 10 minutes.");
        insertLog(orderRow, "order.placed", "We got your order",
                "Your order totalling 125000 LBP has been sent to the shop.");

        flyway(MigrationVersion.LATEST).migrate();

        entityManagerFactory = entityManagerFactory();
    }

    @AfterAll
    void dropTheDatabase() throws SQLException {
        if (entityManagerFactory != null) {
            entityManagerFactory.close();
        }
        try (Connection admin = DriverManager.getConnection(adminUrl, user, password);
             Statement statement = admin.createStatement()) {
            statement.execute("DROP DATABASE IF EXISTS " + database + " WITH (FORCE)");
        }
    }

    @Test
    @DisplayName("V20 masks every code already in the log and leaves every other message as it was")
    void codes_already_logged_are_masked() throws SQLException {
        String masked = query("SELECT subject || '|' || body FROM notification_log WHERE id = '"
                + codeRow + "'");
        assertThat(masked).doesNotContain(CODE)
                .startsWith("****** is your YouDrop verification code|******")
                .contains("It expires in 10 minutes");

        assertThat(query("SELECT body FROM notification_log WHERE id = '" + orderRow + "'"))
                .isEqualTo("Your order totalling 125000 LBP has been sent to the shop.");
    }

    @Test
    @DisplayName("the sink keeps a code for a test address through the real repository")
    void the_sink_writes_through_the_real_repository() throws SQLException {
        EntityManager em = entityManagerFactory.createEntityManager();
        try {
            em.getTransaction().begin();
            TestCodeSink sink = new TestCodeSink(
                    new JpaRepositoryFactory(em).getRepository(TestCodeRepository.class), true);
            assertThat(sink.capture("EMAIL", "qa.db@youdrop.test", "onboarding.verification",
                    CODE + " is your YouDrop verification code", CODE + "\n\nUse this code."))
                    .isTrue();
            em.getTransaction().commit();
        } finally {
            if (em.getTransaction().isActive()) {
                em.getTransaction().rollback();
            }
            em.close();
        }

        // What a smoke test reads.
        assertThat(query("SELECT code FROM test_code_sink WHERE recipient = 'qa.db@youdrop.test' "
                + "ORDER BY created_at DESC LIMIT 1")).isEqualTo(CODE);
    }

    /** The table's own CHECK, so a row for a real address cannot exist whatever writes it. */
    @Test
    @DisplayName("the sink's table refuses any address off the reserved domain")
    void the_table_refuses_a_real_address() {
        assertThatThrownBy(() -> execute("INSERT INTO test_code_sink (id, recipient, purpose, code) "
                + "VALUES (gen_random_uuid(), 'victim@example.com', 'onboarding.password-reset', '"
                + CODE + "')"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_test_code_sink_reserved_domain");
        assertThatThrownBy(() -> execute("INSERT INTO test_code_sink (id, recipient, purpose, code) "
                + "VALUES (gen_random_uuid(), 'victim@example.com@youdrop.test', "
                + "'onboarding.password-reset', '" + CODE + "')"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_test_code_sink_reserved_domain");
    }

    // ------------------------------------------------------------------------------------ helpers

    private String url() {
        int slash = adminUrl.lastIndexOf('/');
        int query = adminUrl.indexOf('?', slash);
        return adminUrl.substring(0, slash + 1) + database + (query < 0 ? "" : adminUrl.substring(query));
    }

    private Connection connection() throws SQLException {
        Connection connection = DriverManager.getConnection(url(), user, password);
        try (Statement statement = connection.createStatement()) {
            statement.execute("SET search_path TO notification");
        }
        return connection;
    }

    private void insertLog(UUID id, String eventType, String subject, String body)
            throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO notification_log (id, recipient_id, channel, recipient, event_type, "
                             + "subject, body) VALUES (?, 'anonymous', 'EMAIL', 'sam@example.com', ?, "
                             + "?, ?)")) {
            insert.setObject(1, id);
            insert.setString(2, eventType);
            insert.setString(3, subject);
            insert.setString(4, body);
            insert.executeUpdate();
        }
    }

    private String query(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            return rows.next() ? rows.getString(1) : null;
        }
    }

    private void execute(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement()) {
            statement.executeUpdate(sql);
        }
    }

    /** What application.yml gives the service. */
    private Flyway flyway(MigrationVersion target) {
        return Flyway.configure()
                .dataSource(url(), user, password)
                .schemas("notification")
                .defaultSchema("notification")
                .locations("classpath:db/migration/notification")
                .table("flyway_schema_history_notifications_manager")
                .baselineOnMigrate(true)
                .baselineVersion("0")
                .target(target)
                .load();
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(
                url() + (url().contains("?") ? "&" : "?") + "currentSchema=notification",
                user, password));
        // What the service scans (@EntityScan("com.delivery")).
        factory.setPackagesToScan("com.delivery");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Hibernate refuses to start if an entity drifted from Flyway.
        jpa.put("hibernate.hbm2ddl.auto", "validate");
        jpa.put("hibernate.default_schema", "notification");
        jpa.put("hibernate.jdbc.time_zone", "UTC");
        jpa.put("hibernate.physical_naming_strategy",
                "org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy");
        jpa.put("hibernate.implicit_naming_strategy",
                "org.springframework.boot.orm.jpa.hibernate.SpringImplicitNamingStrategy");
        factory.setJpaPropertyMap(jpa);
        factory.afterPropertiesSet();
        return factory.getObject();
    }
}

package com.delivery.onboarding.domain;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import jakarta.persistence.OptimisticLockException;
import jakarta.persistence.RollbackException;

import org.camunda.bpm.engine.RuntimeService;
import org.camunda.bpm.engine.TaskService;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationVersion;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaDialect;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication.Kind;
import com.delivery.onboarding.service.ApplicantDocumentService;
import com.delivery.onboarding.service.ApplicationIntake;
import com.delivery.onboarding.service.AutoApprovalPolicy;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.ServiceProviderAnswers;
import com.delivery.onboarding.service.VerificationService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.Mockito.RETURNS_DEEP_STUBS;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * V46 and the application's version, against a real PostgreSQL.
 *
 * <p>Everything else in this module runs without a database, so the optimistic lock the sign-in and
 * the decisions now lean on was proved by mocks alone: a mock can be told to throw a conflict, but
 * only a database decides whether two real writes produce one. Here they do. The entity manager
 * validates every entity against the migrated schema, as the service does at boot
 * ({@code ddl-auto: validate}), so an entity that disagreed with V46 would fail here first.
 *
 * <p>Runs only when {@code ONBOARDING_TEST_DB_URL} names a database a superuser may use, such as a
 * throwaway {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a schema
 * of its own with a random name and drops only that schema, so it cannot touch a real one:
 *
 * <pre>
 * docker run -d --name onboarding-it -e POSTGRES_PASSWORD=it -p 55435:5432 postgis/postgis:17-3.5
 * ONBOARDING_TEST_DB_URL=jdbc:postgresql://localhost:55435/postgres ONBOARDING_TEST_DB_PASSWORD=it \
 *     mvn -Dtest=ApplicationVersionDatabaseTest test
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "ONBOARDING_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("an application's version, against a real database")
class ApplicationVersionDatabaseTest {

    private final String url = System.getenv("ONBOARDING_TEST_DB_URL");
    private final String user = envOr("ONBOARDING_TEST_DB_USER", "postgres");
    private final String password = envOr("ONBOARDING_TEST_DB_PASSWORD", "postgres");
    private final String schema = "onboarding_version_it_" + UUID.randomUUID().toString().substring(0, 8);

    /** An application taken before V46, written with the columns it had then. */
    private final UUID before = UUID.randomUUID();

    private EntityManagerFactory entityManagerFactory;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    // ------------------------------------------------------------------------------------ set-up

    @BeforeAll
    void migrateOverAnExistingApplication() throws SQLException {
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            statement.execute("CREATE SCHEMA " + schema);
        }

        // The schema as it stood before this change, with an application already in it.
        flyway(MigrationVersion.fromVersion("45")).migrate();
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO onboarding_applications (id, kind, business_name, contact_name, "
                             + "contact_email, reference) VALUES (?, 'MERCHANT', 'Before V46', "
                             + "'Old Applicant', 'old@example.test', ?)")) {
            insert.setObject(1, before);
            insert.setString(2, "ref-" + before);
            insert.executeUpdate();
        }

        // Then V46. A constraint an existing row failed would make this throw.
        flyway(MigrationVersion.LATEST).migrate();

        entityManagerFactory = entityManagerFactory();
    }

    @AfterAll
    void dropTheSchema() throws SQLException {
        if (entityManagerFactory != null) {
            entityManagerFactory.close();
        }
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            // Bounded, so a lock nobody released fails the clean-up instead of hanging the build.
            statement.execute("SET lock_timeout = '30s'");
            statement.execute("DROP SCHEMA IF EXISTS " + schema + " CASCADE");
        }
    }

    // ------------------------------------------------------------------------------------ V46

    @Test
    @DisplayName("V46 applies over an existing application, which starts at version 0 with no ticket")
    void v46_applies_over_existing_applications() throws SQLException {
        assertThat(queryString("SELECT success::text FROM flyway_schema_history WHERE version = '46'"))
                .isEqualTo("true");
        assertThat(queryString("SELECT version || '|' || coalesce(account_ticket_hash, '-') || '|' "
                + "|| coalesce(account_ticket_expires_at::text, '-') FROM onboarding_applications "
                + "WHERE id = '" + before + "'"))
                .isEqualTo("0|-|-");
    }

    @Test
    @DisplayName("a ticket is a hash and a deadline together, or nothing")
    void a_half_ticket_is_refused() {
        assertThatThrownBy(() -> execute("UPDATE onboarding_applications SET account_ticket_hash = "
                + "repeat('a', 64) WHERE id = '" + before + "'"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_application_account_ticket");
    }

    // ------------------------------------------------------------------------------------ the lock

    @Test
    @DisplayName("of two real overlapping writes, the later fails and changes nothing")
    void a_real_concurrent_update_gets_the_conflict() throws SQLException {
        UUID id = persistedRider("overlap");

        EntityManager reviewer = entityManagerFactory.createEntityManager();
        EntityManager applicant = entityManagerFactory.createEntityManager();
        try {
            reviewer.getTransaction().begin();
            applicant.getTransaction().begin();
            OnboardingApplication decided = reviewer.find(OnboardingApplication.class, id);
            OnboardingApplication signingIn = applicant.find(OnboardingApplication.class, id);

            // The applicant's sign-in is recorded and committed first.
            signingIn.applicantAccountCreated("kc-overlap");
            applicant.getTransaction().commit();

            // The reviewer's copy is now stale; writing it must fail rather than overwrite.
            decided.reject("reviewer-1", "Not in that area");
            Throwable thrown = catchThrowable(() -> reviewer.getTransaction().commit());
            assertThat(thrown).isInstanceOf(RollbackException.class);
            assertThat(causesOf(thrown)).anyMatch(cause -> cause instanceof OptimisticLockException
                    || cause instanceof org.hibernate.StaleStateException);
        } finally {
            rollBackIfOpen(reviewer);
            rollBackIfOpen(applicant);
            reviewer.close();
            applicant.close();
        }

        assertThat(row(id)).isEqualTo("SUBMITTED|kc-overlap|1");
    }

    /**
     * The finding the flush fixed, on a real row: a decision whose application changed after it was
     * read is refused at its own flush, before the engine is told — so no role is granted, no rider
     * attached, nobody told — and the change it raced survives.
     */
    @Test
    @DisplayName("an approval that raced a sign-in is refused before anything remote, and the sign-in stays")
    void an_approval_that_lost_the_race_does_nothing_remote() throws SQLException {
        UUID id = persistedRider("race");

        EntityManager reviewing = entityManagerFactory.createEntityManager();
        TaskService tasks = mock(TaskService.class, RETURNS_DEEP_STUBS);
        KeycloakAdminClient keycloak = mock(KeycloakAdminClient.class);
        ApplicantDocumentService documents = mock(ApplicantDocumentService.class);
        // Between the reviewer's read and the reviewer's write, the applicant's sign-in commits.
        when(documents.outstandingSummary(id)).thenAnswer(call -> {
            recordSignInElsewhere(id, "kc-race");
            return null;
        });
        OnboardingService onboarding = onboarding(reviewing, tasks, keycloak, documents);

        try {
            reviewing.getTransaction().begin();
            Throwable thrown = catchThrowable(() -> onboarding.approve(id, "reviewer-1"));

            // Refused at the decision's own flush. In the service, the repository proxy hands this
            // to the entity manager factory's dialect, which is this translation; the result is
            // what ApplicationChangedAdvice answers with 409.
            assertThat(thrown).isInstanceOf(RuntimeException.class);
            assertThat(new HibernateJpaDialect().translateExceptionIfPossible((RuntimeException) thrown))
                    .isInstanceOf(OptimisticLockingFailureException.class);
            verify(tasks, never()).complete(any(), anyMap());
            verifyNoInteractions(keycloak);
        } finally {
            rollBackIfOpen(reviewing);
            reviewing.close();
        }

        assertThat(row(id)).isEqualTo("SUBMITTED|kc-race|1");
    }

    // ------------------------------------------------------------------------------------ helpers

    private UUID persistedRider(String name) {
        EntityManager em = entityManagerFactory.createEntityManager();
        try {
            em.getTransaction().begin();
            OnboardingApplication application = new OnboardingApplication(Kind.RIDER, name, name,
                    name + "@example.test", Instant.now(), null, null, null, null, null);
            application.startedAs("process-" + name);
            em.persist(application);
            em.getTransaction().commit();
            return application.getId();
        } finally {
            em.close();
        }
    }

    private void recordSignInElsewhere(UUID id, String userRef) {
        EntityManager elsewhere = entityManagerFactory.createEntityManager();
        try {
            elsewhere.getTransaction().begin();
            elsewhere.find(OnboardingApplication.class, id).applicantAccountCreated(userRef);
            elsewhere.getTransaction().commit();
        } finally {
            elsewhere.close();
        }
    }

    private OnboardingService onboarding(EntityManager em, TaskService tasks,
                                         KeycloakAdminClient keycloak,
                                         ApplicantDocumentService documents) {
        OnboardingApplicationRepository applications =
                new JpaRepositoryFactory(em).getRepository(OnboardingApplicationRepository.class);
        return new OnboardingService(applications, mock(ApplicationIntake.class),
                mock(VerificationService.class), mock(ServiceProviderAnswers.class),
                mock(RuntimeService.class), tasks, keycloak, documents,
                new AutoApprovalPolicy(false, false, false,
                        mock(AutoApprovalDecisionRepository.class),
                        mock(AutoApprovalAuditRepository.class)),
                mock(org.springframework.transaction.PlatformTransactionManager.class),
                mock(PartnerEditEntryRepository.class));
    }

    private static java.util.List<Throwable> causesOf(Throwable thrown) {
        java.util.List<Throwable> chain = new java.util.ArrayList<>();
        for (Throwable cause = thrown; cause != null && !chain.contains(cause); cause = cause.getCause()) {
            chain.add(cause);
        }
        return chain;
    }

    private static void rollBackIfOpen(EntityManager em) {
        if (em.getTransaction().isActive()) {
            em.getTransaction().rollback();
        }
    }

    /** status | applicant_user_ref | version, as committed. */
    private String row(UUID id) throws SQLException {
        return queryString("SELECT status || '|' || coalesce(applicant_user_ref, '-') || '|' || version "
                + "FROM onboarding_applications WHERE id = '" + id + "'");
    }

    private Connection connection() throws SQLException {
        Connection connection = DriverManager.getConnection(url, user, password);
        try (Statement statement = connection.createStatement()) {
            statement.execute("SET search_path TO " + schema);
        }
        return connection;
    }

    private String queryString(String sql) throws SQLException {
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

    private Flyway flyway(MigrationVersion target) {
        return Flyway.configure()
                .dataSource(url, user, password)
                .schemas(schema)
                .defaultSchema(schema)
                // The location application.yml gives the service.
                .locations("classpath:db/migration/onboarding")
                .target(target)
                .load();
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(urlInSchema(), user, password));
        // What the service scans (@EntityScan("com.delivery")), platform-storage's file rows included.
        factory.setPackagesToScan("com.delivery");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it.
        jpa.put("hibernate.hbm2ddl.auto", "validate");
        jpa.put("hibernate.default_schema", schema);
        jpa.put("hibernate.jdbc.time_zone", "UTC");
        // Spring Boot's naming, so a column an entity leaves implicit is looked for where the app looks.
        jpa.put("hibernate.physical_naming_strategy",
                "org.hibernate.boot.model.naming.CamelCaseToUnderscoresNamingStrategy");
        jpa.put("hibernate.implicit_naming_strategy",
                "org.springframework.boot.orm.jpa.hibernate.SpringImplicitNamingStrategy");
        factory.setJpaPropertyMap(jpa);
        factory.afterPropertiesSet();
        return factory.getObject();
    }

    private String urlInSchema() {
        return url + (url.contains("?") ? "&" : "?") + "currentSchema=" + schema;
    }
}

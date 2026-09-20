package com.delivery.accounting.domain;

import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;

import org.hibernate.SessionFactory;
import org.hibernate.boot.MetadataSources;
import org.hibernate.boot.registry.StandardServiceRegistry;
import org.hibernate.boot.registry.StandardServiceRegistryBuilder;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.data.jpa.repository.Query;

import jakarta.persistence.EntityManager;

/**
 * Every JPQL query on the cash and rider repositories is valid against the real entity model.
 *
 * <p>Spring Data validates an {@code @Query} only when the application context starts, and this
 * service's tests never start one — there is no database on a build machine, and the Postgres-backed
 * query tests are skipped without one. So a query naming a field that does not exist, or an enum
 * constant spelt wrong, would compile, pass every mocked test, and take the service down at deploy.
 *
 * <p>This boots Hibernate against the entities with no database at all — metadata access switched
 * off, the Postgres dialect named — and asks it to interpret each query. Interpretation resolves
 * every path, parameter and enum literal against the mapping, which is exactly the failure a mock
 * cannot see. It does not prove what the SQL returns; the Postgres-backed tests do that.
 */
@DisplayName("repository queries")
class RepositoryQueriesParseTest {

    private static SessionFactory factory;

    @BeforeAll
    static void boot() {
        StandardServiceRegistry registry = new StandardServiceRegistryBuilder()
                .applySetting("hibernate.dialect", "org.hibernate.dialect.PostgreSQLDialect")
                .applySetting("hibernate.boot.allow_jdbc_metadata_access", "false")
                .applySetting("hibernate.default_schema", "accounting")
                .build();
        factory = new MetadataSources(registry)
                .addAnnotatedClass(CashFloatEntry.class)
                .addAnnotatedClass(RiderLedgerEntry.class)
                .addAnnotatedClass(AccountingTransaction.class)
                .addAnnotatedClass(CarrierPayPolicy.class)
                .addAnnotatedClass(CarrierPayRun.class)
                .addAnnotatedClass(CarrierPayslip.class)
                .addAnnotatedClass(CarrierPayLine.class)
                .addAnnotatedClass(CarrierPayAdjustment.class)
                .addAnnotatedClass(CarrierPayrollEvent.class)
                .addAnnotatedClass(CarrierPayAttendance.class)
                .addAnnotatedClass(CarrierPayDelivered.class)
                .buildMetadata()
                .buildSessionFactory();
    }

    /**
     * Payroll's repositories are mostly derived queries — a method name Spring Data turns into a
     * query when the context starts, and nothing earlier. A property spelt wrong in one of those
     * names compiles, passes every mocked test and stops the service at deploy, so each name is
     * parsed here against its entity the way Spring Data will parse it.
     */
    static Stream<Arguments> derivedQueries() {
        List<Arguments> out = new ArrayList<>();
        for (Class<?>[] pair : List.of(
                new Class<?>[] {CarrierPayPolicyRepository.class, CarrierPayPolicy.class},
                new Class<?>[] {CarrierPayRunRepository.class, CarrierPayRun.class},
                new Class<?>[] {CarrierPayslipRepository.class, CarrierPayslip.class},
                new Class<?>[] {CarrierPayLineRepository.class, CarrierPayLine.class},
                new Class<?>[] {CarrierPayAdjustmentRepository.class, CarrierPayAdjustment.class},
                new Class<?>[] {CarrierPayrollEventRepository.class, CarrierPayrollEvent.class},
                new Class<?>[] {CarrierPayAttendanceRepository.class, CarrierPayAttendance.class},
                new Class<?>[] {CarrierPayDeliveredRepository.class, CarrierPayDelivered.class})) {
            for (Method method : pair[0].getDeclaredMethods()) {
                if (method.getAnnotation(Query.class) == null && !method.isDefault()) {
                    out.add(Arguments.of(pair[0].getSimpleName() + "." + method.getName(),
                            method.getName(), pair[1]));
                }
            }
        }
        return out.stream();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("derivedQueries")
    void derivedNamesResolve(String name, String methodName, Class<?> entity) {
        // Throws PropertyReferenceException naming the property that does not exist.
        new org.springframework.data.repository.query.parser.PartTree(methodName, entity);
    }

    @AfterAll
    static void close() {
        if (factory != null) {
            factory.close();
        }
    }

    static Stream<Arguments> queries() {
        List<Arguments> out = new ArrayList<>();
        for (Class<?> repository : List.of(CashFloatRepository.class,
                RiderLedgerRepository.class, CarrierPayRunRepository.class,
                CarrierPayAdjustmentRepository.class)) {
            for (Method method : repository.getDeclaredMethods()) {
                Query query = method.getAnnotation(Query.class);
                if (query != null && !query.nativeQuery()) {
                    out.add(Arguments.of(repository.getSimpleName() + "." + method.getName(),
                            query.value()));
                }
            }
        }
        return out.stream();
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("queries")
    void interprets(String name, String jpql) {
        try (EntityManager em = factory.createEntityManager()) {
            // Throws IllegalArgumentException naming the bad path if the query does not resolve.
            em.createQuery(jpql);
        }
    }

    /**
     * A company's custody copy is the same order a rider already collected, re-held after a
     * hand-over. The platform statement's door-cash figure must leave it out or every carrier
     * order's cash is reported as collected twice — and only the query text can say so without a
     * database, so the predicate is pinned here.
     */
    @Test
    @DisplayName("the platform's door-cash total leaves custody copies out")
    void platformDoorCashExcludesCustodyCopies() throws Exception {
        Query query = CashFloatRepository.class
                .getMethod("totalBetween", CashFloatEntry.Kind.class, java.time.Instant.class,
                        java.time.Instant.class)
                .getAnnotation(Query.class);

        assertThat(query.value()).contains("f.handoverId IS NULL");
    }

    @Test
    @DisplayName("the carrier custody queries are among those checked")
    void theNewQueriesAreCovered() {
        List<String> names = queries().map(a -> (String) a.get()[0]).toList();
        assertThat(names).contains(
                "CashFloatRepository.lockHeldForCarrier",
                "CashFloatRepository.heldByRidersFor",
                "CashFloatRepository.forCarrierBetween",
                "CashFloatRepository.handedOverBetween",
                "CashFloatRepository.custodyReceivedBetween",
                "CashFloatRepository.withRidersByCarrier",
                "CashFloatRepository.outstandingByCreditor",
                "CashFloatRepository.totalBetween",
                "RiderLedgerRepository.jobsForCarrierBetween",
                "RiderLedgerRepository.tipsForCarrierBetween",
                "RiderLedgerRepository.countJobsForCarrierRecordedAfter",
                "CarrierPayRunRepository.lockOwned",
                "CarrierPayRunRepository.overlapping",
                "CarrierPayRunRepository.endingOnOrAfter",
                "CarrierPayAdjustmentRepository.lockAll");
    }

    /**
     * Payroll reads tips for information only. The query must stay on TIP rows of the company's
     * fleet: widened to every row it would put job earnings into the tips column, and a later change
     * that added "tips" to pay would then pay the company's own jobs twice.
     */
    @Test
    @DisplayName("payroll's tip read stays on the company's TIP rows")
    void payrollTipsAreTipsOnly() throws Exception {
        Query query = RiderLedgerRepository.class
                .getMethod("tipsForCarrierBetween", String.class, java.time.Instant.class,
                        java.time.Instant.class)
                .getAnnotation(Query.class);

        assertThat(query.value())
                .contains("RiderLedgerEntry$EntryType.TIP")
                .contains("RiderLedgerEntry$Fleet.CARRIER")
                .contains("e.carrierRef = :carrier");
    }
}

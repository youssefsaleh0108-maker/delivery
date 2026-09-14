package com.delivery.product.domain;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Supplier;

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
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.repository.support.JpaRepositoryFactory;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.orm.jpa.LocalContainerEntityManagerFactoryBean;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;

import com.delivery.platform.outbox.OutboxRecorder;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.api.dto.CatalogDtos.ServiceTermsRequest;
import com.delivery.product.service.CatalogService;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.ProductNotFoundException;
import com.delivery.product.service.OfferModerationService;
import com.delivery.product.service.OfferModerationService.ModeratedOffer;
import com.delivery.product.service.OfferModerationService.Moderator;
import com.delivery.product.service.OfferModerationService.StatusFilter;
import com.delivery.product.service.OnboardingApplicationClient;
import com.delivery.product.service.ServiceCategories;
import com.delivery.product.service.ServiceOfferSearch;
import com.delivery.product.service.StoreService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.tuple;
import static org.mockito.Mockito.mock;

/**
 * V36 and back office's moderation of service offers, against a real PostgreSQL with PostGIS.
 *
 * <p>The unit suite proves which rules the acts apply and which queries they ask. Only a database can
 * prove the rest:
 * <ul>
 *   <li>the hold and its trail commit together or not at all;
 *   <li>{@code chk_product_takedown} refuses a held offer on sale, even when a stale save tries to put it
 *       back;
 *   <li>every customer read leaves a taken-down offer out;
 *   <li>the back office list's optional filters answer what they claim.
 * </ul>
 * Built like {@code ServiceOffersDatabaseTest}, and for the same reason. The entity manager validates
 * every entity against the migrated schema, as the service does at boot ({@code ddl-auto: validate}), so
 * a {@link Product} or {@link OfferModerationAction} that disagreed with V36 fails here before it fails
 * a pod.
 *
 * <p>Runs only when {@code PRODUCT_TEST_DB_URL} names a database a superuser may use, such as a throwaway
 * {@code postgis/postgis:17-3.5} container, and is skipped otherwise. It migrates a schema of its own,
 * with a random name, and drops only that schema:
 *
 * <pre>
 * docker run -d --name product-it -e POSTGRES_PASSWORD=it -p 55433:5432 postgis/postgis:17-3.5
 * PRODUCT_TEST_DB_URL=jdbc:postgresql://localhost:55433/postgres PRODUCT_TEST_DB_PASSWORD=it \
 *     mvn -Dtest=OfferModerationDatabaseTest test
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "PRODUCT_TEST_DB_URL", matches = ".+")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@DisplayName("offer moderation, against a real database")
class OfferModerationDatabaseTest {

    private static final Instant NOW = Instant.now().truncatedTo(ChronoUnit.SECONDS);

    private static final PageRequest PAGE = PageRequest.of(0, 50);

    private static final Moderator OPS = new Moderator("keycloak-sub-ops", "rana.ops");

    private final String url = System.getenv("PRODUCT_TEST_DB_URL");
    private final String user = envOr("PRODUCT_TEST_DB_USER", "postgres");
    private final String password = envOr("PRODUCT_TEST_DB_PASSWORD", "postgres");
    private final String schema = "svc_moderation_it_" + UUID.randomUUID().toString().substring(0, 8);

    /** The acts' clock, moved on before each act, so two acts on one offer are told apart by time. */
    private final SteppingClock moderationClock = new SteppingClock(NOW);

    /** Goods on the schema before V36, by status. */
    private final Map<String, UUID> goodsBeforeV36 = new HashMap<>();

    /** A service shop's offers on the schema before V36, by status. */
    private final Map<String, UUID> offersBeforeV36 = new HashMap<>();

    private UUID grill;
    private UUID oldPress;

    private EntityManagerFactory entityManagerFactory;
    private EntityManager em;
    private ProductRepository products;
    private StoreRepository stores;
    private CatalogService catalog;
    private StoreService storeService;
    private ServiceOfferSearch search;
    private OfferModerationService moderation;

    /** Listed, pinned, open all week, in an open category. */
    private Store press;

    private static String envOr(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isBlank() ? fallback : value;
    }

    // ------------------------------------------------------------------------------------ set-up

    @BeforeAll
    void migrateOverProductsOnSaleThenOpenAPrintShop() throws SQLException {
        try (Connection admin = DriverManager.getConnection(url, user, password);
             Statement statement = admin.createStatement()) {
            // What infra/postgres/init provides on every environment.
            statement.execute("CREATE EXTENSION IF NOT EXISTS postgis");
            statement.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm");
            statement.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"");
            statement.execute("CREATE SCHEMA " + schema);
        }

        // The schema as dev and qa have it with service offers deployed, holding goods and offers in every
        // status they can have.
        flyway(MigrationVersion.fromVersion("35")).migrate();
        grill = insertShop("Hamra Grill", "RESTAURANT", null);
        oldPress = insertShop("Old Town Press", "SERVICES", "PRINTING");
        for (String status : List.of("DRAFT", "ACTIVE", "PAUSED", "ARCHIVED")) {
            if (!status.equals("PAUSED")) {
                goodsBeforeV36.put(status, insertRawProduct(grill, "Grill " + status, status));
            }
            UUID offer = insertRawProduct(oldPress, "Old Town " + status.toLowerCase() + " flyers", status);
            insertRawTerms(offer);
            offersBeforeV36.put(status, offer);
        }

        // Then this change. A CHECK an existing row failed would make this throw.
        flyway(MigrationVersion.LATEST).migrate();

        // Validates every entity against V36, as the service's ddl-auto: validate does at boot.
        entityManagerFactory = entityManagerFactory();
        Wiring wiring = wire(entityManagerFactory.createEntityManager());
        em = wiring.em();
        products = wiring.products();
        stores = wiring.stores();
        catalog = wiring.catalog();
        storeService = wiring.storeService();
        search = wiring.search();
        moderation = wiring.moderation();

        press = transaction(em, () -> {
            Store shop = listed(new Store("merchant-press", "Al Fakhry Press", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING));
            em.persist(shop);
            return shop;
        });
        em.clear();
    }

    @AfterAll
    void dropTheSchema() throws SQLException {
        if (em != null) {
            // A set-up that failed half way leaves its transaction open, and an open transaction holds
            // locks the DROP below would wait on for ever. Closing the manager does not release them.
            close(em);
        }
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

    // ------------------------------------------------------------------------------------ the migration

    @Test
    @DisplayName("V36 applies over goods and offers in every status, and leaves each as it was and not taken down")
    void v36_applies_over_existing_products() throws SQLException {
        assertThat(count("SELECT count(*) FROM flyway_schema_history WHERE version = '36' AND success"))
                .isEqualTo(1);

        Map<String, UUID> before = new HashMap<>();
        goodsBeforeV36.forEach((status, id) -> before.put("goods " + status, id));
        offersBeforeV36.forEach((status, id) -> before.put("offer " + status, id));
        for (Map.Entry<String, UUID> row : before.entrySet()) {
            String status = row.getKey().substring(row.getKey().indexOf(' ') + 1);
            UUID id = row.getValue();
            assertThat(text("SELECT status FROM products WHERE id = '" + id + "'")).as(row.getKey())
                    .isEqualTo(status);
            assertThat(count("SELECT count(*) FROM products WHERE id = '" + id + "' AND taken_down_at IS NULL "
                    + "AND takedown_reason IS NULL AND status_before_takedown IS NULL"))
                    .as(row.getKey()).isEqualTo(1);
            Product read = products.findById(id).orElseThrow();
            assertThat(read.isTakenDown()).as(row.getKey()).isFalse();
            assertThat(read.getStatusBeforeTakedown()).as(row.getKey()).isNull();
            assertThat(count("SELECT count(*) FROM offer_moderation_actions WHERE product_id = '" + id + "'"))
                    .as(row.getKey()).isZero();
        }
        em.clear();

        // Back office lists the offers that were there before, each under its own status, and no goods.
        for (Map.Entry<String, UUID> offer : offersBeforeV36.entrySet()) {
            assertThat(backOfficeNames(StatusFilter.valueOf(offer.getKey()), null, oldPress, null))
                    .containsExactly("Old Town " + offer.getKey().toLowerCase() + " flyers");
        }
        assertThat(backOfficeNames(StatusFilter.TAKEN_DOWN, null, oldPress, null)).isEmpty();
        assertThat(backOfficeNames(null, null, grill, null)).isEmpty();
    }

    @Test
    @DisplayName("the schema refuses a hold that is not whole or on an offer on sale, and a trail row that is not an act")
    void the_schema_refuses_what_no_hold_or_act_can_be() throws SQLException {
        // A shop of its own, so the hold written raw here is in no other test's list.
        UUID refusals = insertShop("Refusals Press", "SERVICES", "PRINTING");
        UUID posters = insertRawProduct(refusals, "Refusals posters", "ACTIVE");
        String row = " WHERE id = '" + posters + "'";

        // A whole hold, but on an offer still on sale.
        assertThatThrownBy(() -> execute("UPDATE products SET taken_down_at = now(), takedown_reason = 'Unsafe', "
                + "status_before_takedown = 'ACTIVE'" + row))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_product_takedown");

        execute("UPDATE products SET status = 'ARCHIVED'" + row);
        // Half a hold, a blank reason, and a status to restore to that no product can have.
        assertThatThrownBy(() -> execute("UPDATE products SET taken_down_at = now()" + row))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_product_takedown");
        assertThatThrownBy(() -> execute("UPDATE products SET taken_down_at = now(), takedown_reason = '   ', "
                + "status_before_takedown = 'ACTIVE'" + row))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_product_takedown");
        assertThatThrownBy(() -> execute("UPDATE products SET taken_down_at = now(), takedown_reason = 'Unsafe', "
                + "status_before_takedown = 'HIDDEN'" + row))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_product_takedown");

        // What a take-down writes is accepted.
        execute("UPDATE products SET taken_down_at = now(), takedown_reason = 'Unsafe', "
                + "status_before_takedown = 'ACTIVE'" + row);
        assertThat(text("SELECT takedown_reason FROM products" + row)).isEqualTo("Unsafe");

        assertThatThrownBy(() -> insertRawAction(posters, refusals, "DELETE", "Unsafe"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_offer_moderation_action");
        assertThatThrownBy(() -> insertRawAction(posters, refusals, "TAKE_DOWN", "   "))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("chk_offer_moderation_reason");
        assertThatThrownBy(() -> insertRawAction(posters, refusals, "TAKE_DOWN", null))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("reason");
        assertThatThrownBy(() -> insertRawAction(UUID.randomUUID(), refusals, "TAKE_DOWN", "Unsafe"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("offer_moderation_actions_product_id_fkey");
        assertThatThrownBy(() -> insertRawAction(posters, UUID.randomUUID(), "TAKE_DOWN", "Unsafe"))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("offer_moderation_actions_store_id_fkey");
        insertRawAction(posters, refusals, "TAKE_DOWN", "Unsafe");
        assertThat(count("SELECT count(*) FROM offer_moderation_actions WHERE product_id = '" + posters + "'"))
                .isEqualTo(1);
    }

    // ------------------------------------------------------------------------------------ the acts

    @Test
    @DisplayName("a taken-down offer leaves every customer read at once, its provider reads why, and the trail is committed with it")
    void taking_an_offer_down_hides_it_from_every_customer_read() throws SQLException {
        UUID poster = transaction(em, () -> {
            Product offer = liveOffer(press, "Poster printing");
            offer.featureAsGift(NOW);
            return offer.getId();
        });
        em.clear();
        // On sale: searched, and on the gift hub.
        assertThat(names(search.search("poster", null, PAGE))).containsExactly("Poster printing");
        assertThat(products.findFeaturedGifts(PAGE)).extracting(Product::getId).contains(poster);
        em.clear();

        Instant at = moderationClock.advance();
        ModeratedOffer takenDown = transaction(em, () ->
                moderation.takeDown(poster, OPS, "  Prints copyrighted film posters.  "));
        em.clear();
        assertThat(takenDown.store().getName()).isEqualTo("Al Fakhry Press");
        assertThat(takenDown.view().service()).isNotNull();

        // Every read a customer's screen, basket or order makes.
        assertThat(search.search("poster", null, PAGE).getTotalElements()).isZero();
        assertThat(names(catalog.browseStore(press.getId(), "customer-sub", null, null, PAGE)))
                .doesNotContain("Poster printing");
        assertThat(catalog.browseStoreByIds(press.getId(), "customer-sub", List.of(poster), PAGE)
                .getTotalElements()).isZero();
        assertThat(catalog.readAllActive(List.of(poster))).isEmpty();
        assertThat(products.findFeaturedGifts(PAGE)).extracting(Product::getId).doesNotContain(poster);
        // The read by id is what its options, its price and its bought-together rail read through, and
        // what order-manager reads with the customer's token before it prices a line.
        assertThatThrownBy(() -> catalog.read(poster, "customer-sub"))
                .isInstanceOf(ProductNotFoundException.class);
        assertThatThrownBy(() -> catalog.read(poster, null))
                .isInstanceOf(ProductNotFoundException.class);
        em.clear();

        // Its provider still reads it, with the reason, on the offer and in their list.
        Product owned = catalog.read(poster, press.getMerchantId());
        assertThat(owned.isTakenDown()).isTrue();
        assertThat(owned.getTakedownReason()).isEqualTo("Prints copyrighted film posters.");
        assertThat(catalog.listOwnedBy(press.getMerchantId(), press.getId(), Product.Status.ARCHIVED, PAGE)
                .getContent()).extracting(Product::getId).contains(poster);
        em.clear();

        // The hold and the trail, as a separate connection reads them once committed.
        assertThat(text("SELECT status || '|' || status_before_takedown || '|' || takedown_reason "
                + "FROM products WHERE id = '" + poster + "'"))
                .isEqualTo("ARCHIVED|ACTIVE|Prints copyrighted film posters.");
        assertThat(instant("SELECT taken_down_at FROM products WHERE id = '" + poster + "'")).isEqualTo(at);
        assertThat(text("SELECT action || '|' || reason || '|' || actor_id || '|' || actor_name || '|' || store_id "
                + "FROM offer_moderation_actions WHERE product_id = '" + poster + "'"))
                .isEqualTo("TAKE_DOWN|Prints copyrighted film posters.|keycloak-sub-ops|rana.ops|" + press.getId());
        assertThat(instant("SELECT created_at FROM offer_moderation_actions WHERE product_id = '" + poster + "'"))
                .isEqualTo(at);
    }

    @Test
    @DisplayName("its provider cannot publish, resume or pause a taken-down offer until back office restores it, and then resumes it")
    void the_provider_cannot_put_it_back_on_sale_until_it_is_restored() throws SQLException {
        String provider = press.getMerchantId();
        UUID stickers = transaction(em, () -> liveOffer(press, "Sticker printing").getId());
        em.clear();
        moderationClock.advance();
        transaction(em, () -> moderation.takeDown(stickers, OPS, "The stickers imitate official vehicle permits."));
        em.clear();

        List<Supplier<Product>> puttingBackOnSale = List.of(
                () -> catalog.publish(stickers, provider),
                () -> catalog.resume(stickers, provider),
                () -> catalog.pause(stickers, provider));
        for (Supplier<Product> act : puttingBackOnSale) {
            assertThatThrownBy(() -> transaction(em, act))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("The stickers imitate official vehicle permits.");
            em.clear();
        }

        // Fixing what back office objected to is allowed, and puts nothing on sale.
        transaction(em, () -> catalog.update(stickers, provider, new ProductRequest(
                "Sticker printing, custom shapes", null, new BigDecimal("15.00"), null, press.getId(), null,
                null, terms())));
        em.clear();
        Product fixed = products.findById(stickers).orElseThrow();
        assertThat(fixed.getName()).isEqualTo("Sticker printing, custom shapes");
        assertThat(fixed.getStatus()).isEqualTo(Product.Status.ARCHIVED);
        assertThat(fixed.isTakenDown()).isTrue();
        em.clear();

        moderationClock.advance();
        ModeratedOffer restored = transaction(em, () -> moderation.restore(stickers,
                new Moderator("keycloak-sub-lead", null), "The provider removed the permit designs."));
        em.clear();
        // Back as it was before the take-down, but paused: its provider decides when it is on sale again.
        assertThat(restored.view().product().getStatus()).isEqualTo(Product.Status.PAUSED);
        assertThat(count("SELECT count(*) FROM products WHERE id = '" + stickers + "' AND status = 'PAUSED' "
                + "AND taken_down_at IS NULL AND takedown_reason IS NULL AND status_before_takedown IS NULL"))
                .isEqualTo(1);
        assertThat(search.search("sticker", null, PAGE).getTotalElements()).isZero();
        assertThat(moderation.history(stickers))
                .extracting(OfferModerationAction::getAction, OfferModerationAction::getActorId,
                        OfferModerationAction::getActorName, OfferModerationAction::getReason)
                .containsExactly(
                        tuple(OfferModerationAction.Action.RESTORE, "keycloak-sub-lead", null,
                                "The provider removed the permit designs."),
                        tuple(OfferModerationAction.Action.TAKE_DOWN, "keycloak-sub-ops", "rana.ops",
                                "The stickers imitate official vehicle permits."));
        em.clear();

        transaction(em, () -> catalog.resume(stickers, provider));
        em.clear();
        assertThat(names(search.search("sticker", null, PAGE))).containsExactly("Sticker printing, custom shapes");
    }

    /**
     * The transaction the trail shares with the act. An actor id longer than its column cannot be
     * written, so the commit fails, and the hold set in the same transaction goes with it.
     */
    @Test
    @DisplayName("when the trail row cannot be written, the offer is not taken down")
    void no_trail_no_take_down() throws SQLException {
        UUID mugs = transaction(em, () -> liveOffer(press, "Mug printing").getId());
        em.clear();

        // Its own entity manager: one whose commit failed is not one the other tests should share.
        Wiring failing = wire(entityManagerFactory.createEntityManager());
        try {
            assertThatThrownBy(() -> transaction(failing.em(), () -> failing.moderation().takeDown(mugs,
                    new Moderator("x".repeat(65), null), "Prints trademarked logos.")))
                    .hasStackTraceContaining("character varying(64)");
        } finally {
            close(failing.em());
        }

        assertThat(count("SELECT count(*) FROM products WHERE id = '" + mugs + "' AND status = 'ACTIVE' "
                + "AND taken_down_at IS NULL AND takedown_reason IS NULL")).isEqualTo(1);
        assertThat(count("SELECT count(*) FROM offer_moderation_actions WHERE product_id = '" + mugs + "'"))
                .isZero();
        assertThat(names(search.search("mug", null, PAGE))).containsExactly("Mug printing");
        em.clear();
    }

    /**
     * Why Product writes only the columns a save changed. Both saves here read the offer before back
     * office took it down. Writing every column, the rename would have written the hold-less row it read
     * back over the hold, and the resume would then have put the offer on sale.
     */
    @Test
    @DisplayName("a provider's save that read the offer before it was taken down keeps the hold, and cannot put it back on sale")
    void a_save_read_before_the_take_down_cannot_undo_it() throws SQLException {
        String provider = press.getMerchantId();
        UUID canvas = transaction(em, () -> {
            Product offer = liveOffer(press, "Canvas printing");
            catalog.pause(offer.getId(), provider);
            return offer.getId();
        });
        em.clear();

        EntityManager renaming = entityManagerFactory.createEntityManager();
        EntityManager resuming = entityManagerFactory.createEntityManager();
        try {
            renaming.getTransaction().begin();
            Product toRename = renaming.find(Product.class, canvas);
            resuming.getTransaction().begin();
            Product toResume = resuming.find(Product.class, canvas);

            moderationClock.advance();
            transaction(em, () -> moderation.takeDown(canvas, OPS, "Reproduces a museum painting without permission."));
            em.clear();

            // A rename writes the name alone, so the hold it never saw stays.
            toRename.update("Canvas prints, framed", toRename.getDescription(), toRename.getPrice(),
                    toRename.getCategoryId(), toRename.getSku(), toRename.getBarcode());
            renaming.getTransaction().commit();

            // A resume writes the status, and the database refuses a held offer on sale.
            toResume.resume();
            assertThatThrownBy(() -> resuming.getTransaction().commit())
                    .hasStackTraceContaining("chk_product_takedown");
        } finally {
            close(renaming);
            close(resuming);
        }

        assertThat(text("SELECT name || '|' || status || '|' || takedown_reason FROM products WHERE id = '"
                + canvas + "'"))
                .isEqualTo("Canvas prints, framed|ARCHIVED|Reproduces a museum painting without permission.");
    }

    // ------------------------------------------------------------------------------------ the list

    @Test
    @DisplayName("back office lists every service offer, and narrows by status, taken down, category, shop and text")
    void back_office_lists_and_narrows_every_service_offer() {
        Map<String, UUID> cedar = new HashMap<>();
        Store[] shops = transaction(em, () -> {
            Store cedarShop = listed(new Store("merchant-cedar", "Cedar Print House", Store.Vertical.SERVICES,
                    Store.ServiceCategory.PRINTING));
            // Never listed, and in a category the launch keeps closed: no customer sees its offers.
            Store tutors = new Store("merchant-tutor", "Bright Tutors", Store.Vertical.SERVICES,
                    Store.ServiceCategory.TUTORING);
            em.persist(cedarShop);
            em.persist(tutors);
            String merchant = cedarShop.getMerchantId();

            cedar.put("live", liveOffer(cedarShop, "Cedar business cards").getId());
            UUID paused = liveOffer(cedarShop, "Cedar letterheads").getId();
            catalog.pause(paused, merchant);
            cedar.put("paused", paused);
            cedar.put("draft", catalog.create(merchant, request(cedarShop, "Cedar envelopes"),
                    StoreService.FirstShop.ALREADY_OPEN).getId());
            UUID archived = liveOffer(cedarShop, "Cedar calendars").getId();
            catalog.archive(archived, merchant);
            cedar.put("archived", archived);
            cedar.put("held", liveOffer(cedarShop, "Cedar stamps").getId());
            liveOffer(tutors, "Algebra lessons");
            return new Store[] {cedarShop, tutors};
        });
        moderationClock.advance();
        transaction(em, () -> moderation.takeDown(cedar.get("held"), OPS, "Sells copies of postage stamps."));
        em.clear();
        UUID cedarShop = shops[0].getId();

        assertThat(backOfficeNames(null, null, cedarShop, null)).containsExactlyInAnyOrder(
                "Cedar business cards", "Cedar letterheads", "Cedar envelopes", "Cedar calendars", "Cedar stamps");
        assertThat(backOfficeNames(StatusFilter.ACTIVE, null, cedarShop, null)).containsExactly("Cedar business cards");
        assertThat(backOfficeNames(StatusFilter.PAUSED, null, cedarShop, null)).containsExactly("Cedar letterheads");
        assertThat(backOfficeNames(StatusFilter.DRAFT, null, cedarShop, null)).containsExactly("Cedar envelopes");
        // Archived by the provider, and taken down by back office, apart.
        assertThat(backOfficeNames(StatusFilter.ARCHIVED, null, cedarShop, null)).containsExactly("Cedar calendars");
        assertThat(backOfficeNames(StatusFilter.TAKEN_DOWN, null, cedarShop, null)).containsExactly("Cedar stamps");

        // A closed category and a shop that never listed, which the customer search leaves out.
        assertThat(search.search("algebra", null, PAGE).getTotalElements()).isZero();
        assertThat(backOfficeNames(null, Store.ServiceCategory.TUTORING, null, null)).containsExactly("Algebra lessons");
        assertThat(backOfficeNames(null, null, shops[1].getId(), null)).containsExactly("Algebra lessons");
        assertThat(backOfficeNames(null, Store.ServiceCategory.TUTORING, cedarShop, null)).isEmpty();

        // Text in the offer's name, in any case, or in its shop's name.
        assertThat(backOfficeNames(null, null, null, "ALGEBRA")).containsExactly("Algebra lessons");
        assertThat(backOfficeNames(null, null, null, "cedar print house")).containsExactlyInAnyOrder(
                "Cedar business cards", "Cedar letterheads", "Cedar envelopes", "Cedar calendars", "Cedar stamps");
        assertThat(backOfficeNames(StatusFilter.TAKEN_DOWN, null, null, "cedar")).containsExactly("Cedar stamps");

        // Never a goods product, by shop or by name.
        assertThat(backOfficeNames(null, null, grill, null)).isEmpty();
        assertThat(backOfficeNames(null, null, null, "grill")).isEmpty();

        // Each offer comes with its shop, its terms and its hold.
        ModeratedOffer stamps = moderation.list(StatusFilter.TAKEN_DOWN, null, cedarShop, null, PAGE)
                .getContent().get(0);
        assertThat(stamps.store().getName()).isEqualTo("Cedar Print House");
        assertThat(stamps.view().service()).isNotNull();
        assertThat(stamps.view().product().getTakedownReason()).isEqualTo("Sells copies of postage stamps.");
        em.clear();

        // Pages of two, newest first. All five were created in one transaction, at one instant, so only the id
        // keeps a page boundary from repeating one offer and losing another.
        Set<UUID> seen = new HashSet<>();
        List<Integer> sizes = new ArrayList<>();
        for (int page = 0; page < 3; page++) {
            Page<ModeratedOffer> offers = moderation.list(null, null, cedarShop, null,
                    PageRequest.of(page, 2, Sort.by(Sort.Direction.DESC, "createdAt")));
            assertThat(offers.getTotalElements()).isEqualTo(5);
            assertThat(offers.getTotalPages()).isEqualTo(3);
            sizes.add(offers.getNumberOfElements());
            offers.getContent().forEach(offer -> seen.add(offer.view().product().getId()));
            em.clear();
        }
        assertThat(sizes).containsExactly(2, 2, 1);
        assertThat(seen).containsExactlyInAnyOrderElementsOf(cedar.values());
    }

    // ------------------------------------------------------------------------------------ Verified Local

    @Test
    @DisplayName("back office grants and withdraws Verified Local on a service shop, as on any shop")
    void verified_local_is_a_service_shops_badge_too() {
        assertThat(transaction(em, () -> storeService.setVerifiedLocal(press.getId(), "keycloak-sub-ops", true))
                .store().isVerifiedLocal()).isTrue();
        em.clear();
        assertThat(stores.findById(press.getId()).orElseThrow().isVerifiedLocal()).isTrue();
        em.clear();

        transaction(em, () -> storeService.setVerifiedLocal(press.getId(), "keycloak-sub-ops", false));
        em.clear();
        assertThat(stores.findById(press.getId()).orElseThrow().isVerifiedLocal()).isFalse();
        em.clear();
    }

    // ------------------------------------------------------------------------------------ helpers

    /** The catalogue's services over one entity manager, wired as the service wires them. */
    private record Wiring(EntityManager em, ProductRepository products, StoreRepository stores,
                          CatalogService catalog, StoreService storeService, ServiceOfferSearch search,
                          OfferModerationService moderation) {
    }

    private Wiring wire(EntityManager manager) {
        JpaRepositoryFactory repositories = new JpaRepositoryFactory(manager);
        StoreRepository storeRepository = repositories.getRepository(StoreRepository.class);
        ProductRepository productRepository = repositories.getRepository(ProductRepository.class);
        CategoryRepository categories = repositories.getRepository(CategoryRepository.class);
        ServiceTermsRepository serviceTerms = repositories.getRepository(ServiceTermsRepository.class);

        StoreService shops = new StoreService(storeRepository,
                repositories.getRepository(StoreOfferRepository.class),
                repositories.getRepository(StoreFavoriteRepository.class), productRepository, categories,
                new ServiceCategories(new MockEnvironment()), mock(OnboardingApplicationClient.class),
                Clock.fixed(NOW, ZoneOffset.UTC), Duration.ofHours(4));
        CatalogService catalogService = new CatalogService(productRepository, categories, shops,
                mock(OutboxRecorder.class), storeRepository, serviceTerms,
                repositories.getRepository(StoreDeliveryZoneRepository.class),
                repositories.getRepository(ProductOptionGroupRepository.class),
                new ServiceCategories(new MockEnvironment()));
        return new Wiring(manager, productRepository, storeRepository, catalogService, shops,
                new ServiceOfferSearch(productRepository, new ServiceCategories(new MockEnvironment())),
                new OfferModerationService(productRepository, storeRepository, serviceTerms,
                        repositories.getRepository(OfferModerationActionRepository.class), catalogService,
                        mock(OutboxRecorder.class), moderationClock));
    }

    /** A clock the tests move on, one minute before each act. */
    private static final class SteppingClock extends Clock {

        private Instant now;

        SteppingClock(Instant start) {
            this.now = start;
        }

        /** Moves on a minute, and says to what. */
        Instant advance() {
            now = now.plus(Duration.ofMinutes(1));
            return now;
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }

    /** Created, given a photo and published through the catalogue, as a pickup print offer. */
    private Product liveOffer(Store shop, String name) {
        Product offer = catalog.create(shop.getMerchantId(), request(shop, name),
                StoreService.FirstShop.ALREADY_OPEN);
        offer.addImage("products/" + UUID.randomUUID() + ".jpg");
        return catalog.publish(offer.getId(), shop.getMerchantId());
    }

    private static ProductRequest request(Store shop, String name) {
        return new ProductRequest(name, null, new BigDecimal("15.00"), null, shop.getId(), null, null, terms());
    }

    private static ServiceTermsRequest terms() {
        return new ServiceTermsRequest(ServiceTerms.PricingType.FIXED, "cards", 500, 24, 48,
                ServiceTerms.Fulfilment.PICKUP, ServiceTerms.AttachmentPolicy.NONE, null);
    }

    /** Listed, pinned and open all week. */
    private static Store listed(Store store) {
        store.pinAt(GeoPoint.of(33.898200d, 35.482500d));
        store.replaceHours(Arrays.stream(DayOfWeek.values())
                .map(day -> new StoreHours(day, LocalTime.MIDNIGHT, LocalTime.of(23, 59, 59)))
                .toList());
        store.publish(NOW.minus(Duration.ofDays(30)));
        return store;
    }

    private static List<String> names(Page<Product> page) {
        return page.getContent().stream().map(Product::getName).toList();
    }

    private List<String> backOfficeNames(StatusFilter status, Store.ServiceCategory category, UUID storeId,
                                         String text) {
        List<String> names = moderation.list(status, category, storeId, text, PAGE).getContent().stream()
                .map(offer -> offer.view().product().getName())
                .toList();
        em.clear();
        return names;
    }

    private static <T> T transaction(EntityManager manager, Supplier<T> work) {
        manager.getTransaction().begin();
        try {
            T result = work.get();
            manager.getTransaction().commit();
            return result;
        } catch (RuntimeException e) {
            if (manager.getTransaction().isActive()) {
                manager.getTransaction().rollback();
            }
            throw e;
        }
    }

    private static void close(EntityManager manager) {
        if (manager.getTransaction().isActive()) {
            manager.getTransaction().rollback();
        }
        manager.close();
    }

    private Flyway flyway(MigrationVersion target) {
        return Flyway.configure()
                .dataSource(url, user, password)
                .schemas(schema)
                .defaultSchema(schema)
                // The locations and the ordering rule application.yml gives the service.
                .locations("classpath:db/migration/shared", "classpath:db/migration/product")
                .outOfOrder(true)
                .target(target)
                .load();
    }

    private EntityManagerFactory entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean factory = new LocalContainerEntityManagerFactoryBean();
        factory.setDataSource(new DriverManagerDataSource(urlInSchema(), user, password));
        factory.setPackagesToScan("com.delivery.product.domain");
        factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        Map<String, Object> jpa = new HashMap<>();
        // What the service boots with: Flyway owns the schema, and Hibernate refuses to start if an
        // entity has drifted from it.
        jpa.put("hibernate.hbm2ddl.auto", "validate");
        jpa.put("hibernate.default_schema", schema);
        // Not the service's hibernate.jdbc.time_zone=UTC, for the reason ServicesVerticalDatabaseTest
        // gives: on a machine outside UTC it shifts the all-week opening hours past chk_hours_order.
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

    private Connection connection() throws SQLException {
        return DriverManager.getConnection(urlInSchema(), user, password);
    }

    private long count(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getLong(1);
        }
    }

    private String text(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getString(1);
        }
    }

    private Instant instant(String sql) throws SQLException {
        try (Connection connection = connection();
             Statement statement = connection.createStatement();
             ResultSet rows = statement.executeQuery(sql)) {
            rows.next();
            return rows.getObject(1, OffsetDateTime.class).toInstant();
        }
    }

    private void execute(String sql) throws SQLException {
        try (Connection connection = connection(); Statement statement = connection.createStatement()) {
            statement.execute(sql);
        }
    }

    /** A shop as the schema before V36 holds it: a goods shop, or a service shop with its category. */
    private UUID insertShop(String name, String vertical, String serviceCategory) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO stores (id, merchant_id, name, slug, vertical, service_category, status, "
                             + "published_at) VALUES (?, 'merchant-it', ?, ?, ?, ?, 'ACTIVE', now())")) {
            UUID id = UUID.randomUUID();
            insert.setObject(1, id);
            insert.setString(2, name);
            insert.setString(3, "it-" + id);
            insert.setString(4, vertical);
            insert.setString(5, serviceCategory);
            insert.executeUpdate();
            return id;
        }
    }

    /** A product as the schema before V36 holds it, with a photo. */
    private UUID insertRawProduct(UUID storeId, String name, String status) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO products (id, merchant_id, store_id, name, price, status, image_refs) "
                             + "VALUES (?, 'merchant-it', ?, ?, 16.00, ?, '[\"products/it.jpg\"]'::jsonb)")) {
            UUID id = UUID.randomUUID();
            insert.setObject(1, id);
            insert.setObject(2, storeId);
            insert.setString(3, name);
            insert.setString(4, status);
            insert.executeUpdate();
            return id;
        }
    }

    private void insertRawTerms(UUID productId) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO service_terms (product_id, pricing_type, unit_label, unit_size, "
                             + "turnaround_min_hours, turnaround_max_hours, fulfilment_modes) "
                             + "VALUES (?, 'FIXED', 'flyers', 100, 24, 48, 'PICKUP')")) {
            insert.setObject(1, productId);
            insert.executeUpdate();
        }
    }

    private void insertRawAction(UUID productId, UUID storeId, String action, String reason) throws SQLException {
        try (Connection connection = connection();
             PreparedStatement insert = connection.prepareStatement(
                     "INSERT INTO offer_moderation_actions (id, product_id, store_id, action, reason, actor_id) "
                             + "VALUES (?, ?, ?, ?, ?, 'keycloak-sub-ops')")) {
            insert.setObject(1, UUID.randomUUID());
            insert.setObject(2, productId);
            insert.setObject(3, storeId);
            insert.setString(4, action);
            insert.setString(5, reason);
            insert.executeUpdate();
        }
    }
}

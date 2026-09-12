package com.delivery.product.api;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.ThrowingConsumer;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InOrder;
import org.mockito.Mockito;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import com.delivery.product.api.dto.CatalogDtos.PresignUploadRequest;
import com.delivery.product.api.dto.CatalogScanDtos.CommitRequest;
import com.delivery.product.api.dto.CatalogScanDtos.ItemEditRequest;
import com.delivery.product.domain.CatalogScan;
import com.delivery.product.service.CatalogScanAnalyzer;
import com.delivery.product.service.CatalogScanService;
import com.delivery.product.service.CatalogScanService.CatalogScanNotFoundException;
import com.delivery.product.service.CatalogScanService.ScanDetails;
import com.delivery.product.service.ProductImageService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Who may call Merchant Blitz, proved through the real method-security proxy.
 *
 * <p>The controller is built inside a Spring context with method security switched on, so the
 * {@code @PreAuthorize} on the class actually runs — a test that constructed the controller by hand
 * would pass even if the annotation were deleted. Every endpoint is then asked by every party that
 * is not a merchant, and must refuse before the service is reached.
 *
 * <p>The second half is the other merchant: role alone would let any merchant read any scan, so the
 * controller must hand the service the caller's own {@code sub} — never an id from the request —
 * and the service's "not found" must surface as a 404.
 */
@DisplayName("who may call Merchant Blitz")
class CatalogScanAccessTest {

    private static final UUID SCAN = UUID.randomUUID();
    private static final UUID FILE = UUID.randomUUID();
    private static final UUID ITEM = UUID.randomUUID();

    @Configuration
    @EnableMethodSecurity
    static class Wiring {

        @Bean
        CatalogScanService catalogScanService() {
            return mock(CatalogScanService.class);
        }

        @Bean
        CatalogScanAnalyzer catalogScanAnalyzer() {
            return mock(CatalogScanAnalyzer.class);
        }

        @Bean
        ProductImageService productImageService() {
            return mock(ProductImageService.class);
        }

        @Bean
        CatalogScanController catalogScanController(CatalogScanService scans,
                                                    CatalogScanAnalyzer analyzer,
                                                    ProductImageService images) {
            return new CatalogScanController(scans, analyzer, images);
        }
    }

    private static AnnotationConfigApplicationContext context;

    private CatalogScanController controller;
    private CatalogScanService scans;
    private CatalogScanAnalyzer analyzer;

    @BeforeAll
    static void boot() {
        context = new AnnotationConfigApplicationContext(Wiring.class);
    }

    @AfterAll
    static void shutDown() {
        context.close();
    }

    @BeforeEach
    void wire() {
        controller = context.getBean(CatalogScanController.class);
        scans = context.getBean(CatalogScanService.class);
        analyzer = context.getBean(CatalogScanAnalyzer.class);
        Mockito.reset(scans, analyzer);
    }

    @AfterEach
    void signOut() {
        SecurityContextHolder.clearContext();
    }

    private static void signInAs(String subject, String... authorities) {
        Jwt token = Jwt.withTokenValue("token").header("alg", "none").subject(subject).build();
        SecurityContextHolder.getContext().setAuthentication(
                new JwtAuthenticationToken(token, AuthorityUtils.createAuthorityList(authorities)));
    }

    private static List<ThrowingConsumer<CatalogScanController>> everyEndpoint() {
        return List.of(
                c -> c.create(null),
                c -> c.presignPhoto(SCAN, new PresignUploadRequest("image/jpeg")),
                c -> c.confirmPhoto(SCAN, FILE),
                c -> c.analyze(SCAN),
                c -> c.read(SCAN),
                c -> c.updateItem(SCAN, ITEM, new ItemEditRequest("Pepsi", null, null)),
                c -> c.rejectItem(SCAN, ITEM),
                c -> c.commit(SCAN, new CommitRequest(List.of(), List.of())));
    }

    private static ScanDetails emptyScan() {
        return new ScanDetails(new CatalogScan("merchant-sub", UUID.randomUUID()),
                CatalogScan.Status.UPLOADING, null, List.of(), List.of(), 6, 2, 4);
    }

    /**
     * An employee is a MERCHANT_STAFF token, not MERCHANT: shop staff sell and count, they do not
     * spend the owner's scan quota or create catalogue lines from photos.
     */
    @ParameterizedTest
    @ValueSource(strings = {"ROLE_CUSTOMER", "ROLE_MERCHANT_STAFF", "ROLE_RIDER", "ROLE_CARRIER",
            "ROLE_BACKOFFICE"})
    void every_endpoint_refuses_anyone_who_is_not_a_merchant(String role) {
        signInAs("not-a-merchant", role);

        for (ThrowingConsumer<CatalogScanController> endpoint : everyEndpoint()) {
            assertThatThrownBy(() -> endpoint.accept(controller))
                    .isInstanceOf(AccessDeniedException.class);
        }
        verifyNoInteractions(scans, analyzer);
    }

    @Test
    void a_merchant_reaches_the_service_as_themselves() {
        signInAs("merchant-sub", "ROLE_MERCHANT");
        when(scans.read(SCAN, "merchant-sub")).thenReturn(emptyScan());

        assertThat(controller.read(SCAN).status()).isEqualTo(CatalogScan.Status.UPLOADING);
        verify(scans).read(SCAN, "merchant-sub");
    }

    /** Somebody else's scan id: the caller's own sub goes to the service, and the answer is a 404. */
    @Test
    void another_merchants_scan_is_not_found_for_the_caller() {
        signInAs("intruder-sub", "ROLE_MERCHANT");
        when(scans.read(SCAN, "intruder-sub"))
                .thenThrow(new CatalogScanNotFoundException("Scan " + SCAN + " was not found"));

        CatalogScanNotFoundException refused = org.junit.jupiter.api.Assertions.assertThrows(
                CatalogScanNotFoundException.class, () -> controller.read(SCAN));
        verify(scans).read(SCAN, "intruder-sub");

        ProblemDetail problem = new ApiExceptionHandler().onScanNotFound(refused);
        assertThat(problem.getStatus()).isEqualTo(HttpStatus.NOT_FOUND.value());
    }

    /** The job is queued only after the transaction that marked the scan ANALYZING has returned. */
    @Test
    void analysis_is_queued_only_after_the_scan_has_been_marked() {
        signInAs("merchant-sub", "ROLE_MERCHANT");
        when(scans.startAnalysis(SCAN, "merchant-sub"))
                .thenReturn(new CatalogScanService.Started(emptyScan(), 3));

        controller.analyze(SCAN);

        InOrder order = Mockito.inOrder(scans, analyzer);
        order.verify(scans).startAnalysis(SCAN, "merchant-sub");
        order.verify(analyzer).submit(SCAN, 3);
    }

    @Test
    void a_refused_analysis_never_queues_a_job() {
        signInAs("merchant-sub", "ROLE_MERCHANT");
        when(scans.startAnalysis(SCAN, "merchant-sub"))
                .thenThrow(new CatalogScanService.ScanStateException("already analysing"));

        assertThatThrownBy(() -> controller.analyze(SCAN))
                .isInstanceOf(CatalogScanService.ScanStateException.class);
        verify(analyzer, never()).submit(any(), anyInt());
    }

    @Test
    void the_daily_limit_is_a_429_with_the_limit_in_the_body() {
        ProblemDetail problem = new ApiExceptionHandler()
                .onScanQuota(new CatalogScanService.ScanQuotaExceededException(5));

        assertThat(problem.getStatus()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS.value());
        assertThat(problem.getProperties()).containsEntry("limit", 5);
    }
}

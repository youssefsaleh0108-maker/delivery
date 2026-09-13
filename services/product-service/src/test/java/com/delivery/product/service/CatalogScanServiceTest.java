package com.delivery.product.service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.function.Executable;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;

import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.platform.storage.StorageService;
import com.delivery.product.api.dto.CatalogDtos.ProductRequest;
import com.delivery.product.domain.CatalogScan;
import com.delivery.product.domain.CatalogScanItem;
import com.delivery.product.domain.CatalogScanItemRepository;
import com.delivery.product.domain.CatalogScanPhoto;
import com.delivery.product.domain.CatalogScanPhotoRepository;
import com.delivery.product.domain.CatalogScanRepository;
import com.delivery.product.domain.Category;
import com.delivery.product.domain.CategoryRepository;
import com.delivery.product.domain.Product;
import com.delivery.product.domain.Store;
import com.delivery.product.service.CatalogScanService.Acceptance;
import com.delivery.product.service.CatalogScanService.AnalysisJob;
import com.delivery.product.service.CatalogScanService.CatalogScanNotFoundException;
import com.delivery.product.service.CatalogScanService.CategoryChoice;
import com.delivery.product.service.CatalogScanService.Limits;
import com.delivery.product.service.CatalogScanService.PhotoRef;
import com.delivery.product.service.CatalogScanService.ScanDetails;
import com.delivery.product.service.CatalogScanService.ScanQuotaExceededException;
import com.delivery.product.service.CatalogScanService.ScanStateException;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.CatalogService.CategoryNotFoundException;
import com.delivery.product.service.StoreService.StoreNotFoundException;
import com.delivery.product.vision.VisionProvider.Box;
import com.delivery.product.vision.VisionProvider.Detection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * Merchant Blitz, as a merchant drives it: start, upload, analyse, decide.
 *
 * <p>What is held down here is mostly about who and how much. A merchant must never read, feed or
 * decide another merchant's scan, and must never land a product in somebody else's shop. The quota
 * and the attempt cap exist because every analysis is a paid call once a real provider is on. And
 * the last word — an accepted line is a DRAFT, never published — is the owner's decision, pinned so
 * a later "quick win" cannot quietly put a model's reading of a shelf in front of customers.
 */
@DisplayName("Merchant Blitz catalogue scans")
class CatalogScanServiceTest {

    private static final String MERCHANT = "merchant-sub";
    private static final String OTHER = "other-merchant-sub";
    private static final Instant NOW = Instant.parse("2026-09-11T10:00:00Z");
    private static final Duration STALE = Duration.ofMinutes(10);

    private CatalogScanRepository scans;
    private CatalogScanPhotoRepository photos;
    private CatalogScanItemRepository items;
    private CategoryRepository categories;
    private StoreService stores;
    private StorageService storage;
    private CatalogService catalog;
    private CatalogScanService service;
    private Store store;

    @BeforeEach
    void setUp() {
        scans = mock(CatalogScanRepository.class);
        photos = mock(CatalogScanPhotoRepository.class);
        items = mock(CatalogScanItemRepository.class);
        categories = mock(CategoryRepository.class);
        stores = mock(StoreService.class);
        storage = mock(StorageService.class);
        catalog = mock(CatalogService.class);
        service = new CatalogScanService(scans, photos, items, categories, stores, storage, catalog,
                Clock.fixed(NOW, ZoneOffset.UTC), new Limits(6, 5, 2, 120, STALE));
        store = new Store(MERCHANT, "Corner Shop", Store.Vertical.RESTAURANT);

        when(scans.save(any(CatalogScan.class))).thenAnswer(call -> call.getArgument(0));
        when(photos.save(any(CatalogScanPhoto.class))).thenAnswer(call -> call.getArgument(0));
        when(items.save(any(CatalogScanItem.class))).thenAnswer(call -> call.getArgument(0));
        when(scans.findByIdAndMerchantId(any(UUID.class), anyString())).thenReturn(Optional.empty());
        when(scans.lockOwned(any(UUID.class), anyString())).thenReturn(Optional.empty());
        when(photos.findByScanIdOrderByPositionAsc(any(UUID.class))).thenReturn(List.of());
        when(items.findByScanIdOrderByPositionAsc(any(UUID.class))).thenReturn(List.of());
    }

    private CatalogScan owned(CatalogScan scan) {
        when(scans.findByIdAndMerchantId(scan.getId(), MERCHANT)).thenReturn(Optional.of(scan));
        when(scans.lockOwned(scan.getId(), MERCHANT)).thenReturn(Optional.of(scan));
        when(scans.findById(scan.getId())).thenReturn(Optional.of(scan));
        return scan;
    }

    private CatalogScan uploading() {
        return owned(new CatalogScan(MERCHANT, store.getId()));
    }

    private CatalogScan complete() {
        CatalogScan scan = new CatalogScan(MERCHANT, store.getId());
        scan.startAnalysis(NOW, 2, STALE);
        scan.complete("FAKE", NOW);
        return owned(scan);
    }

    private CatalogScanPhoto uploadedPhoto(CatalogScan scan) {
        CatalogScanPhoto photo = new CatalogScanPhoto(scan.getId(), UUID.randomUUID(),
                "scans/" + scan.getId() + "/shelf.jpg", 0);
        photo.markUploaded();
        when(photos.findByScanIdOrderByPositionAsc(scan.getId())).thenReturn(List.of(photo));
        return photo;
    }

    private CatalogScanItem pendingLine(CatalogScan scan) {
        CatalogScanItem item = new CatalogScanItem(scan.getId(), UUID.randomUUID(), 0, "Pepsi 1L",
                "Pepsi", "1 L", null, new BigDecimal("0.900"), new BigDecimal("1.20"), null);
        when(items.findByIdAndScanId(item.getId(), scan.getId())).thenReturn(Optional.of(item));
        return item;
    }

    @Nested
    @DisplayName("starting a scan")
    class Starting {

        @Test
        void it_is_filed_under_the_callers_own_store() {
            when(stores.requireStoreFor(MERCHANT)).thenReturn(store);

            ScanDetails details = service.create(MERCHANT, null);

            assertThat(details.scan().getMerchantId()).isEqualTo(MERCHANT);
            assertThat(details.scan().getStoreId()).isEqualTo(store.getId());
            assertThat(details.status()).isEqualTo(CatalogScan.Status.UPLOADING);
            assertThat(details.scansLeftToday()).isEqualTo(4);
        }

        /** Naming a competitor's shop gets the same answer as naming no shop at all. */
        @Test
        void another_merchants_store_is_not_found_and_nothing_is_created() {
            Store theirs = new Store(OTHER, "Their Shop", Store.Vertical.RESTAURANT);
            when(stores.ownedBy(MERCHANT)).thenReturn(List.of(store));

            assertThatThrownBy(() -> service.create(MERCHANT, theirs.getId()))
                    .isInstanceOf(StoreNotFoundException.class);
            verify(scans, never()).save(any());
            verify(scans, never()).countByMerchantIdAndCreatedAtAfter(any(), any());
        }

        /**
         * Counted under the merchant's lock, so two starts racing each other cannot both see the last
         * free slot — and counted over a rolling day, so a burst cannot straddle midnight.
         */
        @Test
        void the_daily_quota_is_counted_under_the_lock_and_refuses_the_sixth() {
            when(stores.requireStoreFor(MERCHANT)).thenReturn(store);
            when(scans.countByMerchantIdAndCreatedAtAfter(MERCHANT, NOW.minus(Duration.ofHours(24))))
                    .thenReturn(5L);

            assertThatThrownBy(() -> service.create(MERCHANT, null))
                    .isInstanceOf(ScanQuotaExceededException.class)
                    .satisfies(e -> assertThat(((ScanQuotaExceededException) e).getLimit()).isEqualTo(5));

            InOrder order = inOrder(scans);
            order.verify(scans).lockMerchant(MERCHANT);
            order.verify(scans).countByMerchantIdAndCreatedAtAfter(MERCHANT, NOW.minus(Duration.ofHours(24)));
            verify(scans, never()).save(any());
        }

        /**
         * The quota counts every store a merchant owns, so the lock must be the merchant's: starts in
         * two of their shops queue on the one lock. A lock per store — what this used to take — let
         * parallel starts in different shops each see room for one more.
         */
        @Test
        void starts_in_two_of_a_merchants_stores_queue_on_the_same_merchant_lock() {
            Store second = new Store(MERCHANT, "Second Shop", Store.Vertical.RESTAURANT);
            when(stores.ownedBy(MERCHANT)).thenReturn(List.of(store, second));

            service.create(MERCHANT, store.getId());
            service.create(MERCHANT, second.getId());

            InOrder order = inOrder(scans);
            for (int start = 0; start < 2; start++) {
                order.verify(scans).lockMerchant(MERCHANT);
                order.verify(scans).countByMerchantIdAndCreatedAtAfter(MERCHANT, NOW.minus(Duration.ofHours(24)));
                order.verify(scans).save(any(CatalogScan.class));
            }
            verify(scans, org.mockito.Mockito.times(2)).lockMerchant(MERCHANT);
        }
    }

    @Nested
    @DisplayName("adding photos")
    class Photos {

        @Test
        void a_photo_is_presigned_into_the_scans_own_folder_and_waits_to_be_confirmed() {
            CatalogScan scan = uploading();
            UUID fileId = UUID.randomUUID();
            when(photos.countByScanId(scan.getId())).thenReturn(2L);
            when(storage.presignUpload(MERCHANT, FilePurpose.PRODUCT_IMAGE, "image/jpeg",
                    "scans/" + scan.getId())).thenReturn(new PresignedUpload(fileId, "http://put",
                    "scans/" + scan.getId() + "/f.jpg", "product-images", "image/jpeg", NOW, 10L));

            service.presignPhoto(scan.getId(), MERCHANT, "image/jpeg");

            ArgumentCaptor<CatalogScanPhoto> saved = ArgumentCaptor.forClass(CatalogScanPhoto.class);
            verify(photos).save(saved.capture());
            assertThat(saved.getValue().getFileId()).isEqualTo(fileId);
            assertThat(saved.getValue().getPosition()).isEqualTo(2);
            assertThat(saved.getValue().isUploaded()).isFalse();
        }

        /** The cap counts presigned URLs, so it cannot be walked round by never confirming. */
        @Test
        void the_seventh_photo_is_refused_before_any_url_exists() {
            CatalogScan scan = uploading();
            when(photos.countByScanId(scan.getId())).thenReturn(6L);

            assertThatThrownBy(() -> service.presignPhoto(scan.getId(), MERCHANT, "image/jpeg"))
                    .isInstanceOf(CatalogRuleViolationException.class)
                    .hasMessageContaining("6");
            verifyNoInteractions(storage);
        }

        @Test
        void a_format_the_server_cannot_read_is_refused() {
            CatalogScan scan = uploading();

            assertThatThrownBy(() -> service.presignPhoto(scan.getId(), MERCHANT, "application/pdf"))
                    .isInstanceOf(CatalogRuleViolationException.class);
            verifyNoInteractions(storage);
        }

        @Test
        void no_photo_may_be_added_once_analysis_has_started() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);
            service.startAnalysis(scan.getId(), MERCHANT);

            assertThatThrownBy(() -> service.presignPhoto(scan.getId(), MERCHANT, "image/jpeg"))
                    .isInstanceOf(ScanStateException.class);
        }

        @Test
        void confirming_checks_the_file_belongs_to_the_caller_and_then_trusts_it() {
            CatalogScan scan = uploading();
            CatalogScanPhoto photo = new CatalogScanPhoto(scan.getId(), UUID.randomUUID(), "scans/k.jpg", 0);
            when(photos.findByScanIdAndFileId(scan.getId(), photo.getFileId())).thenReturn(Optional.of(photo));

            service.confirmPhoto(scan.getId(), MERCHANT, photo.getFileId());

            verify(storage).confirmUpload(photo.getFileId(), MERCHANT);
            assertThat(photo.isUploaded()).isTrue();
        }

        /** Even the caller's own upload, if another scan issued it. */
        @Test
        void a_file_this_scan_did_not_issue_is_not_found_and_storage_is_never_asked() {
            CatalogScan scan = uploading();
            UUID foreign = UUID.randomUUID();
            when(photos.findByScanIdAndFileId(scan.getId(), foreign)).thenReturn(Optional.empty());

            assertThatThrownBy(() -> service.confirmPhoto(scan.getId(), MERCHANT, foreign))
                    .isInstanceOf(CatalogScanNotFoundException.class);
            verifyNoInteractions(storage);
        }
    }

    /**
     * Every entry point, asked by a merchant who does not own the scan. All answer "not found" — a
     * 403 would confirm the id is real — and none of them touches storage or the catalogue.
     */
    @Test
    void another_merchant_can_do_nothing_at_all_with_a_scan() {
        CatalogScan scan = complete();
        CatalogScanItem line = pendingLine(scan);

        List<Executable> attempts = List.of(
                () -> service.read(scan.getId(), OTHER),
                () -> service.presignPhoto(scan.getId(), OTHER, "image/jpeg"),
                () -> service.confirmPhoto(scan.getId(), OTHER, UUID.randomUUID()),
                () -> service.startAnalysis(scan.getId(), OTHER),
                () -> service.updateItem(scan.getId(), OTHER, line.getId(), "Mine now",
                        new BigDecimal("1.00"), null),
                () -> service.rejectItem(scan.getId(), OTHER, line.getId()),
                () -> service.commit(scan.getId(), OTHER,
                        List.of(new Acceptance(line.getId(), "Mine now", new BigDecimal("1.00"), null)),
                        List.of()));

        for (Executable attempt : attempts) {
            assertThatThrownBy(attempt::execute).isInstanceOf(CatalogScanNotFoundException.class);
        }
        verifyNoInteractions(storage, catalog);
        assertThat(line.getStatus()).isEqualTo(CatalogScanItem.Status.PENDING);
    }

    @Nested
    @DisplayName("analysing")
    class Analysing {

        @Test
        void there_must_be_a_confirmed_photo_to_read() {
            CatalogScan scan = uploading();

            assertThatThrownBy(() -> service.startAnalysis(scan.getId(), MERCHANT))
                    .isInstanceOf(ScanStateException.class);
            assertThat(scan.getAnalysisAttempts()).isZero();
        }

        /** Two taps together must not queue two paid calls. */
        @Test
        void a_scan_already_being_analysed_is_not_started_again() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);

            assertThat(service.startAnalysis(scan.getId(), MERCHANT).attempt()).isEqualTo(1);
            assertThat(scan.getStatus()).isEqualTo(CatalogScan.Status.ANALYZING);
            assertThatThrownBy(() -> service.startAnalysis(scan.getId(), MERCHANT))
                    .isInstanceOf(ScanStateException.class);
            verify(scans, org.mockito.Mockito.atLeastOnce()).lockOwned(scan.getId(), MERCHANT);
        }

        @Test
        void a_failed_scan_may_be_retried_but_not_past_the_attempt_cap() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);

            int first = service.startAnalysis(scan.getId(), MERCHANT).attempt();
            service.recordFailure(scan.getId(), first, CatalogScan.FailureCode.PROVIDER_ERROR);
            int second = service.startAnalysis(scan.getId(), MERCHANT).attempt();
            service.recordFailure(scan.getId(), second, CatalogScan.FailureCode.PROVIDER_ERROR);

            assertThat(second).isEqualTo(2);
            assertThatThrownBy(() -> service.startAnalysis(scan.getId(), MERCHANT))
                    .isInstanceOf(ScanStateException.class)
                    .hasMessageContaining("start a new scan");
        }

        /**
         * One reading at a time per merchant: the analyser's pool is shared by every shop, and a few
         * accounts firing scans side by side must not turn everybody else's into BUSY. Checked under
         * the merchant's lock; a reading lost with its pod stops counting once stale.
         */
        @Test
        void a_merchant_has_one_scan_read_at_a_time() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);
            when(scans.countOtherLiveAnalyses(MERCHANT, scan.getId(), CatalogScan.Status.ANALYZING,
                    NOW.minus(STALE))).thenReturn(1L);

            assertThatThrownBy(() -> service.startAnalysis(scan.getId(), MERCHANT))
                    .isInstanceOf(ScanStateException.class);
            assertThat(scan.getStatus()).isEqualTo(CatalogScan.Status.UPLOADING);
            assertThat(scan.getAnalysisAttempts()).isZero();
            InOrder order = inOrder(scans);
            order.verify(scans).lockMerchant(MERCHANT);
            order.verify(scans).countOtherLiveAnalyses(MERCHANT, scan.getId(),
                    CatalogScan.Status.ANALYZING, NOW.minus(STALE));

            // Once the other reading has finished, or gone stale, this one starts.
            when(scans.countOtherLiveAnalyses(MERCHANT, scan.getId(), CatalogScan.Status.ANALYZING,
                    NOW.minus(STALE))).thenReturn(0L);
            assertThat(service.startAnalysis(scan.getId(), MERCHANT).attempt()).isEqualTo(1);
        }

        /** Nothing was sent while the queue was full, so the attempt comes back for the retry. */
        @Test
        void a_busy_refusal_fails_the_scan_but_gives_the_attempt_back() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);
            int attempt = service.startAnalysis(scan.getId(), MERCHANT).attempt();

            service.recordBusy(scan.getId(), attempt);

            ScanDetails read = service.read(scan.getId(), MERCHANT);
            assertThat(read.status()).isEqualTo(CatalogScan.Status.FAILED);
            assertThat(read.failure()).isEqualTo(CatalogScan.FailureCode.BUSY);
            assertThat(read.attemptsLeft()).isEqualTo(2);
            assertThat(service.startAnalysis(scan.getId(), MERCHANT).attempt()).isEqualTo(1);
        }

        @Test
        void a_busy_refusal_for_an_attempt_that_has_moved_on_changes_nothing() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);
            int first = service.startAnalysis(scan.getId(), MERCHANT).attempt();
            service.recordFailure(scan.getId(), first, CatalogScan.FailureCode.PROVIDER_ERROR);
            service.startAnalysis(scan.getId(), MERCHANT);

            service.recordBusy(scan.getId(), first);

            assertThat(scan.getStatus()).isEqualTo(CatalogScan.Status.ANALYZING);
            assertThat(scan.getAnalysisAttempts()).isEqualTo(2);
        }

        /** A job lost with its pod must not leave the merchant watching a scan line forever. */
        @Test
        void an_analysis_lost_with_its_pod_reads_as_interrupted_and_may_be_restarted() {
            CatalogScan scan = new CatalogScan(MERCHANT, store.getId());
            scan.startAnalysis(NOW.minus(Duration.ofHours(1)), 2, STALE);
            owned(scan);
            uploadedPhoto(scan);

            ScanDetails read = service.read(scan.getId(), MERCHANT);
            assertThat(read.status()).isEqualTo(CatalogScan.Status.FAILED);
            assertThat(read.failure()).isEqualTo(CatalogScan.FailureCode.INTERRUPTED);

            assertThat(service.startAnalysis(scan.getId(), MERCHANT).attempt()).isEqualTo(2);
        }

        @Test
        void lines_are_stored_against_their_photo_with_only_offered_sections_resolved() {
            CatalogScan scan = uploading();
            CatalogScanPhoto photo = uploadedPhoto(scan);
            int attempt = service.startAnalysis(scan.getId(), MERCHANT).attempt();
            UUID ownSection = UUID.randomUUID();
            UUID platformDrinks = UUID.randomUUID();
            AnalysisJob job = new AnalysisJob(scan.getId(), attempt,
                    List.of(new PhotoRef(photo.getId(), "product-images", photo.getObjectKey())),
                    List.of(new CategoryChoice(ownSection, "Cold Drinks", true),
                            new CategoryChoice(platformDrinks, "Drinks", false)));

            service.recordDetections(job, "CLAUDE", List.of(
                    new Detection(0, "Pepsi 1L", "Pepsi", "1 L", " cold drinks ", 0.93,
                            new BigDecimal("1.20"), new Box(0.1, 0.1, 0.2, 0.2)),
                    new Detection(0, "Mystery Tin", "", "", "Frozen Goods", 0.4, null, null)));

            ArgumentCaptor<CatalogScanItem> saved = ArgumentCaptor.forClass(CatalogScanItem.class);
            verify(items, org.mockito.Mockito.times(2)).save(saved.capture());
            assertThat(saved.getAllValues()).allSatisfy(item ->
                    assertThat(item.getPhotoId()).isEqualTo(photo.getId()));
            assertThat(saved.getAllValues().get(0).getCategoryId()).isEqualTo(ownSection);
            // Never an id the provider made up: an unmatched suggestion stays empty.
            assertThat(saved.getAllValues().get(1).getCategoryId()).isNull();
            // The guess stays a guess. The server never sets the price.
            assertThat(saved.getAllValues().get(0).getPriceGuess()).isEqualByComparingTo("1.20");
            assertThat(saved.getAllValues().get(0).getPrice()).isNull();

            assertThat(scan.getStatus()).isEqualTo(CatalogScan.Status.COMPLETE);
            assertThat(scan.getProvider()).isEqualTo("CLAUDE");
        }

        /** A job presumed lost that finishes after its successor started must not overwrite it. */
        @Test
        void a_late_result_from_an_earlier_attempt_is_discarded() {
            CatalogScan scan = uploading();
            CatalogScanPhoto photo = uploadedPhoto(scan);
            int first = service.startAnalysis(scan.getId(), MERCHANT).attempt();
            service.recordFailure(scan.getId(), first, CatalogScan.FailureCode.PROVIDER_ERROR);
            service.startAnalysis(scan.getId(), MERCHANT);

            service.recordDetections(new AnalysisJob(scan.getId(), first,
                    List.of(new PhotoRef(photo.getId(), "b", "k")), List.of()), "FAKE",
                    List.of(new Detection(0, "Pepsi", "", "", "", 0.9, null, null)));
            service.recordFailure(scan.getId(), first, CatalogScan.FailureCode.REFUSED);

            verify(items, never()).save(any());
            assertThat(scan.getStatus()).isEqualTo(CatalogScan.Status.ANALYZING);
        }
    }

    @Nested
    @DisplayName("deciding lines")
    class Deciding {

        @Test
        void an_accepted_line_becomes_a_draft_in_the_scans_own_store_and_is_never_published() {
            CatalogScan scan = complete();
            CatalogScanItem line = pendingLine(scan);
            UUID section = UUID.randomUUID();
            Product draft = new Product(MERCHANT, store.getId(), "Pepsi 1L", null,
                    new BigDecimal("1.25"), section);
            when(catalog.create(eq(MERCHANT), any(ProductRequest.class))).thenReturn(draft);

            service.commit(scan.getId(), MERCHANT,
                    List.of(new Acceptance(line.getId(), "  Pepsi 1L ", new BigDecimal("1.25"), section)),
                    List.of());

            ArgumentCaptor<ProductRequest> request = ArgumentCaptor.forClass(ProductRequest.class);
            verify(catalog).create(eq(MERCHANT), request.capture());
            assertThat(request.getValue().storeId()).isEqualTo(store.getId());
            assertThat(request.getValue().name()).isEqualTo("Pepsi 1L");
            // The merchant's price, not the model's guess of 1.20.
            assertThat(request.getValue().price()).isEqualByComparingTo("1.25");
            assertThat(request.getValue().categoryId()).isEqualTo(section);

            assertThat(line.getStatus()).isEqualTo(CatalogScanItem.Status.ACCEPTED);
            assertThat(line.getProductId()).isEqualTo(draft.getId());
            assertThat(draft.getStatus()).isEqualTo(Product.Status.DRAFT);
            verify(catalog, never()).publish(any(), anyString());
        }

        @Test
        void a_free_item_or_a_fraction_of_a_cent_is_refused_and_nothing_is_created() {
            CatalogScan scan = complete();
            CatalogScanItem line = pendingLine(scan);

            for (String price : new String[] {"0.00", "-1.00", "1.205"}) {
                assertThatThrownBy(() -> service.commit(scan.getId(), MERCHANT,
                        List.of(new Acceptance(line.getId(), "Pepsi", new BigDecimal(price), null)),
                        List.of()))
                        .as(price)
                        .isInstanceOf(CatalogRuleViolationException.class);
            }
            assertThatThrownBy(() -> service.commit(scan.getId(), MERCHANT,
                    List.of(new Acceptance(line.getId(), "Pepsi", null, null)), List.of()))
                    .isInstanceOf(CatalogRuleViolationException.class);
            verifyNoInteractions(catalog);
            assertThat(line.getStatus()).isEqualTo(CatalogScanItem.Status.PENDING);
        }

        @Test
        void a_line_already_decided_cannot_be_accepted_twice() {
            CatalogScan scan = complete();
            CatalogScanItem line = pendingLine(scan);
            service.rejectItem(scan.getId(), MERCHANT, line.getId());

            assertThatThrownBy(() -> service.commit(scan.getId(), MERCHANT,
                    List.of(new Acceptance(line.getId(), "Pepsi", new BigDecimal("1.00"), null)),
                    List.of()))
                    .isInstanceOf(ScanStateException.class);
            verifyNoInteractions(catalog);
        }

        @Test
        void the_same_line_twice_in_one_review_is_refused() {
            CatalogScan scan = complete();
            CatalogScanItem line = pendingLine(scan);

            assertThatThrownBy(() -> service.commit(scan.getId(), MERCHANT,
                    List.of(new Acceptance(line.getId(), "Pepsi", new BigDecimal("1.00"), null)),
                    List.of(line.getId())))
                    .isInstanceOf(CatalogRuleViolationException.class);
            verifyNoInteractions(catalog);
        }

        @Test
        void nothing_can_be_decided_before_the_scan_has_lines() {
            CatalogScan scan = uploading();

            assertThatThrownBy(() -> service.commit(scan.getId(), MERCHANT, List.of(), List.of()))
                    .isInstanceOf(ScanStateException.class);
        }

        /** A competitor's shelf is indistinguishable from an id that was never issued. */
        @Test
        void a_line_cannot_be_filed_under_another_shops_section() {
            CatalogScan scan = complete();
            CatalogScanItem line = pendingLine(scan);
            Category theirs = new Category(UUID.randomUUID(), "Their Drinks", null, (short) 0);
            when(categories.findById(theirs.getId())).thenReturn(Optional.of(theirs));

            assertThatThrownBy(() -> service.updateItem(scan.getId(), MERCHANT, line.getId(),
                    "Pepsi", new BigDecimal("1.00"), theirs.getId()))
                    .isInstanceOf(CategoryNotFoundException.class);
            assertThat(line.getCategoryId()).isNull();
        }

        @Test
        void an_edit_is_saved_without_deciding_the_line() {
            CatalogScan scan = complete();
            CatalogScanItem line = pendingLine(scan);

            service.updateItem(scan.getId(), MERCHANT, line.getId(), " Pepsi 1L Can ",
                    new BigDecimal("1.10"), null);

            assertThat(line.getName()).isEqualTo("Pepsi 1L Can");
            assertThat(line.getPrice()).isEqualByComparingTo("1.10");
            assertThat(line.getStatus()).isEqualTo(CatalogScanItem.Status.PENDING);
        }
    }

    /**
     * What the screen asks on opening, so a scan it lost — an app killed mid-capture, a merchant who
     * left during the reading, a reloaded tab — is carried on rather than stranded with its photos, a
     * share of the day's allowance and a paid reading.
     */
    @Nested
    @DisplayName("picking a scan up again")
    class Resuming {

        private final Instant since = NOW.minus(Duration.ofHours(24));

        private CatalogScan failed(int attempts) {
            CatalogScan scan = new CatalogScan(MERCHANT, store.getId());
            for (int i = 0; i < attempts; i++) {
                scan.startAnalysis(NOW, 2, STALE);
                scan.fail(CatalogScan.FailureCode.PROVIDER_ERROR, NOW);
            }
            return scan;
        }

        private CatalogScan completeWith(boolean aLineStillWaits) {
            CatalogScan scan = new CatalogScan(MERCHANT, store.getId());
            scan.startAnalysis(NOW, 2, STALE);
            scan.complete("CLAUDE", NOW);
            when(items.existsByScanIdAndStatus(scan.getId(), CatalogScanItem.Status.PENDING))
                    .thenReturn(aLineStillWaits);
            return scan;
        }

        private void recent(String merchant, CatalogScan... newestFirst) {
            when(scans.findByMerchantIdAndCreatedAtAfterOrderByCreatedAtDesc(merchant, since))
                    .thenReturn(List.of(newestFirst));
        }

        /** Finished scans are passed over; the newest one the merchant can still act on answers. */
        @Test
        void the_newest_scan_still_waiting_on_the_merchant_is_the_one_picked_up() {
            CatalogScan waiting = completeWith(true);
            CatalogScan olderStillUploading = new CatalogScan(MERCHANT, store.getId());
            recent(MERCHANT, completeWith(false), failed(2), waiting, olderStillUploading);

            ScanDetails details = service.current(MERCHANT, null).orElseThrow();

            assertThat(details.scan()).isSameAs(waiting);
            assertThat(details.status()).isEqualTo(CatalogScan.Status.COMPLETE);
            // All four in the window count against today's five.
            assertThat(details.scansLeftToday()).isEqualTo(1);
        }

        @Test
        void photos_to_add_a_reading_under_way_or_lost_and_a_retry_left_all_count_as_waiting() {
            CatalogScan uploading = new CatalogScan(MERCHANT, store.getId());
            recent(MERCHANT, uploading);
            assertThat(service.current(MERCHANT, null).orElseThrow().scan()).isSameAs(uploading);

            CatalogScan reading = new CatalogScan(MERCHANT, store.getId());
            reading.startAnalysis(NOW.minusSeconds(30), 2, STALE);
            recent(MERCHANT, reading);
            assertThat(service.current(MERCHANT, null).orElseThrow().status())
                    .isEqualTo(CatalogScan.Status.ANALYZING);

            // Lost with its pod: reported as interrupted and restartable, so worth coming back to.
            CatalogScan lost = new CatalogScan(MERCHANT, store.getId());
            lost.startAnalysis(NOW.minus(Duration.ofHours(1)), 2, STALE);
            recent(MERCHANT, lost);
            ScanDetails interrupted = service.current(MERCHANT, null).orElseThrow();
            assertThat(interrupted.failure()).isEqualTo(CatalogScan.FailureCode.INTERRUPTED);
            assertThat(interrupted.attemptsLeft()).isEqualTo(1);

            CatalogScan retryable = failed(1);
            recent(MERCHANT, retryable);
            assertThat(service.current(MERCHANT, null).orElseThrow().scan()).isSameAs(retryable);
        }

        /** Offering a dead end again would only stand between the merchant and a new scan. */
        @Test
        void a_finished_scan_is_not_offered_again() {
            recent(MERCHANT, failed(2), completeWith(false));

            assertThat(service.current(MERCHANT, null)).isEmpty();
        }

        @Test
        void a_named_store_narrows_the_search_to_that_store() {
            Store second = new Store(MERCHANT, "Second Shop", Store.Vertical.RESTAURANT);
            CatalogScan elsewhere = new CatalogScan(MERCHANT, second.getId());
            CatalogScan here = new CatalogScan(MERCHANT, store.getId());
            recent(MERCHANT, elsewhere, here);

            assertThat(service.current(MERCHANT, store.getId()).orElseThrow().scan()).isSameAs(here);
            assertThat(service.current(MERCHANT, null).orElseThrow().scan()).isSameAs(elsewhere);
        }

        /** By the caller's own id, over the quota's day: another merchant's scan never answers. */
        @Test
        void the_lookup_is_the_callers_own_and_never_finds_another_merchants_scan() {
            recent(MERCHANT, new CatalogScan(MERCHANT, store.getId()));

            assertThat(service.current(OTHER, store.getId())).isEmpty();
            verify(scans).findByMerchantIdAndCreatedAtAfterOrderByCreatedAtDesc(OTHER, since);
            verify(scans, never()).findByMerchantIdAndCreatedAtAfterOrderByCreatedAtDesc(eq(MERCHANT), any());
        }
    }

    /**
     * Shelf photos are a picture of the merchant's stock room in a public-read bucket, so once no line
     * waits on them they go. Best effort: a photo that will not delete never undoes a save that has
     * already happened — the bucket's expiry rule takes it.
     */
    @Nested
    @DisplayName("letting shelf photos go")
    class Discarding {

        private CatalogScanPhoto photo(CatalogScan scan, int position) {
            CatalogScanPhoto photo = new CatalogScanPhoto(scan.getId(), UUID.randomUUID(),
                    "scans/" + scan.getId() + "/" + position + ".jpg", position);
            photo.markUploaded();
            return photo;
        }

        @Test
        void once_every_line_is_decided_every_photo_is_deleted_as_its_owner() {
            CatalogScan scan = complete();
            CatalogScanPhoto first = photo(scan, 0);
            CatalogScanPhoto second = photo(scan, 1);
            when(photos.findByScanIdOrderByPositionAsc(scan.getId())).thenReturn(List.of(first, second));

            service.discardPhotosOnceDecided(scan.getId(), MERCHANT);

            verify(storage).softDelete(first.getFileId(), MERCHANT);
            verify(storage).softDelete(second.getFileId(), MERCHANT);
        }

        @Test
        void while_a_line_still_waits_the_photos_stay() {
            CatalogScan scan = complete();
            when(photos.findByScanIdOrderByPositionAsc(scan.getId())).thenReturn(List.of(photo(scan, 0)));
            when(items.existsByScanIdAndStatus(scan.getId(), CatalogScanItem.Status.PENDING)).thenReturn(true);

            service.discardPhotosOnceDecided(scan.getId(), MERCHANT);

            verifyNoInteractions(storage);
        }

        @Test
        void a_scan_still_taking_photos_keeps_them() {
            CatalogScan scan = uploading();
            uploadedPhoto(scan);

            service.discardPhotosOnceDecided(scan.getId(), MERCHANT);

            verifyNoInteractions(storage);
        }

        @Test
        void a_photo_that_will_not_delete_does_not_stop_the_rest_or_undo_the_save() {
            CatalogScan scan = complete();
            CatalogScanPhoto stuck = photo(scan, 0);
            CatalogScanPhoto next = photo(scan, 1);
            when(photos.findByScanIdOrderByPositionAsc(scan.getId())).thenReturn(List.of(stuck, next));
            org.mockito.Mockito.doThrow(new IllegalStateException("storage is down"))
                    .when(storage).softDelete(stuck.getFileId(), MERCHANT);

            ScanDetails details = service.discardPhotosOnceDecided(scan.getId(), MERCHANT);

            verify(storage).softDelete(next.getFileId(), MERCHANT);
            assertThat(details.status()).isEqualTo(CatalogScan.Status.COMPLETE);
        }

        @Test
        void another_merchants_scan_is_not_found_and_nothing_is_deleted() {
            CatalogScan scan = complete();

            assertThatThrownBy(() -> service.discardPhotosOnceDecided(scan.getId(), OTHER))
                    .isInstanceOf(CatalogScanNotFoundException.class);
            verifyNoInteractions(storage);
        }
    }

    /** A box ending on the photo's edge must not round a hair past it and fail the whole scan. */
    @Test
    void a_box_rounded_for_storage_still_fits_inside_its_photo() {
        CatalogScanItem.Box box = CatalogScanService.toBox(new Box(0.33335, 0.00004, 0.66667, 0.99999));

        assertThat(box.left().add(box.width())).isLessThanOrEqualTo(BigDecimal.ONE);
        assertThat(box.top().add(box.height())).isLessThanOrEqualTo(BigDecimal.ONE);
        assertThat(CatalogScanService.toBox(null)).isNull();
    }
}

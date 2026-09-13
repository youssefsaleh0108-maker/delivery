package com.delivery.product.service;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.delivery.product.domain.CatalogScan.FailureCode;
import com.delivery.product.service.CatalogScanService.AnalysisJob;
import com.delivery.product.service.CatalogScanService.CategoryChoice;
import com.delivery.product.service.CatalogScanService.PhotoRef;
import com.delivery.product.vision.VisionException;
import com.delivery.product.vision.VisionProvider;
import com.delivery.product.vision.VisionProvider.Detection;
import com.delivery.product.vision.VisionProvider.ShelfPhoto;
import com.delivery.product.vision.VisionProviders;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The background half of a scan: read the photos, shrink them, ask the provider, write down what
 * happened — and turn every way that can go wrong into a code on the scan rather than a stuck one.
 */
@DisplayName("analysing a scan off the request thread")
class CatalogScanAnalyzerTest {

    private static final UUID SCAN = UUID.randomUUID();
    private static final UUID PHOTO = UUID.randomUUID();
    private static final int MAX_EDGE = 800;
    private static final Executor INLINE = Runnable::run;

    private CatalogScanService scans;
    private VisionProviders providers;
    private VisionProvider provider;
    private ImageObjectStore objects;
    private AnalysisJob job;

    @BeforeEach
    void setUp() {
        scans = mock(CatalogScanService.class);
        providers = mock(VisionProviders.class);
        provider = mock(VisionProvider.class);
        objects = mock(ImageObjectStore.class);
        when(providers.active()).thenReturn(provider);
        when(provider.name()).thenReturn("FAKE");

        job = new AnalysisJob(SCAN, 1,
                List.of(new PhotoRef(PHOTO, "product-images", "scans/s/shelf.png")),
                List.of(new CategoryChoice(UUID.randomUUID(), "Drinks", true)));
        when(scans.loadForAnalysis(SCAN, 1)).thenReturn(Optional.of(job));
    }

    private CatalogScanAnalyzer analyzer(Executor executor) {
        return new CatalogScanAnalyzer(scans, providers, objects, new Thumbnailer(40_000_000L),
                executor, MAX_EDGE);
    }

    private static byte[] png(int width, int height) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "png", out);
        return out.toByteArray();
    }

    /** The provider reads images at about this size; sending a phone's original is paying for pixels. */
    @Test
    void photos_are_shrunk_to_the_configured_edge_before_the_provider_sees_them() throws IOException {
        when(objects.read("product-images", "scans/s/shelf.png")).thenReturn(png(2400, 1200));
        List<Detection> lines = List.of(new Detection(0, "Pepsi", "", "", "", 0.9, null, null));
        when(provider.detect(anyList(), anyList())).thenReturn(lines);

        analyzer(INLINE).submit(SCAN, 1);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<ShelfPhoto>> sent = ArgumentCaptor.forClass(List.class);
        verify(provider).detect(sent.capture(), eq(List.of("Drinks")));
        BufferedImage prepared = ImageIO.read(new ByteArrayInputStream(sent.getValue().get(0).jpeg()));
        assertThat(prepared.getWidth()).isEqualTo(MAX_EDGE);
        assertThat(prepared.getHeight()).isEqualTo(MAX_EDGE / 2);

        verify(scans).recordDetections(job, "FAKE", lines);
        verify(scans, never()).recordFailure(any(), anyInt(), any());
    }

    /**
     * A portrait photo as a phone camera stores it — landscape pixels and a tag to turn them — goes
     * to the provider upright: the frame the merchant's screen draws it in, and so the frame its
     * boxes have to come back in.
     */
    @Test
    void a_camera_photo_tagged_to_be_turned_reaches_the_provider_upright() throws IOException {
        when(objects.read(any(), any())).thenReturn(TaggedJpeg.of(2400, 1200, 6, false));
        when(provider.detect(anyList(), anyList())).thenReturn(List.of());

        analyzer(INLINE).submit(SCAN, 1);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<ShelfPhoto>> sent = ArgumentCaptor.forClass(List.class);
        verify(provider).detect(sent.capture(), anyList());
        BufferedImage prepared = ImageIO.read(new ByteArrayInputStream(sent.getValue().get(0).jpeg()));
        assertThat(prepared.getWidth()).isEqualTo(MAX_EDGE / 2);
        assertThat(prepared.getHeight()).isEqualTo(MAX_EDGE);
        // The corner stored top-left is where a quarter turn clockwise puts it: top right.
        assertThat(TaggedJpeg.isRed(prepared.getRGB(MAX_EDGE / 2 - 10, 10))).isTrue();
    }

    @Test
    void an_unreadable_photo_fails_the_scan_without_spending_a_provider_call() {
        when(objects.read(any(), any())).thenReturn("not an image".getBytes());

        analyzer(INLINE).submit(SCAN, 1);

        verify(scans).recordFailure(SCAN, 1, FailureCode.UNREADABLE_PHOTO);
        verifyNoInteractions(providers);
    }

    @Test
    void a_provider_that_declines_is_recorded_as_refused() throws IOException {
        when(objects.read(any(), any())).thenReturn(png(100, 100));
        when(provider.detect(anyList(), anyList()))
                .thenThrow(new VisionException(VisionException.Reason.REFUSED, "declined"));

        analyzer(INLINE).submit(SCAN, 1);

        verify(scans).recordFailure(SCAN, 1, FailureCode.REFUSED);
    }

    @Test
    void a_provider_that_cannot_be_reached_is_a_provider_error_not_a_stuck_scan() throws IOException {
        when(objects.read(any(), any())).thenReturn(png(100, 100));
        when(provider.detect(anyList(), anyList()))
                .thenThrow(new IllegalStateException("socket closed"));

        analyzer(INLINE).submit(SCAN, 1);

        verify(scans).recordFailure(SCAN, 1, FailureCode.PROVIDER_ERROR);
    }

    /** A backlog of paid calls behind a slow provider is worse than an honest "busy, try again". */
    @Test
    void a_full_queue_fails_the_scan_as_busy_at_once() {
        analyzer(runnable -> {
            throw new RejectedExecutionException("full");
        }).submit(SCAN, 1);

        verify(scans).recordFailure(SCAN, 1, FailureCode.BUSY);
        verifyNoInteractions(objects, providers);
    }

    @Test
    void a_job_whose_scan_has_moved_on_does_nothing() {
        when(scans.loadForAnalysis(SCAN, 1)).thenReturn(Optional.empty());

        analyzer(INLINE).submit(SCAN, 1);

        verifyNoInteractions(objects, providers);
        verify(scans, never()).recordFailure(any(), anyInt(), any());
    }
}

package com.delivery.product.service;

import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import javax.imageio.ImageIO;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.service.PhotoSearchException.Refusal;
import com.delivery.product.vision.VisionException;
import com.delivery.product.vision.VisionProvider;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Reading one photo on a request thread: the slots, the order in which the use is counted, and what
 * each provider outcome becomes.
 */
@DisplayName("reading a photo")
class PhotoReaderTest {

    private final Thumbnailer thumbnailer = new Thumbnailer(40_000_000L);

    static byte[] jpeg(int width, int height) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        for (int x = 0; x < width; x += 7) {
            image.setRGB(x, height / 2, 0xCC2200);
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            ImageIO.write(image, "jpg", out);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        return out.toByteArray();
    }

    /** A provider that answers "Pepsi 1L" and remembers what it was sent. */
    private static final class Answering implements VisionProvider {
        private final AtomicReference<byte[]> sent = new AtomicReference<>();
        private final List<String> events;
        private final VisionProvider.ProductDescription answer;

        Answering(List<String> events, ProductDescription answer) {
            this.events = events;
            this.answer = answer;
        }

        @Override
        public String name() {
            return "STUB";
        }

        @Override
        public List<Detection> detect(List<ShelfPhoto> photos, List<String> categoryNames) {
            throw new AssertionError("photo search never reads shelves");
        }

        @Override
        public ProductDescription describe(ProductPhoto photo) {
            events.add("provider");
            sent.set(photo.jpeg());
            return answer;
        }
    }

    private static VisionProvider.ProductDescription pepsi(String barcode) {
        return new VisionProvider.ProductDescription(true, "Pepsi 1L", "بيبسي", "Pepsi", "1 L",
                List.of("cola"), barcode, 0.9);
    }

    private static VisionProvider failing(VisionException.Reason reason) {
        return new VisionProvider() {
            @Override
            public String name() {
                return "STUB";
            }

            @Override
            public List<Detection> detect(List<ShelfPhoto> photos, List<String> categoryNames) {
                throw new AssertionError();
            }

            @Override
            public ProductDescription describe(ProductPhoto photo) {
                throw new VisionException(reason, "stand-in");
            }
        };
    }

    @Test
    @DisplayName("the use is counted after the photo is decoded and just before the provider is asked")
    void the_use_is_counted_just_before_the_provider() {
        List<String> events = new ArrayList<>();
        PhotoReader reader = new PhotoReader(thumbnailer, 4, 1568, 16_000_000L);

        PhotoReader.Reading reading = reader.read(jpeg(640, 480), new Answering(events, pepsi(null)), () -> {
            events.add("counted");
            return 7;
        });

        assertThat(events).containsExactly("counted", "provider");
        assertThat(reading.left()).isEqualTo(7);
        assertThat(reading.description().name()).isEqualTo("Pepsi 1L");
    }

    @Test
    @DisplayName("the provider is sent an upright JPEG no longer than 1568 px on its long edge")
    void the_provider_gets_a_jpeg_at_most_1568_px() throws IOException {
        Answering provider = new Answering(new ArrayList<>(), pepsi(null));

        new PhotoReader(thumbnailer, 4, 1568, 16_000_000L).read(jpeg(3000, 1000), provider, () -> 9);

        BufferedImage sent = ImageIO.read(new ByteArrayInputStream(provider.sent.get()));
        assertThat(sent.getWidth()).isEqualTo(1568);
        assertThat(provider.sent.get()[0]).isEqualTo((byte) 0xFF);
        assertThat(provider.sent.get()[1]).isEqualTo((byte) 0xD8);
    }

    @Test
    @DisplayName("what the provider says is sanitised: a barcode with a wrong check digit is dropped")
    void the_answer_is_sanitised() {
        PhotoReader.Reading reading = new PhotoReader(thumbnailer, 4, 1568, 16_000_000L)
                .read(jpeg(64, 64), new Answering(new ArrayList<>(), pepsi("5449000000997")), () -> 9);

        assertThat(reading.description().barcode()).isNull();
    }

    @Test
    @DisplayName("a photo that will not decode is PHOTO_UNREADABLE, and is neither counted nor sent")
    void an_unreadable_photo_costs_nothing() {
        List<String> events = new ArrayList<>();
        PhotoReader reader = new PhotoReader(thumbnailer, 4, 1568, 16_000_000L);
        byte[] notAPicture = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 1, 2, 3};

        assertThatThrownBy(() -> reader.read(notAPicture, new Answering(events, pepsi(null)), () -> {
            events.add("counted");
            return 0;
        })).isInstanceOfSatisfying(PhotoSearchException.class,
                e -> assertThat(e.refusal()).isEqualTo(Refusal.UNREADABLE));
        assertThat(events).isEmpty();
        assertThat(reader.freeSlots()).isEqualTo(4);
    }

    @Test
    @DisplayName("a photo larger than the reader's pixel budget is refused before it is decoded")
    void a_photo_over_the_pixel_budget_is_unreadable() {
        PhotoReader reader = new PhotoReader(thumbnailer, 4, 1568, 10_000L);

        assertThatThrownBy(() -> reader.read(jpeg(200, 100), new Answering(new ArrayList<>(), pepsi(null)),
                () -> 0)).isInstanceOfSatisfying(PhotoSearchException.class,
                e -> assertThat(e.refusal()).isEqualTo(Refusal.UNREADABLE));
    }

    @Test
    @DisplayName("a limit reached is passed on, and the provider is never asked")
    void a_limit_stops_the_call() {
        List<String> events = new ArrayList<>();

        assertThatThrownBy(() -> new PhotoReader(thumbnailer, 4, 1568, 16_000_000L).read(jpeg(64, 64),
                new Answering(events, pepsi(null)), () -> {
                    throw PhotoSearchException.limit(false, 10, PhotoSearchException.Scope.DAY, 60);
                })).isInstanceOfSatisfying(PhotoSearchException.class,
                e -> assertThat(e.refusal()).isEqualTo(Refusal.SEARCH_LIMIT));
        assertThat(events).isEmpty();
    }

    @Test
    @DisplayName("a refusal is PHOTO_REFUSED, a failure PHOTO_READER_FAILED, a missing key unavailable")
    void provider_outcomes_become_refusals() {
        PhotoReader reader = new PhotoReader(thumbnailer, 4, 1568, 16_000_000L);
        byte[] photo = jpeg(64, 64);

        assertThatThrownBy(() -> reader.read(photo, failing(VisionException.Reason.REFUSED), () -> 1))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.refusal()).isEqualTo(Refusal.REFUSED);
                    assertThat(e.refusal().status()).isEqualTo(422);
                });
        assertThatThrownBy(() -> reader.read(photo, failing(VisionException.Reason.PROVIDER_ERROR), () -> 1))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.refusal()).isEqualTo(Refusal.FAILED);
                    assertThat(e.refusal().status()).isEqualTo(502);
                });
        assertThatThrownBy(() -> reader.read(photo, failing(VisionException.Reason.NOT_CONFIGURED), () -> 1))
                .isInstanceOfSatisfying(PhotoSearchException.class,
                        e -> assertThat(e.refusal()).isEqualTo(Refusal.UNAVAILABLE));
        // Every slot came back.
        assertThat(reader.freeSlots()).isEqualTo(4);
    }

    /**
     * No request ever waits for a slot: with every slot held by a read in progress, the next photo is
     * answered at once with 503 and a Retry-After, and is not counted.
     */
    @Test
    @DisplayName("with every slot taken the next photo is PHOTO_READER_BUSY at once, uncounted")
    void a_full_reader_answers_busy_at_once() throws Exception {
        PhotoReader reader = new PhotoReader(thumbnailer, 1, 1568, 16_000_000L);
        CountDownLatch inProvider = new CountDownLatch(1);
        CountDownLatch release = new CountDownLatch(1);
        VisionProvider slow = new VisionProvider() {
            @Override
            public String name() {
                return "SLOW";
            }

            @Override
            public List<Detection> detect(List<ShelfPhoto> photos, List<String> categoryNames) {
                throw new AssertionError();
            }

            @Override
            public ProductDescription describe(ProductPhoto photo) {
                inProvider.countDown();
                try {
                    release.await(10, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                return pepsi(null);
            }
        };
        byte[] photo = jpeg(64, 64);
        CompletableFuture<PhotoReader.Reading> first =
                CompletableFuture.supplyAsync(() -> reader.read(photo, slow, () -> 5));
        assertThat(inProvider.await(10, TimeUnit.SECONDS)).isTrue();

        AtomicInteger counted = new AtomicInteger();
        assertThatThrownBy(() -> reader.read(photo, slow, counted::incrementAndGet))
                .isInstanceOfSatisfying(PhotoSearchException.class, e -> {
                    assertThat(e.refusal()).isEqualTo(Refusal.BUSY);
                    assertThat(e.refusal().status()).isEqualTo(503);
                    assertThat(e.getRetryAfterSeconds()).isEqualTo(PhotoReader.BUSY_RETRY_AFTER_SECONDS);
                });
        assertThat(counted).hasValue(0);

        release.countDown();
        assertThat(first.get(10, TimeUnit.SECONDS).left()).isEqualTo(5);
        assertThat(reader.freeSlots()).isEqualTo(1);
    }
}

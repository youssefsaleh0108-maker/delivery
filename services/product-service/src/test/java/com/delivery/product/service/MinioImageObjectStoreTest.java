package com.delivery.product.service;

import java.io.ByteArrayInputStream;
import java.util.Arrays;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import io.minio.GetObjectArgs;
import io.minio.GetObjectResponse;
import io.minio.MinioClient;
import okhttp3.Headers;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Reading an object's bytes, never more than the upload limit.
 *
 * <p>Confirm checks a photo's size once, but its presigned PUT stays usable until it expires, so a
 * confirmed photo can be replaced with something far larger afterwards. The read is where that
 * would land on the heap — before the thumbnailer's pixel budget could look at it — so the read is
 * where the limit is applied again. Shelf photos and product thumbnails share this read.
 */
@DisplayName("reading an image object")
class MinioImageObjectStoreTest {

    private static final long LIMIT = 1_000;
    private static final String BUCKET = "product-images";
    private static final String KEY = "scans/s/photo.jpg";

    private final MinioClient client = mock(MinioClient.class);
    private final MinioImageObjectStore store = new MinioImageObjectStore(client, LIMIT);

    /** What storage sends back — the whole object, whatever range was asked for. */
    private ByteArrayInputStream storageSends(byte[] bytes) throws Exception {
        ByteArrayInputStream body = new ByteArrayInputStream(bytes);
        when(client.getObject(any(GetObjectArgs.class)))
                .thenReturn(new GetObjectResponse(Headers.of(), BUCKET, "", KEY, body));
        return body;
    }

    @Test
    void an_object_at_the_limit_is_read_whole() throws Exception {
        byte[] photo = new byte[(int) LIMIT];
        Arrays.fill(photo, (byte) 7);
        storageSends(photo);

        assertThat(store.read(BUCKET, KEY)).isEqualTo(photo);
    }

    /**
     * Replaced after confirm with something fifty times the limit: refused, without being read in
     * full — even from a storage that ignored the range and sent the lot.
     */
    @Test
    void an_object_grown_past_the_limit_since_it_was_confirmed_is_refused_unread() throws Exception {
        ByteArrayInputStream body = storageSends(new byte[(int) LIMIT * 50]);

        assertThatThrownBy(() -> store.read(BUCKET, KEY))
                .isInstanceOf(Thumbnailer.ThumbnailUnavailableException.class)
                .hasMessageContaining("upload limit");
        assertThat(body.available()).isEqualTo((int) (LIMIT * 50 - (LIMIT + 1)));
    }

    @Test
    void only_one_byte_past_the_limit_is_ever_asked_for() throws Exception {
        storageSends(new byte[10]);

        store.read(BUCKET, KEY);

        ArgumentCaptor<GetObjectArgs> asked = ArgumentCaptor.forClass(GetObjectArgs.class);
        verify(client).getObject(asked.capture());
        assertThat(asked.getValue().offset()).isZero();
        assertThat(asked.getValue().length()).isEqualTo(LIMIT + 1);
    }
}

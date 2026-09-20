package com.delivery.product.api;

import java.util.UUID;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.product.service.BannerService;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PT-5 (portal deep test, 2026-09-19): a banner id that does not exist.
 *
 * <p>{@link BannerService#read} throws {@link BannerService.BannerNotFoundException}, and nothing in
 * {@link ApiExceptionHandler} maps it, so the catch-all answers 500 "Internal error". On dev,
 * back office's PUT and DELETE /api/banners/{id} and POST /api/banners/{id}/image/presign all return
 * 500 for an unknown id, where every other missing thing in this service (product, store,
 * category, zone, offer, scan) is a 404. A banner withdrawn in another tab is exactly that case.
 *
 * <p>Fails until the exception is mapped to 404.
 */
@DisplayName("PT-5: a banner that does not exist")
class BannerNotFoundTest {

    @RestController
    static class Probe {
        @DeleteMapping("/probe/banners/{id}")
        void withdraw(@PathVariable UUID id) {
            throw new BannerService.BannerNotFoundException(id);
        }
    }

    private final MockMvc mvc = MockMvcBuilders.standaloneSetup(new Probe())
            .setControllerAdvice(new ApiExceptionHandler())
            .build();

    @Test
    void is_a_404_like_every_other_missing_thing_here() throws Exception {
        mvc.perform(delete("/probe/banners/" + UUID.randomUUID()))
                .andExpect(status().isNotFound());
    }
}

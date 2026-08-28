package com.delivery.product.service;

import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.platform.storage.FileMetadata;
import com.delivery.platform.storage.FilePurpose;
import com.delivery.platform.storage.StorageService;
import com.delivery.platform.storage.PresignedUpload;
import com.delivery.product.domain.Store;
import com.delivery.product.domain.StoreRepository;
import com.delivery.product.service.CatalogService.CatalogRuleViolationException;
import com.delivery.product.service.StoreService.StoreNotFoundException;

/**
 * A store's own artwork: the logo customers recognise it by, and the cover behind its header.
 *
 * <p>Same three-step presign flow as {@link ProductImageService} — ask, PUT straight to storage,
 * confirm — for the same reason: the bytes never pass through this service, so a 4 MB photo is not
 * a 4 MB request body here.
 *
 * <p>Reuses the {@code product-images} bucket rather than introducing a new one. Store artwork is
 * the same class of asset in every way that matters to storage: merchant-supplied, publicly
 * readable, served straight to a storefront. A separate bucket would need provisioning in
 * minio-init and its own policy, for no difference in behaviour. Keys are prefixed
 * {@code stores/<id>} so the two are still trivially separable.
 */
@Service
public class StoreImageService {

    /**
     * Which picture is being replaced.
     *
     * <p>A store has exactly one of each, so an upload replaces rather than appends — unlike a
     * product, which has a gallery.
     */
    public enum Slot {
        LOGO,
        COVER
    }

    private final StoreRepository stores;
    private final StorageService storage;
    private final ThumbnailService thumbnails;

    public StoreImageService(StoreRepository stores, StorageService storage,
                             ThumbnailService thumbnails) {
        this.stores = stores;
        this.storage = storage;
        this.thumbnails = thumbnails;
    }

    @Transactional
    public PresignedUpload presign(UUID storeId, String merchantId, Slot slot, String contentType) {
        requireOwned(storeId, merchantId);
        return storage.presignUpload(merchantId, FilePurpose.PRODUCT_IMAGE, contentType,
                "stores/" + storeId + "/" + slot.name().toLowerCase(java.util.Locale.ROOT));
    }

    /**
     * Attaches a confirmed upload to the store.
     *
     * <p>The ownership check runs twice, exactly as it does for product images: {@code confirmUpload}
     * verifies the <em>file</em> belongs to the caller and {@code requireOwned} verifies the
     * <em>store</em> does. Dropping the second would let a merchant put their logo on a
     * competitor's shopfront.
     *
     * <p>A cover earns its derivative more than anything else on the platform: the home screen
     * draws a grid of them at 100–130 dp and the shop page draws the same object full-bleed as a
     * hero, so without one the grid pays hero-sized bytes per card. Same call as
     * {@link ProductImageService#confirmImage}, and it cannot fail this one either.
     */
    @Transactional
    public Store confirm(UUID storeId, String merchantId, Slot slot, UUID fileId) {
        Store store = requireOwned(storeId, merchantId);
        FileMetadata metadata = storage.confirmUpload(fileId, merchantId);

        thumbnails.createFor(metadata);

        applySlot(store, slot, metadata.getObjectKey());
        return store;
    }

    @Transactional
    public Store remove(UUID storeId, String merchantId, Slot slot) {
        Store store = requireOwned(storeId, merchantId);
        // The object itself is left in the bucket for an orphan sweep to collect. Deleting it here
        // would break any response already holding a presigned URL for it.
        applySlot(store, slot, null);
        return store;
    }

    private void applySlot(Store store, Slot slot, String objectKey) {
        if (slot == Slot.LOGO) {
            store.setImagery(objectKey, store.getCoverRef());
        } else {
            store.setImagery(store.getLogoRef(), objectKey);
        }
    }

    public static Slot slotOf(String raw) {
        try {
            return Slot.valueOf(raw.toUpperCase(java.util.Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new CatalogRuleViolationException(
                    "Unknown image slot '" + raw + "' — expected logo or cover");
        }
    }

    private Store requireOwned(UUID storeId, String merchantId) {
        return stores.findByIdAndMerchantId(storeId, merchantId)
                .orElseThrow(() -> new StoreNotFoundException(storeId.toString()));
    }
}

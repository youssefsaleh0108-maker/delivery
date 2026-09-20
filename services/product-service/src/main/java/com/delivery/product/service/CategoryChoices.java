package com.delivery.product.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

import com.delivery.product.domain.CategoryRepository;

/**
 * The sections a product may be filed under in one shop, and a name back to one of them.
 *
 * <p>Shared by everything that reads a photo and suggests where the product belongs: Merchant Blitz's
 * shelf lines, and a merchant finding a product by photo. One copy of the rule, because a near miss
 * is worse than no suggestion and both should miss the same way.
 */
public final class CategoryChoices {

    /** A section a product may be filed under — the store's own, or the platform's. */
    public record Choice(UUID id, String name, boolean storeOwned) {
    }

    private CategoryChoices() {
    }

    /** The store's own sections first, then the platform taxonomy. */
    public static List<Choice> forStore(CategoryRepository categories, UUID storeId) {
        List<Choice> choices = new ArrayList<>();
        categories.findByStoreIdOrderByPositionAscNameAsc(storeId)
                .forEach(c -> choices.add(new Choice(c.getId(), c.getName(), true)));
        categories.findByStoreIdIsNull()
                .forEach(c -> choices.add(new Choice(c.getId(), c.getName(), false)));
        return choices;
    }

    /**
     * A suggested section name back to an id — only ever one that was offered.
     *
     * <p>Exact match, ignoring case and surrounding space, store sections first. No fuzzy matching:
     * a near miss filed under the wrong shelf is worse than no suggestion, which the merchant sees
     * as an empty picker and fills in.
     */
    public static UUID resolve(String suggested, List<Choice> choices) {
        if (suggested == null || suggested.isBlank()) {
            return null;
        }
        String wanted = suggested.trim().toLowerCase(Locale.ROOT);
        for (Choice choice : choices) {
            if (choice.name() != null && choice.name().trim().toLowerCase(Locale.ROOT).equals(wanted)) {
                return choice.id();
            }
        }
        return null;
    }

    /**
     * The first of {@code suggestions} that names a section, or null.
     *
     * <p>What photo search's keywords are read with: a reader answers "cola", "soft drink",
     * "مشروب غازي", and a shop whose shelf is called exactly one of those gets the suggestion.
     */
    public static UUID resolveAny(List<String> suggestions, List<Choice> choices) {
        if (suggestions == null) {
            return null;
        }
        for (String suggested : suggestions) {
            UUID found = resolve(suggested, choices);
            if (found != null) {
                return found;
            }
        }
        return null;
    }
}

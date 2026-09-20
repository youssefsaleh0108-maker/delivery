package com.delivery.product.api.dto;

import java.util.Collections;
import java.util.List;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import com.delivery.product.domain.Store;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * What a shop's profile form may carry.
 *
 * <p>The tags in particular, because they are bounded in two independent ways and only one of them
 * used to be written down: how long one tag may be, and how many there may be. Every one of these
 * values is merchant-typed and ends up in a jsonb column and on a public page.
 */
@DisplayName("the limits on a shop's profile")
class StoreRequestLimitsTest {

    private static ValidatorFactory factory;
    private static Validator validator;

    @BeforeAll
    static void startValidator() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void stopValidator() {
        factory.close();
    }

    private static StoreDtos.StoreRequest withTags(List<String> tags) {
        return new StoreDtos.StoreRequest("Dekkanet Al Rawche", Store.Vertical.GROCERY,
                "Everything the corner shop should have", "Open since 1974.", tags,
                "Asia/Beirut", "Rawche, Beirut", "Ras Beirut", null);
    }

    @Test
    @DisplayName("twenty tags are a shop describing itself")
    void acceptsAReasonableList() {
        assertThat(validator.validate(withTags(Collections.nCopies(20, "grocery")))).isEmpty();
        assertThat(validator.validate(withTags(List.of()))).isEmpty();
        assertThat(validator.validate(withTags(null))).isEmpty();
    }

    @Test
    @DisplayName("a hundred thousand of them is not, however short each one is")
    void refusesAnUnboundedList() {
        assertThat(validator.validate(withTags(Collections.nCopies(21, "grocery"))))
                .isNotEmpty();
        // The shape the old limit allowed: every tag valid, the list itself unbounded, all of it
        // stored in one jsonb column and drawn as chips on a page anybody can fetch.
        assertThat(validator.validate(withTags(Collections.nCopies(100_000, "grocery"))))
                .isNotEmpty();
    }

    @Test
    @DisplayName("one tag is still allowed to be forty characters and no more")
    void stillBoundsEachTag() {
        assertThat(validator.validate(withTags(List.of("x".repeat(40))))).isEmpty();
        assertThat(validator.validate(withTags(List.of("x".repeat(41))))).isNotEmpty();
    }
}

package com.delivery.appnotification.domain;

import java.lang.reflect.Method;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.repository.query.parser.PartTree;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * That the inbox's paged query is one Spring Data can actually derive.
 *
 * <p>The paging fix added a second finder, and a finder whose name does not resolve to properties
 * of the entity fails at context startup rather than at the call — long after every mocked test in
 * this module has passed. There is no Spring context and no database here, so the cheapest check
 * that does work is to run the same name through the parser Spring Data itself uses.
 */
@DisplayName("the paged inbox query")
class InAppMessageRepositoryTest {

    private static final String FINDER = "findPageByUserIdOrderByCreatedAtDesc";

    @Test
    void resolves_against_the_message_entity() {
        assertThatCode(() -> new PartTree(FINDER, InAppMessage.class)).doesNotThrowAnyException();
    }

    /** Newest first is what an inbox means; a page of the oldest messages would be worse than none. */
    @Test
    void is_sorted_newest_first() {
        PartTree tree = new PartTree(FINDER, InAppMessage.class);

        assertThat(tree.getSort().getOrderFor("createdAt")).isNotNull();
        assertThat(tree.getSort().getOrderFor("createdAt").isDescending()).isTrue();
    }

    /**
     * A count comes back with the rows, which is the whole reason this finder exists next to the
     * list-returning one: without a total the client cannot tell "that was all" from "ask again".
     */
    @Test
    void returns_a_page_for_a_pageable() throws Exception {
        Method finder = InAppMessageRepository.class.getDeclaredMethod(
                FINDER, String.class, Pageable.class);

        assertThat(finder.getReturnType()).isEqualTo(Page.class);
    }
}

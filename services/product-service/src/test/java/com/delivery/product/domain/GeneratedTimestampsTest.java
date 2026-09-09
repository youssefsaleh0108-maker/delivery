package com.delivery.product.domain;

import java.lang.reflect.Field;
import java.util.Arrays;

import org.hibernate.annotations.Generated;
import org.hibernate.generator.EventType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The timestamps a client reads off a 201.
 *
 * <p>{@code created_at} and {@code updated_at} are owned by the database — a column default and the
 * {@code touch_updated_at} trigger — so the entity does not write them and, without being told to
 * read them back, never learns what was written. The symptom was a created product serialised
 * straight after {@code save()} carrying {@code createdAt: null}, which a client cannot tell from a
 * product with no creation date.
 *
 * <p>Asserted through reflection rather than by creating a row, because the fault only exists
 * across a real flush: these are mocked unit tests with no Spring context and no database, and a
 * test that saved through a mocked repository would pass whether the annotation were there or not.
 * What this holds down is the one thing that is checkable here and is exactly what was missing.
 */
@DisplayName("the database-maintained timestamps")
class GeneratedTimestampsTest {

    @Test
    void a_product_reads_its_creation_time_back_after_the_insert() {
        assertThat(generationEventsOf(Product.class, "createdAt")).contains(EventType.INSERT);
    }

    @Test
    void a_product_reads_its_update_time_back_after_both() {
        assertThat(generationEventsOf(Product.class, "updatedAt"))
                .contains(EventType.INSERT, EventType.UPDATE);
    }

    @Test
    void a_store_reads_its_creation_time_back_after_the_insert() {
        assertThat(generationEventsOf(Store.class, "createdAt")).contains(EventType.INSERT);
    }

    @Test
    void a_store_reads_its_update_time_back_after_both() {
        assertThat(generationEventsOf(Store.class, "updatedAt"))
                .contains(EventType.INSERT, EventType.UPDATE);
    }

    /**
     * The other half of the pair: the columns stay out of the insert and update statements, so the
     * database's own value is never overwritten by the null the entity is holding.
     */
    @Test
    void and_the_columns_are_still_the_databases_to_write() {
        for (Class<?> entity : new Class<?>[] {Product.class, Store.class}) {
            for (String field : new String[] {"createdAt", "updatedAt"}) {
                jakarta.persistence.Column column =
                        fieldOf(entity, field).getAnnotation(jakarta.persistence.Column.class);
                assertThat(column.insertable()).isFalse();
                assertThat(column.updatable()).isFalse();
            }
        }
    }

    private static EventType[] generationEventsOf(Class<?> entity, String fieldName) {
        Generated generated = fieldOf(entity, fieldName).getAnnotation(Generated.class);
        assertThat(generated)
                .as("%s.%s is written by the database and must be read back",
                        entity.getSimpleName(), fieldName)
                .isNotNull();
        return Arrays.stream(generated.event()).toArray(EventType[]::new);
    }

    private static Field fieldOf(Class<?> entity, String fieldName) {
        try {
            return entity.getDeclaredField(fieldName);
        } catch (NoSuchFieldException e) {
            throw new AssertionError(entity.getSimpleName() + " has no " + fieldName, e);
        }
    }
}

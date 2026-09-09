package com.delivery.transfer.api;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.web.bind.annotation.RequestBody;

import jakarta.validation.Valid;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Every request body reaches its handler validated.
 *
 * <p>The {@code @NotNull}s on these records were written and then never ran: a bare
 * {@code @RequestBody} binds without validating, so a payload missing {@code amountUsd} or
 * {@code orderId} passed straight into BigDecimal and UUID work and answered 500 with the
 * framework's own body. A missing {@code @Valid} is silent — nothing fails, the constraints simply
 * stop applying — so this pins the annotation itself rather than waiting for the next omission to
 * be found in production.
 */
class ValidatedRequestBodiesTest {

    @ParameterizedTest(name = "{0} validates every body it accepts")
    @ValueSource(classes = {TransferController.class, SplitController.class})
    @DisplayName("a request body is never bound without its constraints")
    void everyRequestBodyIsValidated(Class<?> controller) {
        List<String> unvalidated = java.util.Arrays.stream(controller.getDeclaredMethods())
                .flatMap(method -> java.util.Arrays.stream(method.getParameters())
                        .filter(p -> p.isAnnotationPresent(RequestBody.class))
                        .filter(p -> !p.isAnnotationPresent(Valid.class))
                        .map(p -> describe(method, p)))
                .toList();

        assertThat(unvalidated).isEmpty();
    }

    private static String describe(Method method, Parameter parameter) {
        return method.getName() + "(" + parameter.getType().getSimpleName() + ")";
    }
}

package com.delivery.onboarding.service;

import java.lang.reflect.Method;
import java.util.Arrays;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.service.VerificationService.VerificationException;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The attempt cap must survive the refusal that triggers it.
 *
 * <p>{@code confirm} counts a wrong guess and then refuses by throwing. Because
 * {@link VerificationException} is a {@link RuntimeException}, Spring's default rollback threw the
 * count away with the refusal — so every guess was the first attempt, {@code MAX_ATTEMPTS} was
 * unreachable, and a six-digit code could be walked end to end. An end-to-end run confirmed it on
 * both the signup and password-reset paths.
 *
 * <p>This is asserted by reflection rather than by exercising the service because rollback is a
 * property of the transaction, not of the method body: every test in this module mocks its
 * repositories and runs with no Spring context, so a mocked save "succeeds" and the bug is
 * invisible. Checking the annotation is the only guard this test style can actually offer.
 */
class VerificationRollbackTest {

    @Test
    @DisplayName("every confirm overload keeps its attempt count when it refuses a code")
    void confirmDoesNotRollBackTheAttemptCounter() {
        Method[] confirms = Arrays.stream(VerificationService.class.getDeclaredMethods())
                .filter(m -> m.getName().equals("confirm"))
                .toArray(Method[]::new);

        assertThat(confirms)
                .as("confirm() overloads found on VerificationService")
                .isNotEmpty();

        for (Method confirm : confirms) {
            Transactional tx = confirm.getAnnotation(Transactional.class);
            assertThat(tx)
                    .as("%s must be transactional", confirm)
                    .isNotNull();
            assertThat(tx.noRollbackFor())
                    .as("%s must commit the attempt it just counted, or the cap is unreachable "
                            + "and the code is brute-forceable", confirm)
                    .contains(VerificationException.class);
        }
    }
}

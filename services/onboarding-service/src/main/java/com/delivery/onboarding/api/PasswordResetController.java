package com.delivery.onboarding.api;

import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.service.PasswordResetService;
import com.delivery.onboarding.service.VerificationService;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * The sign-in screen's "Forgot password".
 *
 * <p>Both endpoints are open, necessarily: the whole premise is somebody who cannot sign in. What
 * stands in for authentication is the one-time code sent to the account's own address — the same
 * machinery, limits and single-use semantics as sign-up verification, under a purpose of its own
 * so the two kinds of code cannot be swapped (see {@code ContactVerification.Purpose}).
 *
 * <p>The request endpoint answers 202 for every well-formed address, whether or not an account
 * exists, and the rate limits count identically for both — this endpoint must not be usable as a
 * directory of who has a YouDrop account.
 */
@RestController
@RequestMapping("/api/onboarding/password-reset")
public class PasswordResetController {

    private final PasswordResetService resets;

    public PasswordResetController(PasswordResetService resets) {
        this.resets = resets;
    }

    // ---------------------------------------------------------------- shapes

    public record ResetRequest(
            @NotBlank @Email @Size(max = 200) String email) {
    }

    /**
     * @param newPassword the six-digit passcode the app's keypad collects — the same floor and
     *                    ceiling as sign-up, because it becomes the same credential. Keycloak's
     *                    realm policy remains the authority; this only bounds the field
     */
    public record ResetConfirmRequest(
            @NotBlank @Email @Size(max = 200) String email,
            @NotBlank @Size(max = 12) String code,
            @NotBlank @Size(min = 6, max = 128) String newPassword) {
    }

    // ---------------------------------------------------------------- open to anybody

    /**
     * Asks for a reset code.
     *
     * <p>202 always: accepted for processing, and deliberately not "sent". Whether a message
     * actually left depends on whether the address has an account, and that difference is exactly
     * what the response must not carry. The only other answers are 400 for an address that is not
     * one, and 429 when the destination's limits say wait — both of which behave identically for
     * known and unknown addresses.
     */
    @PostMapping
    public ResponseEntity<Void> request(@Valid @RequestBody ResetRequest request) {
        resets.request(request.email());
        return ResponseEntity.accepted().build();
    }

    /**
     * Answers the code and sets the new passcode. 204 on success.
     *
     * <p>A wrong, expired or spent code gets the verification machinery's own refusals, verbatim —
     * 422, same wording as everywhere else — and each wrong guess counts against the code's
     * attempt cap exactly as it does at sign-up.
     */
    @PostMapping("/confirm")
    public ResponseEntity<Void> confirm(@Valid @RequestBody ResetConfirmRequest request) {
        resets.confirm(request.email(), request.code(), request.newPassword());
        return ResponseEntity.noContent().build();
    }

    // ---------------------------------------------------------------- answers

    /** 429, distinct from 422 for the same reason it is on the verification endpoints. */
    @ExceptionHandler(VerificationService.TooManyRequestsException.class)
    public ResponseEntity<Map<String, String>> tooMany(
            VerificationService.TooManyRequestsException e) {
        return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                .body(Map.of("message", e.getMessage()));
    }

    /** 422: the code was wrong, expired, or spent. Same wording as the verification endpoints. */
    @ExceptionHandler(VerificationService.VerificationException.class)
    public ResponseEntity<Map<String, String>> verification(
            VerificationService.VerificationException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 502: the code was right but Keycloak would not take the new passcode. The person did
     * everything correctly, so the message says to retry rather than implying their input was
     * wrong — and their code is still live, because the failed attempt rolled back its consumption.
     */
    @ExceptionHandler(KeycloakAdminClient.ProvisioningException.class)
    public ResponseEntity<Map<String, String>> provisioning(
            KeycloakAdminClient.ProvisioningException e) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(Map.of("message", e.getMessage()));
    }
}

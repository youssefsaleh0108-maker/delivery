package com.delivery.onboarding.api;

import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.OnboardingApplication;
import com.delivery.onboarding.service.AccountApplicationService;
import com.delivery.onboarding.service.OnboardingService;
import com.delivery.onboarding.service.VerificationService;
import com.delivery.platform.security.CurrentUser;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * An account that already exists, asking for a role — the other half of "sign in with Google".
 *
 * <p>The app asks a Google user whether they are a customer, a rider or a seller before it opens
 * the browser, and these two endpoints are what it calls when the answer is a role the account does
 * not hold yet. Both are <strong>authenticated</strong> and both act on the caller's own token
 * subject and nothing else: neither takes an account id, in the path or in the body, so there is no
 * way to aim either one at somebody else.
 *
 * <p>A controller of its own rather than more of {@link OnboardingController}, whose paths are
 * mostly open to anybody. Keeping the two signed-in writes apart makes "which onboarding endpoints
 * need a token" answerable by looking at one class, and lets their error answers — a Keycloak
 * failure in particular — be stated here without changing what the open endpoints say.
 *
 * <p>Neither path is on {@code delivery.security.permit-all}. Note the one near miss worth knowing
 * about: {@code /api/onboarding/applications/*}{@code /account} is open, so a signed-in endpoint
 * must never be shaped {@code /applications/{something}/account}.
 */
@RestController
@RequestMapping("/api/onboarding")
public class AccountOnboardingController {

    private final AccountApplicationService accounts;

    public AccountOnboardingController(AccountApplicationService accounts) {
        this.accounts = accounts;
    }

    /**
     * What a signed-in account sends to apply. The open form's {@code ApplicationRequest} without
     * the email and its proof — the address is the account's own, taken from the token.
     *
     * @param businessName required for a seller; ignored for a rider, whose application is in their
     *                     own name
     */
    public record AccountApplicationRequest(
            @NotNull OnboardingApplication.Kind kind,
            @Size(max = 200) String businessName,
            @NotBlank @Size(max = 160) String contactName,
            @Size(max = 32) String contactPhone,
            @Size(max = 64) String phoneVerificationToken,
            @Size(max = 2000) String notes,
            /** The wizard's free-form answers, bounded exactly as on the open form. */
            @MaxSerializedSize(bytes = OnboardingController.MAX_DETAILS_BYTES)
            Map<String, Object> details,
            /** The delivery company a rider is applying to. Null rides for YouDrop itself. */
            UUID targetProviderId) {
    }

    /**
     * Applying to ride or to sell, as the account you are signed in with.
     *
     * <p>201 with the receipt when this created the application; 200 with the same receipt when the
     * account already had it — a second tap, a retry after a dropped connection, or a returning
     * Google user who picked the same role again. The receipt is the same thin shape the open path
     * returns, so there is nothing in it the caller did not already know.
     *
     * <p>The caller's roles change on the way through (APPLICANT and the live role, or the live role
     * alone if auto-approval took it), and those changes are in Keycloak, not in the token the
     * caller is holding. The app refreshes its token after this returns; until it does, it is
     * looking at the roles it had before it asked.
     */
    @PostMapping("/applications/mine")
    public ResponseEntity<OnboardingController.ApplicationReceipt> applyForMyAccount(
            @Valid @RequestBody AccountApplicationRequest request) {
        AccountApplicationService.Result result = accounts.apply(caller(),
                new AccountApplicationService.Answers(request.kind(), request.businessName(),
                        request.contactName(), request.contactPhone(),
                        request.phoneVerificationToken(), request.notes(), request.details(),
                        request.targetProviderId()));
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(OnboardingController.ApplicationReceipt.of(result.application()));
    }

    /**
     * Becoming a customer, as the account you are signed in with.
     *
     * <p>204 and nothing else; idempotent. What changes is the account's roles, which the caller
     * picks up by refreshing its token.
     */
    @PostMapping("/me/customer")
    public ResponseEntity<Void> becomeCustomer() {
        accounts.becomeCustomer(caller());
        return ResponseEntity.noContent().build();
    }

    /**
     * The caller, read from the validated token and nothing else.
     *
     * <p>{@code email_verified} is read as a claim rather than trusted from anywhere the caller
     * controls. Absent reads as false — the safe direction to be wrong in, since it refuses rather
     * than admits.
     */
    private static AccountApplicationService.Caller caller() {
        String subject = CurrentUser.requireId();
        boolean verified = CurrentUser.jwt()
                .map(jwt -> Boolean.TRUE.equals(jwt.getClaimAsBoolean("email_verified")))
                .orElse(false);
        return new AccountApplicationService.Caller(
                subject, CurrentUser.email().orElse(null), verified, CurrentUser::hasRole);
    }

    // ---------------------------------------------------------------- answers

    /**
     * 422: the request cannot be taken as asked, and the message says why.
     *
     * <p>A refusal this path knows by name also carries its {@code code}, and the code is what the
     * app reads: it translates it, and shows the English message only for a refusal it has no words
     * for (the domain's own, which have no code). See
     * {@link AccountApplicationService.AccountRuleException}.
     */
    @ExceptionHandler(OnboardingService.ApplicationRuleException.class)
    public ResponseEntity<Map<String, String>> rule(OnboardingService.ApplicationRuleException e) {
        if (e instanceof AccountApplicationService.AccountRuleException coded) {
            return ResponseEntity.unprocessableEntity()
                    .body(Map.of("message", e.getMessage(), "code", coded.code()));
        }
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /** 422: the phone number's code was wrong, expired or spent. Same wording as the open form. */
    @ExceptionHandler(VerificationService.VerificationException.class)
    public ResponseEntity<Map<String, String>> verification(
            VerificationService.VerificationException e) {
        return ResponseEntity.unprocessableEntity().body(Map.of("message", e.getMessage()));
    }

    /**
     * 502: the record is fine but Keycloak would not set the roles. The same status
     * {@code PartnerManagementController} answers for the same failure. Retrying is safe and is
     * what finishes it — the application path is idempotent and re-asserts the roles. The app
     * knows this answer by its status and says it in its own words, so the message needs no code.
     */
    @ExceptionHandler(KeycloakAdminClient.ProvisioningException.class)
    public ResponseEntity<Map<String, String>> provisioning(
            KeycloakAdminClient.ProvisioningException e) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(Map.of("message", e.getMessage()));
    }
}

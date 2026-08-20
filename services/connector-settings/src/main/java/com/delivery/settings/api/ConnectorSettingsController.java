package com.delivery.settings.api;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.observability.CorrelationIdFilter;
import com.delivery.platform.security.CurrentUser;
import com.delivery.settings.domain.ConnectorSetting;
import com.delivery.settings.domain.ConnectorSettingAudit;
import com.delivery.settings.domain.ConnectorType;
import com.delivery.settings.service.ConnectorSettingsService;
import com.delivery.settings.service.ConnectorSettingsService.SettingNotFoundException;

/**
 * The Backoffice Settings API (Section 8).
 *
 * <p>BACKOFFICE-only at the class level. Section 12 leaves open whether a narrower
 * {@code BACKOFFICE_ADMIN} sub-role should gate this — when that is decided, it is a one-line change
 * here, which is why the whole controller is annotated rather than each method.
 */
@RestController
@RequestMapping("/api/settings/connectors")
@PreAuthorize("hasRole('BACKOFFICE')")
public class ConnectorSettingsController {

    private final ConnectorSettingsService settings;

    public ConnectorSettingsController(ConnectorSettingsService settings) {
        this.settings = settings;
    }

    @GetMapping
    public List<ConnectorResponse> list() {
        return settings.all().stream().map(ConnectorSettingsController::toResponse).toList();
    }

    @GetMapping("/{type}")
    public ConnectorResponse read(@PathVariable ConnectorType type) {
        return toResponse(settings.get(type));
    }

    @GetMapping("/{type}/history")
    public List<AuditEntry> history(@PathVariable ConnectorType type) {
        return settings.history(type).stream()
                .map(a -> new AuditEntry(a.getOldValue(), a.getNewValue(),
                        a.getChangedBy(), a.getChangedAt()))
                .toList();
    }

    @PutMapping("/{type}")
    public ConnectorResponse update(@PathVariable ConnectorType type,
                                    @Valid @RequestBody UpdateRequest request) {
        return toResponse(settings.update(
                type,
                request.provider(),
                request.config() == null ? Map.of() : request.config(),
                CurrentUser.requireId()));
    }

    private static ConnectorResponse toResponse(ConnectorSetting s) {
        return new ConnectorResponse(
                s.getConnectorType(),
                s.getProvider(),
                // The choices the UI renders as a dropdown, so it never has to hardcode them.
                s.getConnectorType().providers(),
                s.getConfig(),
                // Never the secret itself - only enough to show "configured" and when it last
                // changed (Section 8).
                s.getVaultPath(),
                s.getVaultPath() != null ? "********" : null,
                s.getSecretRotatedAt(),
                s.isActive(),
                s.getUpdatedBy(),
                s.getUpdatedAt());
    }

    public record UpdateRequest(
            @NotBlank String provider,
            Map<String, Object> config) {
    }

    public record ConnectorResponse(
            ConnectorType connectorType,
            String provider,
            List<String> availableProviders,
            Map<String, Object> config,
            String vaultPath,
            String maskedSecret,
            Instant secretRotatedAt,
            boolean active,
            String updatedBy,
            Instant updatedAt) {
    }

    public record AuditEntry(
            Map<String, Object> oldValue,
            Map<String, Object> newValue,
            String changedBy,
            Instant changedAt) {
    }

    @ExceptionHandler(SettingNotFoundException.class)
    public ProblemDetail onNotFound(SettingNotFoundException e) {
        return problem(HttpStatus.NOT_FOUND, "Connector not found", e.getMessage());
    }

    /**
     * Covers both an unsupported provider and a config that looks like it carries a secret. 422
     * rather than 400: the request is well-formed, the value is just not one we accept.
     */
    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail onInvalid(IllegalArgumentException e) {
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "Invalid setting", e.getMessage());
    }

    private static ProblemDetail problem(HttpStatus status, String title, String detail) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setTitle(title);
        problem.setProperty("timestamp", Instant.now());
        String correlationId = MDC.get(CorrelationIdFilter.MDC_KEY);
        if (correlationId != null) {
            problem.setProperty("correlationId", correlationId);
        }
        return problem;
    }
}

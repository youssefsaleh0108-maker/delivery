package com.delivery.settings.api;

import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.settings.domain.ConnectorSetting;
import com.delivery.settings.domain.ConnectorType;
import com.delivery.settings.service.ConnectorSettingsService;
import com.delivery.settings.service.ConnectorSettingsService.SettingNotFoundException;

/**
 * What a connector reads to recover from a missed {@code connector.settings_changed} event.
 *
 * <p>Separate from {@link ConnectorSettingsController} rather than a relaxed annotation on it,
 * because the two have genuinely different callers and different exposure. That controller is a
 * Backoffice API behind the Gateway, gated on the BACKOFFICE role. This one is called by connectors
 * — services with no user token to present — and is deliberately NOT in the Gateway's route table,
 * so it exists only on the internal network.
 *
 * <p>It is also read-only and returns no secret: the response carries the provider name and the
 * non-secret config, never the Vault path's contents. Even reached from inside the cluster, there
 * is nothing here worth stealing.
 */
@RestController
@RequestMapping("/internal/connectors")
public class InternalConnectorSettingsController {

    private final ConnectorSettingsService settings;

    public InternalConnectorSettingsController(ConnectorSettingsService settings) {
        this.settings = settings;
    }

    @GetMapping("/{type}")
    public Map<String, Object> read(@PathVariable ConnectorType type) {
        ConnectorSetting setting = settings.get(type);
        return Map.of(
                "connectorType", setting.getConnectorType().name(),
                "provider", setting.getProvider(),
                "config", setting.getConfig(),
                "active", setting.isActive());
    }

    @ExceptionHandler(SettingNotFoundException.class)
    public ProblemDetail onNotFound(SettingNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }
}

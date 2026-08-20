package com.delivery.settings.service;

import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.MessageProperties;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.settings.domain.ConnectorSetting;
import com.delivery.settings.domain.ConnectorSettingAudit;
import com.delivery.settings.domain.ConnectorSettingAuditRepository;
import com.delivery.settings.domain.ConnectorSettingRepository;
import com.delivery.settings.domain.ConnectorType;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Reads and changes connector configuration, audits every change, and tells the connectors.
 *
 * <p>Connectors must notice a change without a restart (Section 8), so a lightweight
 * {@code connector.settings_changed} event goes onto the same bus that carries domain events. Each
 * connector reloads its active provider client on receipt, with a short in-memory cache in between
 * so a settings-service blip cannot take a connector down.
 */
@Service
public class ConnectorSettingsService {

    private static final Logger log = LoggerFactory.getLogger(ConnectorSettingsService.class);

    /** Routing key connectors bind to. */
    public static final String SETTINGS_CHANGED = "connector.settings_changed";

    private final ConnectorSettingRepository settings;
    private final ConnectorSettingAuditRepository audit;
    private final RabbitTemplate rabbit;
    private final ObjectMapper objectMapper;
    private final String exchange;

    public ConnectorSettingsService(ConnectorSettingRepository settings,
                                    ConnectorSettingAuditRepository audit,
                                    RabbitTemplate rabbit,
                                    ObjectMapper objectMapper,
                                    @Value("${delivery.outbox.exchange:delivery.events}") String exchange) {
        this.settings = settings;
        this.audit = audit;
        this.rabbit = rabbit;
        this.objectMapper = objectMapper;
        this.exchange = exchange;
    }

    @Transactional(readOnly = true)
    public List<ConnectorSetting> all() {
        return settings.findAll();
    }

    @Transactional(readOnly = true)
    public ConnectorSetting get(ConnectorType type) {
        return settings.findById(type)
                .orElseThrow(() -> new SettingNotFoundException(type));
    }

    @Transactional(readOnly = true)
    public List<ConnectorSettingAudit> history(ConnectorType type) {
        return audit.findByConnectorTypeOrderByChangedAtDesc(type);
    }

    /**
     * Changes a connector's active provider and/or non-secret config.
     *
     * <p>The audit row is written in the same transaction as the change, so an audit trail with a
     * gap in it is not possible. The bus notification is sent after commit for the opposite reason:
     * telling connectors about a change that then rolled back would leave them using configuration
     * that does not exist.
     */
    @Transactional
    public ConnectorSetting update(ConnectorType type, String provider,
                                   Map<String, Object> config, String changedBy) {
        ConnectorSetting setting = get(type);
        Map<String, Object> before = setting.snapshot();

        setting.update(provider, config, changedBy);

        audit.save(new ConnectorSettingAudit(type, before, setting.snapshot(), changedBy));
        log.info("Connector {} switched to provider {} by {}", type, provider, changedBy);

        publishAfterCommit(setting);
        return setting;
    }

    private void publishAfterCommit(ConnectorSetting setting) {
        org.springframework.transaction.support.TransactionSynchronizationManager
                .registerSynchronization(
                        new org.springframework.transaction.support.TransactionSynchronization() {
                            @Override
                            public void afterCommit() {
                                announce(setting);
                            }
                        });
    }

    private void announce(ConnectorSetting setting) {
        try {
            byte[] body = objectMapper.writeValueAsBytes(Map.of(
                    "connectorType", setting.getConnectorType().name(),
                    "provider", setting.getProvider(),
                    "config", setting.getConfig()));

            MessageProperties props = new MessageProperties();
            props.setContentType(MessageProperties.CONTENT_TYPE_JSON);
            props.setHeader("eventType", SETTINGS_CHANGED);

            rabbit.send(exchange, SETTINGS_CHANGED,
                    new org.springframework.amqp.core.Message(body, props));
        } catch (Exception e) {
            // The change is already committed and audited. A connector that misses the event picks
            // the new value up when its cache expires, so this is degraded, not broken.
            log.error("Could not announce settings change for {}; connectors will pick it up on "
                    + "cache expiry", setting.getConnectorType(), e);
        }
    }

    public static class SettingNotFoundException extends RuntimeException {
        public SettingNotFoundException(ConnectorType type) {
            super("No settings for connector " + type);
        }
    }
}

package com.delivery.settings.domain;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ConnectorSettingAuditRepository extends JpaRepository<ConnectorSettingAudit, UUID> {

    List<ConnectorSettingAudit> findByConnectorTypeOrderByChangedAtDesc(ConnectorType connectorType);
}

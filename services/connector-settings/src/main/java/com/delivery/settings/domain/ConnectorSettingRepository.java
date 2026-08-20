package com.delivery.settings.domain;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ConnectorSettingRepository extends JpaRepository<ConnectorSetting, ConnectorType> {
}

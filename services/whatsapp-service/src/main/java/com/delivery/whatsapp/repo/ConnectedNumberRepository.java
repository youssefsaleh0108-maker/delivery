package com.delivery.whatsapp.repo;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

import com.delivery.whatsapp.domain.ConnectedNumber;

public interface ConnectedNumberRepository extends JpaRepository<ConnectedNumber, String> {

    List<ConnectedNumber> findByMerchantRefOrderByConnectedAtAsc(String merchantRef);
}

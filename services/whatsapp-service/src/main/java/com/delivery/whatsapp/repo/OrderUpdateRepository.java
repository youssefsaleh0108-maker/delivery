package com.delivery.whatsapp.repo;

import org.springframework.data.jpa.repository.JpaRepository;

import com.delivery.whatsapp.domain.OrderUpdate;

public interface OrderUpdateRepository extends JpaRepository<OrderUpdate, OrderUpdate.Key> {
}

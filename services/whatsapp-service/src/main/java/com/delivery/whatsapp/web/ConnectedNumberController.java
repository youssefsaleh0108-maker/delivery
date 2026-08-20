package com.delivery.whatsapp.web;

import java.util.List;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.platform.security.CurrentUser;
import com.delivery.whatsapp.domain.ConnectedNumber;
import com.delivery.whatsapp.service.NumberDirectory;
import com.delivery.whatsapp.web.dto.ConnectNumberRequest;
import com.delivery.whatsapp.web.dto.ConnectedNumberView;

import jakarta.validation.Valid;

/**
 * A merchant connecting their WhatsApp number.
 *
 * <p>Self-service on purpose. The obvious alternative — a mapping in the config repository — would
 * make every shop that signs up an engineering change, which is the difference between a feature
 * that scales and one that does not.
 */
@RestController
@RequestMapping("/api/whatsapp/numbers")
@PreAuthorize("hasRole('MERCHANT')")
public class ConnectedNumberController {

    private final NumberDirectory numbers;

    public ConnectedNumberController(NumberDirectory numbers) {
        this.numbers = numbers;
    }

    @GetMapping
    public List<ConnectedNumberView> mine() {
        return numbers.of(CurrentUser.requireId()).stream()
                .map(ConnectedNumberView::of)
                .toList();
    }

    @PostMapping
    public ResponseEntity<ConnectedNumberView> connect(@Valid @RequestBody ConnectNumberRequest request) {
        ConnectedNumber connected = numbers.connect(
                CurrentUser.requireId(),
                request.phoneNumberId().trim(),
                request.label(),
                request.displayNumber());
        return ResponseEntity.status(HttpStatus.CREATED).body(ConnectedNumberView.of(connected));
    }

    /**
     * Stops routing new messages to this shop.
     *
     * <p>Conversations survive. "Disconnect" means the number is no longer theirs, not that their
     * customer history is gone — losing every customer a shop has ever spoken to should not be a
     * side effect of switching providers.
     */
    @DeleteMapping("/{phoneNumberId}")
    public ResponseEntity<Void> disconnect(@PathVariable String phoneNumberId) {
        return numbers.disconnect(CurrentUser.requireId(), phoneNumberId)
                ? ResponseEntity.noContent().build()
                : ResponseEntity.notFound().build();
    }

    /** 409, not 500. Someone else holds the number, and that is an answer, not a failure. */
    @ExceptionHandler(NumberDirectory.NumberAlreadyConnectedException.class)
    public ResponseEntity<String> alreadyConnected(NumberDirectory.NumberAlreadyConnectedException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(e.getMessage());
    }
}

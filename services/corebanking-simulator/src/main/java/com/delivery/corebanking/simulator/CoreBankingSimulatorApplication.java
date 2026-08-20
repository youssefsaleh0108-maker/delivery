package com.delivery.corebanking.simulator;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * A stand-in for the bank (Section 7). <strong>Dev environments only — never staging or prod.</strong>
 *
 * <p>Its whole job is to let the accounting saga be built, demoed and tested end to end before real
 * bank credentials and a production banking agreement exist. Staging and production point the same
 * connector at the real Core Banking System through the Backoffice toggle, and nothing about the
 * connector changes.
 *
 * <p>Two properties make it worth running as a service rather than mocking inside the connector's
 * tests. It speaks real HTTP, so the connector's timeouts, breaker and retry behaviour are
 * exercised for real. And it enforces idempotency in the database with a unique constraint, the way
 * a real ledger does — so "a retried debit must not move money twice" is proven rather than assumed.
 *
 * <p><strong>Contract drift is the standing risk</strong> (Section 12, open decision #5: nobody owns
 * keeping this in step with the bank's published spec). Everything about the shape of these
 * endpoints is a guess until that spec is in hand, which is why the connector talks to it through a
 * narrow client interface with a second implementation for the real bank.
 */
@SpringBootApplication
public class CoreBankingSimulatorApplication {

    public static void main(String[] args) {
        SpringApplication.run(CoreBankingSimulatorApplication.class, args);
    }
}

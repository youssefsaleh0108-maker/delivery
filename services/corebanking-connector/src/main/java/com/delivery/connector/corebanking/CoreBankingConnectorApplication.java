package com.delivery.connector.corebanking;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The only process that talks to the bank (Section 7).
 *
 * <p>Holds the bank credentials and nothing else — no database, no order data, no business rules
 * about commission. Section 10 singles this out as the most sensitive integration in the system and
 * gives its Vault path a policy of its own; keeping the process that reads that path this small is
 * the other half of that.
 *
 * <p>Consumes postings off a queue and never exposes a send endpoint, so a slow bank cannot hold up
 * an order no matter how anyone later wires it.
 */
@SpringBootApplication
public class CoreBankingConnectorApplication {

    public static void main(String[] args) {
        SpringApplication.run(CoreBankingConnectorApplication.class, args);
    }
}

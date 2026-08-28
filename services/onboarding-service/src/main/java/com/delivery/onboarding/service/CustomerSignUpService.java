package com.delivery.onboarding.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.delivery.onboarding.client.KeycloakAdminClient;
import com.delivery.onboarding.domain.ContactVerification.Channel;

/**
 * Customer self-service sign-up.
 *
 * <p><strong>Deliberately not an application.</strong> A merchant or a rider is reviewed because
 * the platform is deciding whether to do business with them; a shopper is not. Nobody waits for
 * approval to order food, and a Backoffice queue full of people who just want dinner would bury the
 * partner applications that actually need a decision.
 *
 * <p>What it shares with the reviewed path is the proof. The same one-time code machinery — with
 * its cooldown, daily cap and wrong-guess limit — issues a token, and this spends it. That is what
 * stops the endpoint being a way to create accounts on addresses somebody does not own, which
 * matters more here than on the reviewed path: there, a human reads the application before anything
 * is provisioned, and here the account exists the moment this returns.
 */
@Service
public class CustomerSignUpService {

    private static final Logger log = LoggerFactory.getLogger(CustomerSignUpService.class);

    private final VerificationService verifications;
    private final KeycloakAdminClient keycloak;

    public CustomerSignUpService(VerificationService verifications, KeycloakAdminClient keycloak) {
        this.verifications = verifications;
        this.keycloak = keycloak;
    }

    /**
     * Spends the proof and creates the account.
     *
     * <p>REQUIRES_NEW and transactional around the token, for the same reason the application
     * intake is: a proof consumed against a sign-up that then failed would leave somebody holding a
     * code they can no longer use and cannot get back.
     *
     * <p>The ORDER matters. The token is consumed first, so a caller cannot spend one proof on
     * several accounts by racing; Keycloak is called second. If Keycloak then refuses — almost
     * always because the address already has an account — the transaction rolls back and the proof
     * is returned, which is the right outcome for somebody who mistyped and is about to retry.
     *
     * @param verificationToken from {@code POST /verifications/confirm} on the same address
     * @return the Keycloak {@code sub} of the new account
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public String signUp(String email, String verificationToken, String firstName, String lastName,
                         String password) {

        verifications.consume(verificationToken, Channel.EMAIL, email);

        String normalised = verifications.normalise(Channel.EMAIL, email);
        String sub = keycloak.createCustomer(normalised, firstName, lastName, password);

        log.info("Customer {} signed up", normalised);
        return sub;
    }
}

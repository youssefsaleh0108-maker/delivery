package com.delivery.appnotification.domain;

/**
 * Which side of an order chat somebody is on.
 *
 * <p>Only these two. There is no MERCHANT and no BACKOFFICE member, and that absence is the design:
 * a conversation's membership is derived from the order, so there is no code path that could add a
 * third participant even by accident.
 *
 * <p>This, rather than the sender's user id, is what the API returns on a message. The role is all
 * the UI needs to draw a bubble on the correct side, and handing a rider the customer's Keycloak
 * sub — or the reverse — would be giving each of them a durable identifier for the other that
 * outlives the delivery.
 */
public enum ChatParticipantRole {
    CUSTOMER,
    RIDER
}

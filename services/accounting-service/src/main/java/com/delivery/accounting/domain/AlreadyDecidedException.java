package com.delivery.accounting.domain;

/**
 * A decision on a payout request that has already been decided (RECON-07).
 *
 * <p>Two people act on the same request — two operators on one queue row, or an operator and the
 * requester — and the second finds it paid, refused or withdrawn. That is a conflict with the
 * request's current state, not a malformed call, so the API answers it 409 as it answers the
 * optimistic-lock failure of two decisions committed at the same moment.
 *
 * <p>An {@link IllegalStateException}, so a caller written before it existed still treats it as
 * the refusal it always was.
 */
public class AlreadyDecidedException extends IllegalStateException {

    public AlreadyDecidedException(String message) {
        super(message);
    }
}

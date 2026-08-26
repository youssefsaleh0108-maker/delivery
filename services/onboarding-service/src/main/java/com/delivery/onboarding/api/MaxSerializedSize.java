package com.delivery.onboarding.api;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import jakarta.validation.Constraint;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;
import jakarta.validation.Payload;

/**
 * Rejects a value whose JSON serialisation exceeds a byte budget. Null passes.
 *
 * <p>Exists for the free-form {@code details} document on an application, which is validated for
 * size and nothing else. {@code @Size} cannot do this job: counting entries says nothing about a
 * map whose one value is a megabyte of text, and the thing the database and the reviewer actually
 * pay for is the serialised document.
 *
 * <p>A bean-validation constraint rather than a service-layer check so an oversized document is a
 * plain 400 alongside every other field error, before anything is spent or written.
 */
@Documented
@Constraint(validatedBy = MaxSerializedSize.Validator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT})
@Retention(RetentionPolicy.RUNTIME)
public @interface MaxSerializedSize {

    String message() default "must serialise to no more than {bytes} bytes of JSON";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};

    /** The budget, in bytes of UTF-8 JSON. */
    int bytes();

    class Validator implements ConstraintValidator<MaxSerializedSize, Object> {

        /**
         * A private, default-configured mapper on purpose: the measurement must not drift with
         * whatever modules or pretty-printing the application's shared mapper picks up.
         */
        private static final ObjectMapper MAPPER = new ObjectMapper();

        private int bytes;

        @Override
        public void initialize(MaxSerializedSize constraint) {
            this.bytes = constraint.bytes();
        }

        @Override
        public boolean isValid(Object value, ConstraintValidatorContext context) {
            if (value == null) {
                return true;
            }
            try {
                return MAPPER.writeValueAsBytes(value).length <= bytes;
            } catch (JsonProcessingException e) {
                // Cannot be serialised at all — certainly cannot be stored as jsonb.
                return false;
            }
        }
    }
}

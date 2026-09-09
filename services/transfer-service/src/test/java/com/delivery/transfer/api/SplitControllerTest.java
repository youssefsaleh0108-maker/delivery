package com.delivery.transfer.api;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.support.WebDataBinderFactory;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.method.support.HandlerMethodArgumentResolver;
import org.springframework.web.method.support.ModelAndViewContainer;

import com.delivery.transfer.service.SplitService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * A split plan is only as validated as the shares inside it.
 *
 * <p>{@code @Valid} on the body stops at the body: the {@code @NotNull}s on a share are cascaded
 * to only if the collection holding them asks for it, so a share with no {@code amountUsd} passed
 * every constraint on the way in and was summed with {@code BigDecimal::add} — a 500 over a field
 * the caller simply left out, and the one wording that would have told them which.
 */
@ExtendWith(MockitoExtension.class)
class SplitControllerTest {

    private static final String HOST = "host-sub";

    @Mock private SplitService service;

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new SplitController(service))
                .setControllerAdvice(new ApiExceptionHandler())
                .setCustomArgumentResolvers(new CallersJwt())
                .build();
    }

    @Test
    @DisplayName("a share missing its amount is the caller's 400, not our 500")
    void shareMissingItsAmountIsA400() throws Exception {
        String body = mvc.perform(post("/api/transfers/splits")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"mode":"EVEN","totalUsd":30.00,"storeName":"Falafel Abou Andre",
                                 "shares":[{"username":"rami","name":"Rami"}]}
                                """))
                .andExpect(status().isBadRequest())
                .andReturn().getResponse().getContentAsString();

        // Named down to the element, so the client fixes a row rather than resubmitting the plan.
        assertThat(body).contains("shares[0].amountUsd");
        // Nothing was created: the refusal happens before the plan exists, not after it is saved.
        verify(service, never()).create(any(), any(), any(), any(), any(), any(), any());
    }

    /** Stands in for the resource server's principal, which no test has a real token from. */
    private static final class CallersJwt implements HandlerMethodArgumentResolver {

        private final Jwt jwt = Jwt.withTokenValue("test-token")
                .header("alg", "none")
                .subject(HOST)
                .claim("preferred_username", HOST)
                .build();

        @Override
        public boolean supportsParameter(MethodParameter parameter) {
            return Jwt.class.equals(parameter.getParameterType());
        }

        @Override
        public Object resolveArgument(MethodParameter parameter, ModelAndViewContainer mav,
                                      NativeWebRequest request, WebDataBinderFactory binder) {
            return jwt;
        }
    }
}

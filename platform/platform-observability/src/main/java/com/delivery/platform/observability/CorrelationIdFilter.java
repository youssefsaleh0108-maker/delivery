package com.delivery.platform.observability;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Puts a correlation id on every inbound request, for the servlet services.
 *
 * <p>The Gateway generates the id at the edge (Section 10); downstream services inherit it from the
 * header. A service reached directly — a scheduled job hitting an internal endpoint, or a developer
 * with curl — gets a fresh one, so no request is ever untraced.
 *
 * <p>Runs at {@link Ordered#HIGHEST_PRECEDENCE} so the id is in the MDC before anything else can
 * log, including the security filter chain's rejections.
 */
public class CorrelationIdFilter extends OncePerRequestFilter implements Ordered {

    public static final String MDC_KEY = "correlationId";
    public static final String HEADER = "X-Correlation-Id";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        // Sanitised, not trusted: the header is client-supplied and this value reaches both the log
        // and a varchar(64) column inside the caller's own transaction. See CorrelationIds.
        String correlationId = CorrelationIds.sanitize(request.getHeader(HEADER));

        MDC.put(MDC_KEY, correlationId);
        response.setHeader(HEADER, correlationId);
        try {
            filterChain.doFilter(request, response);
        } finally {
            // Threads are pooled and reused; leaving the id set would mislabel the next request.
            MDC.remove(MDC_KEY);
        }
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}

package com.delivery.platform.observability;

import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.server.WebFilter;
import org.springframework.web.server.WebFilterChain;

import reactor.core.publisher.Mono;
import reactor.util.context.Context;

/**
 * The reactive twin of {@link CorrelationIdFilter}, for the API Gateway.
 *
 * <p>This is where the correlation id is <em>born</em> for most traffic: the Gateway is the single
 * entry point, so an id minted here is the one that travels through the bus and into every
 * connector's outbound call (Section 10).
 *
 * <p>The id is written into the Reactor context rather than a thread-local, because a WebFlux
 * request is not pinned to one thread. It is also mutated onto the forwarded request so downstream
 * services receive it, and echoed on the response so a client can quote it in a bug report.
 */
public class CorrelationIdWebFilter implements WebFilter, Ordered {

    public static final String CONTEXT_KEY = "correlationId";
    public static final String HEADER = "X-Correlation-Id";

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        // The Gateway is where most ids are born, and also where a hostile one would enter. Sanitise
        // before it is forwarded downstream, so no service inherits an unsafe value. See
        // CorrelationIds for what "unsafe" costs.
        String correlationId =
                CorrelationIds.sanitize(exchange.getRequest().getHeaders().getFirst(HEADER));

        ServerWebExchange mutated = exchange.mutate()
                .request(builder -> builder.header(HEADER, correlationId))
                .build();
        mutated.getResponse().getHeaders().set(HEADER, correlationId);

        return chain.filter(mutated)
                .contextWrite(Context.of(CONTEXT_KEY, correlationId))
                // Best-effort MDC for logs emitted synchronously on this signal. Reactor may hop
                // threads mid-stream, so the Reactor context above is the authoritative carrier —
                // this only makes the common case readable in the log output.
                .doFirst(() -> MDC.put(CONTEXT_KEY, correlationId))
                .doFinally(signal -> MDC.remove(CONTEXT_KEY));
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }
}

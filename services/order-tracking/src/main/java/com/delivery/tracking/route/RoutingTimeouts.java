package com.delivery.tracking.route;

import java.time.Duration;

import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * The connect and read timeouts every routing call is made under — the same shape
 * {@code CarrierDirectoryClient} uses for its own call, and for the same reason.
 *
 * <p>A customer's map makes several routing calls per refresh, and a request thread is held for
 * every second of each of them. With no timeout at all, a routing host that accepts connections
 * and then stops answering holds those threads until the operating system gives up, which on this
 * service means the threads that should be taking rider pings. One or two seconds is generous for
 * a routing engine on the same node and short enough that a dead one is noticed by the request
 * rather than by an alert: the map then draws straight lines and says they are approximate.
 */
final class RoutingTimeouts {

    private RoutingTimeouts() {
    }

    /**
     * Makes this builder's calls time out.
     *
     * <p>Zero or negative switches them off, and the builder keeps whatever request factory it
     * already carries. That is the socket convention for "no timeout", and it is also what lets a
     * test bind a mock server to these calls: a factory set here would replace the mock's.
     */
    static RestClient.Builder apply(RestClient.Builder builder, Duration connectTimeout,
                                    Duration readTimeout) {
        if (isOff(connectTimeout) || isOff(readTimeout)) {
            return builder;
        }
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connectTimeout.toMillis());
        factory.setReadTimeout((int) readTimeout.toMillis());
        return builder.requestFactory(factory);
    }

    private static boolean isOff(Duration timeout) {
        return timeout == null || timeout.isZero() || timeout.isNegative();
    }
}

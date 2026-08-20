package com.delivery.whatsapp.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Everything the WhatsApp front door needs to know about the outside world.
 *
 * <p>Note what is <em>not</em> here: which number belongs to which merchant. That is a merchant
 * onboarding themselves, not an environment setting, and it lives in the database — see
 * {@code NumberDirectory}.
 */
@ConfigurationProperties(prefix = "delivery.whatsapp")
public class WhatsAppProperties {

    /**
     * The shared secret the provider signs webhook bodies with.
     *
     * <p>Blank means the webhook rejects everything. That is deliberate: the alternative — "no
     * secret configured, so skip the check" — leaves the endpoint accepting anything precisely on
     * the deployments where nobody finished the setup, which is when it is least likely to be
     * noticed. Same reasoning as the DLR translators.
     */
    private String appSecret = "";

    /** The challenge value Meta's Cloud API echoes back when registering the callback URL. */
    private String verifyToken = "";

    /** Where outbound replies are POSTed. The simulator locally, the Cloud API in a deployment. */
    private String outboundUrl = "";

    /** Bearer token for the outbound API. Blank in dev, where the simulator wants no auth. */
    private String accessToken = "";

    public String getAppSecret() {
        return appSecret;
    }

    public void setAppSecret(String appSecret) {
        this.appSecret = appSecret;
    }

    public String getVerifyToken() {
        return verifyToken;
    }

    public void setVerifyToken(String verifyToken) {
        this.verifyToken = verifyToken;
    }

    public String getOutboundUrl() {
        return outboundUrl;
    }

    public void setOutboundUrl(String outboundUrl) {
        this.outboundUrl = outboundUrl;
    }

    public String getAccessToken() {
        return accessToken;
    }

    public void setAccessToken(String accessToken) {
        this.accessToken = accessToken;
    }
}

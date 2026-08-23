package com.delivery.connector.sms.provider;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailSendException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

import com.delivery.platform.notifications.DeliveryOutcome;
import com.delivery.platform.notifications.NotificationCommand;
import com.delivery.platform.notifications.ProviderClient;

/**
 * The dev provider: delivers "what the SMS would have said" to a test inbox over SMTP.
 *
 * <p>Section 7's dev mode. It exists so the whole notification chain — outbox, manager, worker,
 * connector, resilience, receipt — can be exercised end to end without a paid SMS account or a real
 * handset, and so the platform can launch before the MontyMobile/Twilio commercial decision is made
 * (Section 12, open decision #6).
 *
 * <p>A real send rather than a log line WHEN A TEST INBOX IS CONFIGURED, so that the SMTP hop, the
 * failure classification and the receipt path are exercised before a real vendor is switched on.
 * With no inbox set it falls back to logging — see {@link #send} for why that is the deployed
 * default now that mailpit is gone.

package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.StatementDispatch;
import com.delivery.accounting.domain.StatementDispatchRepository;

/**
 * Emailing a statement, and the three things that must not happen when you do.
 *
 * <p>Sending a shop's figures somewhere nobody named. Sending the same period twice, which a
 * merchant reads as a second amount owed. And recording a send that did not happen, which is worse
 * than recording nothing because it makes the operator stop chasing it.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("sending a statement")
class StatementDispatchTest {

    private static final String SHOP = "merchant-sub-1";
    private static final String OPERATOR = "backoffice-sub-1";

    @Mock
    private StatementService statements;
    @Mock
    private StatementDispatchRepository dispatches;
    @Mock
    private CounterpartyDirectory directory;
    @Mock
    private NotificationsClient notifications;

    private StatementDispatchService service;
    private StatementRange august;
    private Statement statement;

    @BeforeEach
    void setUp() {
        service = new StatementDispatchService(statements, dispatches, directory,
                new StatementRenderer(), notifications);
        august = StatementRange.of(LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"),
                ZoneId.of("UTC"));
        statement = Statement.of(CounterpartyKind.MERCHANT, SHOP, "Rose & Crust Pizzeria",
                august, "USD",
                List.of(Statement.Line.credit("Goods sold", new BigDecimal("2425.00"), "45 orders"),
                        Statement.Line.debit("Platform commission (12.5%)",
                                new BigDecimal("303.20"), null)),
                new BigDecimal("2121.80"), List.of(), 45, null);
    }

    private void everythingIsFine() {
        when(directory.recipientOf(CounterpartyKind.MERCHANT, SHOP))
                .thenReturn("shop@example.com");
        when(statements.build(eq(CounterpartyKind.MERCHANT), eq(SHOP), any()))
                .thenReturn(statement);
        when(dispatches.save(any(StatementDispatch.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        Mockito.lenient().when(notifications.sendDirect(anyString(), anyString(), anyString(),
                anyString(), anyString())).thenReturn("notification-1");
    }

    @Test
    @DisplayName("sends to the address on file and records what went where")
    void sendsAndRecords() {
        everythingIsFine();

        StatementDispatch sent = service.send(CounterpartyKind.MERCHANT, SHOP, august,
                null, false, OPERATOR);

        verify(notifications).sendDirect(eq("EMAIL"), eq("shop@example.com"),
                anyString(), anyString(), eq("ACCOUNTING_STATEMENT"));

        assertThat(sent.getRecipient()).isEqualTo("shop@example.com");
        assertThat(sent.getSentBy()).isEqualTo(OPERATOR);
        assertThat(sent.getPeriodFrom()).isEqualTo(LocalDate.parse("2026-08-01"));
        assertThat(sent.getPeriodTo()).isEqualTo(LocalDate.parse("2026-08-29"));
        // What it said, in one number, so "what did we tell them in August" survives late rows
        // arriving in the ledger afterwards.
        assertThat(sent.getNetAmount()).isEqualByComparingTo("2121.80");
        assertThat(sent.getNetDirection()).isEqualTo("WE_OWE");
        assertThat(sent.getNotificationRef()).isEqualTo("notification-1");
    }

    @Test
    @DisplayName("prefers an address the operator supplied")
    void overrideWins() {
        when(statements.build(eq(CounterpartyKind.MERCHANT), eq(SHOP), any()))
                .thenReturn(statement);
        when(dispatches.save(any(StatementDispatch.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));

        service.send(CounterpartyKind.MERCHANT, SHOP, august, "accounts@example.com", false,
                OPERATOR);

        verify(notifications).sendDirect(eq("EMAIL"), eq("accounts@example.com"),
                anyString(), anyString(), anyString());
        // The directory is not even consulted: an operator who typed an address meant it.
        verify(directory, never()).recipientOf(any(), anyString());
    }

    @Test
    @DisplayName("refuses rather than guessing when no address can be resolved")
    void noRecipientIsRefused() {
        when(directory.recipientOf(CounterpartyKind.CARRIER, "provider-1")).thenReturn(null);

        assertThatThrownBy(() -> service.send(CounterpartyKind.CARRIER, "provider-1", august,
                null, false, OPERATOR))
                .isInstanceOf(StatementDispatchService.NoRecipientException.class)
                .hasMessageContaining("none was supplied");

        // Nothing was rendered, nothing was sent, and nothing was recorded. Sending a carrier's
        // figures to a best-guess address is a disclosure, not a delivery.
        verifyNoInteractions(notifications);
        verify(dispatches, never()).save(any());
    }

    @Test
    @DisplayName("refuses to send the same period twice by accident")
    void aRepeatIsRefused() {
        when(directory.recipientOf(CounterpartyKind.MERCHANT, SHOP))
                .thenReturn("shop@example.com");
        StatementDispatch previous = new StatementDispatch(CounterpartyKind.MERCHANT, SHOP,
                LocalDate.parse("2026-08-01"), LocalDate.parse("2026-08-29"), "EMAIL",
                "shop@example.com", new BigDecimal("2121.80"), "WE_OWE", "USD", "n-1", OPERATOR);
        when(dispatches.findFirstByCounterpartyKindAndCounterpartyRefAndPeriodFromAndPeriodToOrderBySentAtDesc(
                CounterpartyKind.MERCHANT, SHOP, august.from(), august.to()))
                .thenReturn(Optional.of(previous));

        assertThatThrownBy(() -> service.send(CounterpartyKind.MERCHANT, SHOP, august,
                null, false, OPERATOR))
                .isInstanceOf(StatementDispatchService.AlreadySentException.class);

        verifyNoInteractions(notifications);
    }

    @Test
    @DisplayName("sends it anyway when the operator says they mean it")
    void anExplicitResendIsAllowed() {
        everythingIsFine();

        service.send(CounterpartyKind.MERCHANT, SHOP, august, null, true, OPERATOR);

        // A genuine re-send is a real thing — the first one bounced, the figures were restated —
        // and the duplicate check is deliberately not a database constraint for that reason.
        verify(notifications).sendDirect(anyString(), anyString(), anyString(), anyString(),
                anyString());
        // The check is skipped entirely rather than run and ignored.
        verify(dispatches, never())
                .findFirstByCounterpartyKindAndCounterpartyRefAndPeriodFromAndPeriodToOrderBySentAtDesc(
                        any(), anyString(), any(), any());
    }

    @Test
    @DisplayName("records nothing when the message could not be sent")
    void aFailedSendIsNotRecorded() {
        when(directory.recipientOf(CounterpartyKind.MERCHANT, SHOP))
                .thenReturn("shop@example.com");
        when(statements.build(eq(CounterpartyKind.MERCHANT), eq(SHOP), any()))
                .thenReturn(statement);
        when(notifications.sendDirect(anyString(), anyString(), anyString(), anyString(),
                anyString())).thenThrow(new IllegalStateException("notifications are down"));

        assertThatThrownBy(() -> service.send(CounterpartyKind.MERCHANT, SHOP, august,
                null, false, OPERATOR))
                .isInstanceOf(IllegalStateException.class);

        // A row here is a claim that a shop was told. Writing one for a message that never left
        // would make the operator stop chasing it, which is worse than no record at all.
        verify(dispatches, never()).save(any());
    }

    @Test
    @DisplayName("builds the statement itself rather than trusting one it was handed")
    void theFiguresMatchThePeriodRecorded() {
        everythingIsFine();

        service.send(CounterpartyKind.MERCHANT, SHOP, august, null, false, OPERATOR);

        ArgumentCaptor<StatementRange> range = ArgumentCaptor.forClass(StatementRange.class);
        verify(statements).build(eq(CounterpartyKind.MERCHANT), eq(SHOP), range.capture());
        // A statement passed in could have been computed against a different range from the one
        // being recorded, and the row would then claim a period the figures never covered.
        assertThat(range.getValue().from()).isEqualTo(august.from());
        assertThat(range.getValue().to()).isEqualTo(august.to());
    }

    @Test
    @DisplayName("keeps the message inside the limits Notifications Manager enforces")
    void theRenderedMessageFits() {
        StatementRenderer renderer = new StatementRenderer();

        assertThat(renderer.subject(statement)).hasSizeLessThanOrEqualTo(StatementRenderer.MAX_SUBJECT);
        assertThat(renderer.body(statement)).hasSizeLessThanOrEqualTo(StatementRenderer.MAX_BODY);
        // The totals always survive; only the itemisation is budgeted.
        assertThat(renderer.body(statement))
                .contains("2425.00")
                .contains("303.20")
                .contains("The platform owes you 2121.80 USD.");
    }
}

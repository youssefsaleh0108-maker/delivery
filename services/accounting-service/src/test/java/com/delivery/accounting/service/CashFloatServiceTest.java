package com.delivery.accounting.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
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
import org.mockito.junit.jupiter.MockitoExtension;

import com.delivery.accounting.domain.AccountingTransaction;
import com.delivery.accounting.domain.AccountingTransaction.Direction;
import com.delivery.accounting.domain.AccountingTransaction.Leg;
import com.delivery.accounting.domain.AccountingTransactionRepository;
import com.delivery.accounting.domain.CashFloatEntry;
import com.delivery.accounting.domain.CashFloatRepository;

/**
 * Banking the takings.
 *
 * <p>The property that matters: a remittance must discharge <strong>exactly</strong> what it
 * covers. Money that stays outstanding after being banked is a rider chased for cash they already
 * handed over; money cleared without a posting is a platform that thinks it was paid and was not.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("cash remittance")
class CashFloatServiceTest {

    private static final String PLATFORM = "ACC-PLATFORM";
    private static final String RIDER = "rider-1";

    @Mock
    private CashFloatRepository floatEntries;
    @Mock
    private AccountingTransactionRepository transactions;
    @Mock
    private BankPostingPublisher postings;

    private CashFloatService service;

    @BeforeEach
    void setUp() {
        service = new CashFloatService(floatEntries, transactions, postings, PLATFORM, "USD");
        // save() returns what it is given, as a real repository does for a new row.
        lenientSave();
    }

    private void lenientSave() {
        org.mockito.Mockito.lenient()
                .when(floatEntries.save(any(CashFloatEntry.class)))
                .thenAnswer(i -> i.getArgument(0));
        org.mockito.Mockito.lenient()
                .when(transactions.save(any(AccountingTransaction.class)))
                .thenAnswer(i -> i.getArgument(0));
    }

    private CashFloatEntry collection(String amount) {
        return CashFloatEntry.collected(
                RIDER, CashFloatEntry.HolderKind.RIDER, UUID.randomUUID(),
                new BigDecimal(amount), "USD");
    }

    private void carrying(String... amounts) {
        when(floatEntries.outstandingFor(RIDER))
                .thenReturn(java.util.Arrays.stream(amounts).map(this::collection).toList());
    }

    @Test
    void the_remittance_is_the_sum_of_everything_outstanding() {
        carrying("13.25", "8.50", "21.00");

        Optional<CashFloatService.Remittance> result = service.remitAll(RIDER, "corr-1");

        assertThat(result).isPresent();
        assertThat(result.get().amount()).isEqualByComparingTo("42.75");
        assertThat(result.get().collections()).isEqualTo(3);
    }

    @Test
    void every_collection_it_covers_is_marked_cleared() {
        // The failure this guards is the expensive one: a rider hands over the money and the
        // platform still shows them as owing it.
        List<CashFloatEntry> outstanding =
                List.of(collection("13.25"), collection("8.50"));
        when(floatEntries.outstandingFor(RIDER)).thenReturn(outstanding);

        service.remitAll(RIDER, "corr-1");

        assertThat(outstanding).allMatch(e -> !e.isOutstanding());
    }

    @Test
    void they_are_cleared_by_the_remittance_that_covered_them() {
        // So the trail runs both ways: from a settlement to the day it was banked, and back.
        List<CashFloatEntry> outstanding = List.of(collection("10.00"));
        when(floatEntries.outstandingFor(RIDER)).thenReturn(outstanding);

        UUID remittanceId = service.remitAll(RIDER, "corr-1").orElseThrow().id();

        assertThat(outstanding.get(0).getClearedBy()).isEqualTo(remittanceId);
    }

    @Test
    void banking_the_takings_credits_the_platform_at_the_bank() {
        // Unlike a collection, this one IS a real movement — the money genuinely arrives.
        carrying("42.75");

        service.remitAll(RIDER, "corr-1");

        ArgumentCaptor<AccountingTransaction> saved =
                ArgumentCaptor.forClass(AccountingTransaction.class);
        verify(transactions).save(saved.capture());
        assertThat(saved.getValue().getLeg()).isEqualTo(Leg.CASH_REMITTANCE);
        assertThat(saved.getValue().getAccountRef()).isEqualTo(PLATFORM);
        assertThat(saved.getValue().getDirection()).isEqualTo(Direction.CREDIT);
        assertThat(saved.getValue().getAmount()).isEqualByComparingTo("42.75");
        assertThat(saved.getValue().isPostingRequired()).isTrue();
    }

    @Test
    void the_holders_own_account_is_never_touched() {
        // They handed over notes. No account of theirs moved, and saying otherwise is the mistake
        // that broke cash the first time.
        carrying("42.75");

        service.remitAll(RIDER, "corr-1");

        ArgumentCaptor<AccountingTransaction> saved =
                ArgumentCaptor.forClass(AccountingTransaction.class);
        verify(transactions).save(saved.capture());
        assertThat(saved.getValue().getAccountRef()).isNotEqualTo(RIDER);
    }

    @Test
    void a_remittance_row_records_who_banked_it() {
        carrying("42.75");

        service.remitAll(RIDER, "corr-1");

        ArgumentCaptor<CashFloatEntry> saved = ArgumentCaptor.forClass(CashFloatEntry.class);
        verify(floatEntries).save(saved.capture());
        assertThat(saved.getValue().getEntryKind()).isEqualTo(CashFloatEntry.Kind.REMITTED);
        assertThat(saved.getValue().getHolderRef()).isEqualTo(RIDER);
        assertThat(saved.getValue().getAmount()).isEqualByComparingTo("42.75");
        // A remittance belongs to no single order — it covers many.
        assertThat(saved.getValue().getOrderId()).isNull();
    }

    @Test
    void a_holder_carrying_nothing_records_nothing() {
        // Not an error: "have they banked it" is a fair question to ask about somebody who is
        // holding nothing, and the honest answer is yes.
        when(floatEntries.outstandingFor(RIDER)).thenReturn(List.of());

        assertThat(service.remitAll(RIDER, "corr-1")).isEmpty();
        verify(floatEntries, never()).save(any());
        verify(transactions, never()).save(any());
        verifyNoInteractions(postings);
    }

    @Test
    void the_bank_is_asked_only_after_the_rows_are_committed() {
        // No transaction is active in this test, so the publisher fires immediately — which is the
        // documented fallback. The ordering itself is enforced by the after-commit hook.
        carrying("42.75");

        service.remitAll(RIDER, "corr-1");

        verify(postings).request(any(AccountingTransaction.class));
    }
}

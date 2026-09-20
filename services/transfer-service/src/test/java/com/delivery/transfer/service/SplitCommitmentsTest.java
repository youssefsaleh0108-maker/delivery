package com.delivery.transfer.service;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import com.delivery.transfer.client.OrderManagerClient;
import com.delivery.transfer.client.OrderManagerClient.OrderSummary;
import com.delivery.transfer.connector.CashOnDeliveryConnector;
import com.delivery.transfer.connector.ConnectorRegistry;
import com.delivery.transfer.connector.MoneyTransferConnector;
import com.delivery.transfer.connector.SimulatedWalletConnector;
import com.delivery.transfer.domain.MoneyTransfer;
import com.delivery.transfer.domain.MoneyTransferRepository;
import com.delivery.transfer.domain.SplitPlan;
import com.delivery.transfer.domain.SplitPlanRepository;
import com.delivery.transfer.domain.SplitShare;
import com.delivery.transfer.domain.TransferMethod;
import com.delivery.transfer.domain.TransferStatus;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * RECON-01: a share counts as paid only when money moved.
 *
 * <p>The deep test found a 19.50 cash order whose split plan held the host's 14.50 as {@code PAID /
 * HOST_ORDER} and a friend's wallet share as {@code PAID / WHISH} though nothing had taken either:
 * the rider's checklist listed them under "Already paid digitally" and asked for 5.00, while the
 * ledger booked all 19.50 as cash collected at the door. These pin the server's half of the fix —
 * promises are {@code COMMITTED}, a simulated wallet says so, a wallet nothing can carry is refused,
 * and the shares add up to the order the rider collects.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("RECON-01: a share counts as paid only when money moved")
class SplitCommitmentsTest {

    private static final String HOST_REF = "host-sub";
    private static final String HOST = "host";
    private static final String FRIEND = "friend";
    private static final UUID ORDER = UUID.fromString("42c91f1c-4883-4620-9842-f8b190f8c429");

    @Mock private SplitPlanRepository plans;
    @Mock private MoneyTransferRepository transferRows;
    @Mock private OrderManagerClient orders;

    /** Dev as deployed: cash, and the wallet simulator (SIMULATE_WALLETS=true). */
    private SplitService dev;

    @BeforeEach
    void setUp() {
        dev = service(new CashOnDeliveryConnector(), new SimulatedWalletConnector(true));
        when(plans.save(any())).thenAnswer(call -> call.getArgument(0));
        when(plans.findByOrderId(any())).thenReturn(Optional.empty());
    }

    private SplitService service(MoneyTransferConnector... connectors) {
        TransferService transfers = new TransferService(transferRows,
                new ConnectorRegistry(List.of(connectors)), orders,
                new BigDecimal("90000"), new BigDecimal("100000"));
        return new SplitService(plans, transfers);
    }

    /** The deep test's plan: a 19.50 order, one friend in the app owing 5.00. */
    private SplitPlan planWithFriend(SplitService service) {
        SplitPlan plan = service.create(HOST_REF, HOST, "Host Name", "Recon", SplitPlan.Mode.EVEN,
                new BigDecimal("19.50"),
                List.of(new SplitService.NewShare(FRIEND, "Friend", new BigDecimal("5.00"), 1)));
        when(plans.findById(plan.getId())).thenReturn(Optional.of(plan));
        return plan;
    }

    private static SplitShare shareOf(SplitPlan plan, String username) {
        return plan.getShares().stream()
                .filter(s -> username.equals(s.getPayeeUsername()))
                .findFirst().orElseThrow();
    }

    private static BigDecimal sum(SplitPlan plan) {
        return plan.getShares().stream()
                .map(SplitShare::getAmountUsd)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    @Nested
    @DisplayName("create")
    class Create {

        @Test
        @DisplayName("the host's own slice is committed with the order, never paid")
        void hostSliceIsCommittedNotPaid() {
            SplitPlan plan = dev.create(HOST_REF, HOST, "Host Name", "Recon", SplitPlan.Mode.EVEN,
                    new BigDecimal("19.50"),
                    List.of(new SplitService.NewShare(null, "Guest", new BigDecimal("5.00"), 1)));

            SplitShare host = shareOf(plan, HOST);
            assertThat(host.getStatus()).isEqualTo(SplitShare.Status.COMMITTED);
            assertThat(host.getMethod()).isEqualTo(SplitShare.Method.HOST_ORDER);
            assertThat(host.getAmountUsd()).isEqualByComparingTo("14.50");
            assertThat(host.getPaidAt()).isNull();
            // The guest pays at the door: promised, not paid, either.
            SplitShare guest = plan.getShares().stream()
                    .filter(s -> s.getPayeeUsername() == null).findFirst().orElseThrow();
            assertThat(guest.getStatus()).isEqualTo(SplitShare.Status.COMMITTED);
            assertThat(guest.getMethod()).isEqualTo(SplitShare.Method.CASH_AT_DOOR);
            assertThat(plan.getShares()).noneMatch(s -> s.getStatus() == SplitShare.Status.PAID);
            // Nobody is left to answer, so the host can place it.
            assertThat(plan.getStatus()).isEqualTo(SplitPlan.Status.READY);
        }

        /**
         * A host who lists themselves among the lines used to lose that line's amount: it was taken
         * off the host's slice and then dropped, so the plan held less than the order.
         */
        @Test
        @DisplayName("a line naming the host stays in the total")
        void hostsOwnLineStaysInTheTotal() {
            SplitPlan plan = dev.create(HOST_REF, HOST, "Host Name", "Recon", SplitPlan.Mode.ITEMIZED,
                    new BigDecimal("19.50"), List.of(
                            new SplitService.NewShare(HOST, "Host Name", new BigDecimal("4.00"), 2),
                            new SplitService.NewShare(FRIEND, "Friend", new BigDecimal("5.00"), 1)));

            assertThat(plan.getShares()).hasSize(2);
            assertThat(shareOf(plan, HOST).getAmountUsd()).isEqualByComparingTo("14.50");
            assertThat(sum(plan)).isEqualByComparingTo("19.50");
        }

        @Test
        @DisplayName("amounts are cents before they are summed, so the shares make the total")
        void sharesMakeTheTotalToTheCent() {
            SplitPlan plan = dev.create(HOST_REF, HOST, "Host Name", "Recon", SplitPlan.Mode.EVEN,
                    new BigDecimal("10.005"), List.of(
                            new SplitService.NewShare(FRIEND, "Friend", new BigDecimal("3.333"), 1),
                            new SplitService.NewShare(null, "Guest", new BigDecimal("3.333"), 1)));

            assertThat(plan.getTotalUsd()).isEqualByComparingTo("10.01");
            assertThat(sum(plan)).isEqualByComparingTo(plan.getTotalUsd());
            assertThat(plan.getShares()).allMatch(s -> s.getAmountUsd().scale() == 2);
        }

        @Test
        @DisplayName("a negative share is refused before anything is saved")
        void negativeShareIsRefused() {
            assertThatThrownBy(() -> dev.create(HOST_REF, HOST, "Host Name", "Recon",
                    SplitPlan.Mode.EVEN, new BigDecimal("19.50"),
                    List.of(new SplitService.NewShare(FRIEND, "Friend", new BigDecimal("-5.00"), 1))))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY);
        }
    }

    @Nested
    @DisplayName("answer")
    class Answer {

        @Test
        @DisplayName("cash at the door is a promise, not a payment")
        void cashAtTheDoorIsCommitted() {
            SplitPlan plan = planWithFriend(dev);

            dev.answer(plan.getId(), "friend-sub", FRIEND, true, SplitShare.Method.CASH_AT_DOOR);

            SplitShare share = shareOf(plan, FRIEND);
            assertThat(share.getStatus()).isEqualTo(SplitShare.Status.COMMITTED);
            assertThat(share.getMethod()).isEqualTo(SplitShare.Method.CASH_AT_DOOR);
            assertThat(share.getPaidAt()).isNull();
            assertThat(plan.getStatus()).isEqualTo(SplitPlan.Status.READY);
        }

        @Test
        @DisplayName("a wallet the dev simulator stands in for is labelled simulated, not paid")
        void simulatedWalletIsLabelled() {
            SplitPlan plan = planWithFriend(dev);

            dev.answer(plan.getId(), "friend-sub", FRIEND, true, SplitShare.Method.WHISH);

            SplitShare share = shareOf(plan, FRIEND);
            assertThat(share.getStatus()).isEqualTo(SplitShare.Status.COMMITTED);
            assertThat(share.getMethod()).isEqualTo(SplitShare.Method.WHISH);
            assertThat(share.isSimulated()).isTrue();
            assertThat(share.getPaidAt()).isNull();
        }

        @Test
        @DisplayName("a wallet nothing carries is refused, as the checkout refuses it")
        void walletWithoutAConnectorIsRefused() {
            SplitService noWallets = service(new CashOnDeliveryConnector(),
                    new SimulatedWalletConnector(false));
            SplitPlan plan = planWithFriend(noWallets);

            assertThatThrownBy(() -> noWallets.answer(plan.getId(), "friend-sub", FRIEND, true,
                    SplitShare.Method.WHISH))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY)
                    .hasMessageContaining("No provider currently carries WHISH");
            assertThat(shareOf(plan, FRIEND).getStatus()).isEqualTo(SplitShare.Status.PENDING);
        }

        /**
         * A real provider carries a transfer against an order; nothing takes a share's money through
         * it. Trusting it would record exactly the payment-that-did-not-happen this finding is about.
         */
        @Test
        @DisplayName("a real provider is refused rather than trusted to have taken the money")
        void realProviderIsNotTrusted() {
            SplitService withRealWhish = service(new CashOnDeliveryConnector(), new RealWhish(),
                    new SimulatedWalletConnector(true));
            SplitPlan plan = planWithFriend(withRealWhish);

            assertThatThrownBy(() -> withRealWhish.answer(plan.getId(), "friend-sub", FRIEND, true,
                    SplitShare.Method.WHISH))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY)
                    .hasMessageContaining("choose cash at the door");
            assertThat(shareOf(plan, FRIEND).getStatus()).isEqualTo(SplitShare.Status.PENDING);
        }

        @Test
        @DisplayName("the host's own method is not an invitee's answer")
        void hostOrderIsNotAnAnswer() {
            SplitPlan plan = planWithFriend(dev);

            assertThatThrownBy(() -> dev.answer(plan.getId(), "friend-sub", FRIEND, true,
                    SplitShare.Method.HOST_ORDER))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY);
        }
    }

    @Nested
    @DisplayName("the methods an invitee is offered")
    class Offered {

        @Test
        @DisplayName("on dev: every wallet, each marked simulated, and cash at the door")
        void devOffersSimulatedWallets() {
            assertThat(dev.shareMethods()).containsExactly(
                    new SplitService.ShareMethod(SplitShare.Method.WHISH, true),
                    new SplitService.ShareMethod(SplitShare.Method.OMT, true),
                    new SplitService.ShareMethod(SplitShare.Method.BOB, true),
                    new SplitService.ShareMethod(SplitShare.Method.CASH_AT_DOOR, false));
        }

        @Test
        @DisplayName("with no simulator: cash at the door only")
        void withoutASimulatorOnlyCash() {
            SplitService noWallets = service(new CashOnDeliveryConnector(),
                    new SimulatedWalletConnector(false));

            assertThat(noWallets.shareMethods()).containsExactly(
                    new SplitService.ShareMethod(SplitShare.Method.CASH_AT_DOOR, false));
        }

        @Test
        @DisplayName("a wallet a real provider carries is not offered for a share")
        void realProviderIsNotOffered() {
            SplitService withRealWhish = service(new CashOnDeliveryConnector(), new RealWhish(),
                    new SimulatedWalletConnector(true));

            assertThat(withRealWhish.shareMethods())
                    .extracting(SplitService.ShareMethod::method)
                    .doesNotContain(SplitShare.Method.WHISH)
                    .contains(SplitShare.Method.CASH_AT_DOOR);
        }
    }

    /**
     * The plan is priced from the basket; the order is priced by Order Manager. The rider collects
     * the ORDER's total, so the shares must come to it.
     */
    @Nested
    @DisplayName("attach-order")
    class Attach {

        private OrderSummary order(String customer, String total) {
            return new OrderSummary(ORDER, customer, null, "PLACED", new BigDecimal(total),
                    "CASH", "DUE");
        }

        @Test
        @DisplayName("the host's slice takes what the order added, so the shares make its total")
        void sharesAreRepricedToTheOrder() {
            SplitPlan plan = planWithFriend(dev);
            // EXPRESS chosen at checkout: 2.00 on top of the basket the plan was made from.
            when(orders.fetch(ORDER)).thenReturn(order(HOST_REF, "21.50"));

            dev.attachOrder(plan.getId(), HOST_REF, ORDER);

            assertThat(plan.getStatus()).isEqualTo(SplitPlan.Status.PLACED);
            assertThat(plan.getOrderId()).isEqualTo(ORDER);
            assertThat(plan.getTotalUsd()).isEqualByComparingTo("21.50");
            assertThat(shareOf(plan, HOST).getAmountUsd()).isEqualByComparingTo("16.50");
            assertThat(shareOf(plan, FRIEND).getAmountUsd()).isEqualByComparingTo("5.00");
            assertThat(sum(plan)).isEqualByComparingTo("21.50");
        }

        @Test
        @DisplayName("someone else's order is refused")
        void someoneElsesOrderIsRefused() {
            SplitPlan plan = planWithFriend(dev);
            when(orders.fetch(ORDER)).thenReturn(order("somebody-else", "19.50"));

            assertThatThrownBy(() -> dev.attachOrder(plan.getId(), HOST_REF, ORDER))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.FORBIDDEN);
            assertThat(plan.getOrderId()).isNull();
        }

        @Test
        @DisplayName("an order that already has a split takes no second one")
        void oneOrderOnePlan() {
            SplitPlan plan = planWithFriend(dev);
            SplitPlan earlier = planWithFriend(dev);
            when(orders.fetch(ORDER)).thenReturn(order(HOST_REF, "19.50"));
            when(plans.findByOrderId(ORDER)).thenReturn(Optional.of(earlier));

            assertThatThrownBy(() -> dev.attachOrder(plan.getId(), HOST_REF, ORDER))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.CONFLICT);
            assertThat(plan.getOrderId()).isNull();
        }

        @Test
        @DisplayName("an order below the friends' shares is refused rather than given a negative slice")
        void orderBelowTheFriendsSharesIsRefused() {
            SplitPlan plan = planWithFriend(dev);
            when(orders.fetch(ORDER)).thenReturn(order(HOST_REF, "4.00"));

            assertThatThrownBy(() -> dev.attachOrder(plan.getId(), HOST_REF, ORDER))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasFieldOrPropertyWithValue("statusCode", HttpStatus.UNPROCESSABLE_ENTITY);
            assertThat(plan.getOrderId()).isNull();
            assertThat(sum(plan)).isEqualByComparingTo("19.50");
        }
    }

    /** A Whish integration as it would one day be wired: ready, real, first in line. */
    private static final class RealWhish implements MoneyTransferConnector {

        @Override
        public String name() {
            return "whish";
        }

        @Override
        public boolean supports(TransferMethod method) {
            return method == TransferMethod.WHISH;
        }

        @Override
        public boolean ready() {
            return true;
        }

        @Override
        public void initiate(MoneyTransfer transfer) {
            transfer.carriedBy(name(), "WHISH-1", TransferStatus.INITIATED);
        }
    }
}

package com.delivery.accounting.api;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.delivery.accounting.domain.CounterpartyKind;
import com.delivery.accounting.domain.StatementDispatch;
import com.delivery.accounting.service.CarrierCompanyClient;
import com.delivery.accounting.service.Statement;
import com.delivery.accounting.service.StatementDispatchService;
import com.delivery.accounting.service.StatementRange;
import com.delivery.accounting.service.StatementService;

/**
 * Statements: what the platform owes each counterparty, and what they owe it.
 *
 * <p><strong>Two audiences on one controller, and the boundary between them is the whole point.</strong>
 * The Backoffice routes name a counterparty in the path, because an operator acting on somebody
 * else's behalf is what they are for. {@code /mine} names nobody: the kind comes from the caller's
 * realm role and the reference from their token subject, so there is no parameter to tamper with and
 * no code path on which a merchant could ask for another merchant's money. That is the one property
 * of this file worth checking before anything else.
 *
 * <p><strong>The role checks are written twice on purpose.</strong> {@code @PreAuthorize} is the
 * enforcement; the explicit check inside each method is the second lock. Method security is a proxy
 * that a misconfigured filter chain, a missing {@code @EnableMethodSecurity} or a direct call can
 * bypass, and the cost of being wrong here is one shop reading another's revenue. It also means the
 * refusals are provable from a plain controller test rather than only from a fully wired context —
 * a rule nobody can test is a rule that quietly stops holding.
 */
@RestController
@RequestMapping("/api/accounting/statements")
public class StatementController {

    /**
     * Realm role to counterparty kind, in the order they are tried.
     *
     * <p>An account holding two of these is not a shape the platform creates, but a fixed order
     * means it resolves the same way every time rather than depending on how Keycloak happened to
     * serialise the roles. CUSTOMER and BACKOFFICE are deliberately absent: neither has a statement,
     * and a customer's record of what they paid is the order.
     */
    private static final List<Map.Entry<String, CounterpartyKind>> SELF_SERVE_ROLES = List.of(
            Map.entry("ROLE_MERCHANT", CounterpartyKind.MERCHANT),
            Map.entry("ROLE_DELIVERY", CounterpartyKind.RIDER),
            Map.entry("ROLE_CARRIER", CounterpartyKind.CARRIER));

    private final StatementService statements;
    private final StatementDispatchService dispatch;

    /**
     * Turns a carrier's Keycloak subject into the provider id their legs are actually attributed
     * with. Every other kind is keyed on the subject directly; a carrier is not, and the mismatch
     * used to render as an empty statement rather than as an error. See {@link CarrierCompanyClient}.
     */
    private final CarrierCompanyClient carrierCompanies;

    public StatementController(StatementService statements, StatementDispatchService dispatch,
                               CarrierCompanyClient carrierCompanies) {
        this.statements = statements;
        this.dispatch = dispatch;
        this.carrierCompanies = carrierCompanies;
    }

    // ------------------------------------------------------------------------------ Backoffice

    /** Everyone with activity in the range, with the headline number and what could not be assigned. */
    @GetMapping("/counterparties")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> counterparties(@RequestParam String from, @RequestParam String to) {
        ResponseEntity<?> refusal = requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        StatementRange range;
        try {
            range = rangeOf(from, to);
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        }

        StatementService.Counterparties listing;
        try {
            listing = statements.list(range);
        } catch (IllegalStateException e) {
            return unbalanced(e);
        }

        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("from", range.from().toString());
        payload.put("to", range.to().toString());
        payload.put("currency", listing.currency());
        payload.put("counterparties", listing.counterparties().stream()
                .map(StatementController::summaryPayload)
                .toList());

        Map<String, Object> unattributed = new LinkedHashMap<>();
        unattributed.put("amount", money(listing.unattributed().amount()));
        unattributed.put("orders", listing.unattributed().orders());
        unattributed.put("note", listing.unattributed().note());
        payload.put("unattributed", unattributed);

        return ResponseEntity.ok(payload);
    }

    /** One counterparty's statement. Names them in the path, so it is BACKOFFICE only. */
    @GetMapping("/{kind}/{ref}")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> statement(@PathVariable String kind, @PathVariable String ref,
                                       @RequestParam String from, @RequestParam String to) {
        ResponseEntity<?> refusal = requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        CounterpartyKind counterparty = CounterpartyKind.parse(kind);
        if (counterparty == null) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Not a counterparty kind: " + kind));
        }
        try {
            return ResponseEntity.ok(
                    statementPayload(statements.build(counterparty, ref, rangeOf(from, to))));
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        } catch (IllegalStateException e) {
            return unbalanced(e);
        }
    }

    /**
     * Emails the statement for a period.
     *
     * <p>BACKOFFICE only and never triggered by a schedule in this change. Sending money figures to
     * a shop is a decision somebody makes, and the dispatch row records which somebody.
     */
    @PostMapping("/{kind}/{ref}/send")
    @PreAuthorize("hasRole('BACKOFFICE')")
    public ResponseEntity<?> send(@PathVariable String kind, @PathVariable String ref,
                                  @RequestParam String from, @RequestParam String to,
                                  @RequestBody(required = false) SendRequest body) {
        ResponseEntity<?> refusal = requireRole("BACKOFFICE");
        if (refusal != null) {
            return refusal;
        }
        CounterpartyKind counterparty = CounterpartyKind.parse(kind);
        if (counterparty == null) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", "Not a counterparty kind: " + kind));
        }

        Jwt caller = jwt();
        if (caller == null) {
            return unauthenticated();
        }

        try {
            StatementDispatch sent = dispatch.send(counterparty, ref, rangeOf(from, to),
                    body == null ? null : body.to(),
                    body != null && Boolean.TRUE.equals(body.resend()),
                    caller.getSubject());

            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("sentTo", sent.getRecipient());
            payload.put("sentAt", sent.getSentAt().toString());
            payload.put("dispatchId", sent.getId().toString());
            return ResponseEntity.ok(payload);

        } catch (IllegalArgumentException e) {
            return badRequest(e);

        } catch (IllegalStateException e) {
            // The statement is built inside the send, so the balance check can fire here too — and
            // an unbalanced statement must not be emailed to anybody.
            return unbalanced(e);

        } catch (StatementDispatchService.NoRecipientException e) {
            // 409, not 400: the request is well formed and the caller did nothing wrong. The
            // platform simply does not know where to send this, and the fix is to supply an address.
            return ResponseEntity.status(409).body(Map.of(
                    "error", e.getMessage(),
                    "code", "NO_RECIPIENT"));

        } catch (StatementDispatchService.AlreadySentException e) {
            // A CONTRACT EXTENSION, and a deliberate one. The contract names 409 only for a missing
            // address; this is the second thing that makes an operator's month-end go wrong, and a
            // merchant receiving August twice reads the second copy as a second amount owed. The
            // distinct `code` is what lets a client tell the two apart, and `resend` is the way
            // through for somebody who means it.
            Map<String, Object> payload = new LinkedHashMap<>();
            payload.put("error", e.getMessage());
            payload.put("code", "ALREADY_SENT");
            payload.put("sentTo", e.previous().getRecipient());
            payload.put("sentAt", e.previous().getSentAt().toString());
            payload.put("dispatchId", e.previous().getId().toString());
            return ResponseEntity.status(409).body(payload);
        }
    }

    /** {@code {"to":"..."}} to override the address, {@code {"resend":true}} to repeat a period. */
    public record SendRequest(String to, Boolean resend) {
    }

    // ------------------------------------------------------------------------------ self-serve

    /**
     * The caller's own statement, and nobody else's.
     *
     * <p>No counterparty parameter exists on this route, which is the point: the kind is read from
     * the caller's realm role and the reference from {@code sub}. There is nothing here for a
     * merchant to change in order to read another shop's figures, and no branch that could be made
     * to accept one.
     *
     * <p>403 for a role with no statement — a customer, or a Backoffice operator with no partner
     * role of their own. Backoffice staff read other people's statements through the route above,
     * which records nothing about them being their own counterparty.
     */
    @GetMapping("/mine")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> mine(@RequestParam String from, @RequestParam String to) {
        Jwt caller = jwt();
        if (caller == null) {
            return unauthenticated();
        }

        CounterpartyKind kind = selfServeKind();
        if (kind == null) {
            return ResponseEntity.status(403).body(Map.of(
                    "error", "Your account has no statement. Statements exist for merchants, "
                            + "riders and delivery companies."));
        }

        // The reference, resolved from the caller and from nothing else.
        //
        // A merchant and a rider are keyed on their Keycloak subject, which is what the settlement
        // wrote. A CARRIER is not: their legs carry Order Manager's provider id, so the subject has
        // to be exchanged for one. That exchange still starts from the token — see
        // CarrierCompanyClient — so no branch here can be made to accept a reference from a caller.
        String ref;
        try {
            ref = kind == CounterpartyKind.CARRIER
                    ? carrierCompanies.companyIdFor(caller.getTokenValue())
                    : caller.getSubject();
        } catch (CarrierCompanyClient.NoCompanyException e) {
            // Says so, rather than answering a zeroed statement. Owed-nothing and
            // not-attached-to-a-company are different facts and used to look identical.
            return ResponseEntity.status(403).body(Map.of(
                    "error", "This account is not staff of a delivery company, so it has no "
                            + "statement. Ask whoever runs the company to add you to it."));
        } catch (IllegalStateException e) {
            // Order Manager unreachable. A 503 and not an empty statement: a carrier reading
            // "you are owed nothing" during an outage is the failure this whole path exists to end.
            return ResponseEntity.status(503).body(Map.of(
                    "error", "Your statement could not be built just now. Please try again."));
        }

        try {
            // jwt.getSubject(), never a parameter. The single most important expression in the file.
            return ResponseEntity.ok(statementPayload(
                    statements.build(kind, ref, rangeOf(from, to))));
        } catch (IllegalArgumentException e) {
            return badRequest(e);
        } catch (IllegalStateException e) {
            return unbalanced(e);
        }
    }

    // -------------------------------------------------------------------------------- plumbing

    /**
     * The caller's kind, or null if they have no statement.
     *
     * <p>Read from the granted authorities rather than from a claim in the token body: the platform's
     * role converter has already validated and normalised those, and re-reading {@code realm_access}
     * here would be a second, weaker copy of a rule that is settled elsewhere.
     */
    private static CounterpartyKind selfServeKind() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null) {
            return null;
        }
        for (Map.Entry<String, CounterpartyKind> candidate : SELF_SERVE_ROLES) {
            boolean holds = authentication.getAuthorities().stream()
                    .anyMatch(granted -> candidate.getKey().equals(granted.getAuthority()));
            if (holds) {
                return candidate.getValue();
            }
        }
        return null;
    }

    /**
     * The second lock on a Backoffice route. Null when the caller may proceed.
     *
     * <p>See the class note: {@code @PreAuthorize} is the enforcement and this is the check that
     * still holds if the proxy is not there.
     */
    private static ResponseEntity<?> requireRole(String role) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || jwt() == null) {
            return unauthenticated();
        }
        boolean holds = authentication.getAuthorities().stream()
                .anyMatch(granted -> ("ROLE_" + role).equals(granted.getAuthority()));
        return holds ? null : ResponseEntity.status(403).body(Map.of(
                "error", "That is a " + role + " view."));
    }

    private static ResponseEntity<?> unauthenticated() {
        return ResponseEntity.status(401).body(Map.of("error", "Sign in first."));
    }

    private static Jwt jwt() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return (authentication instanceof JwtAuthenticationToken token) ? token.getToken() : null;
    }

    /**
     * Parses and validates the period.
     *
     * <p>Both failures — a date that is not a date, and a range that is inverted or too long — come
     * back as one {@link IllegalArgumentException} and one 400, because they are the same kind of
     * mistake from the caller's side. The MESSAGES stay distinct, which is the part that helps.
     */
    private StatementRange rangeOf(String from, String to) {
        LocalDate start = date(from, "from");
        LocalDate end = date(to, "to");
        return StatementRange.of(start, end, statements.zone());
    }

    private static LocalDate date(String value, String field) {
        try {
            return LocalDate.parse(value.trim());
        } catch (DateTimeParseException | NullPointerException e) {
            throw new IllegalArgumentException(field + " must be an ISO date, like 2026-08-01");
        }
    }

    private static ResponseEntity<?> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    /**
     * A statement that does not balance, surfaced as a legible failure rather than a stack trace.
     *
     * <p>Deliberately a 500 and not a partial document. The lines disagreeing with the ledger is a
     * bug in this service, and returning the figures anyway with a warning attached would mean the
     * wrong numbers reaching a shop with the caveat trimmed off by whatever renders them. There is
     * nothing the caller can do differently, so the honest answer is that the platform cannot
     * produce this statement right now.
     */
    private static ResponseEntity<?> unbalanced(IllegalStateException e) {
        return ResponseEntity.status(500).body(Map.of(
                "error", "That statement does not balance and will not be served: " + e.getMessage(),
                "code", "STATEMENT_DOES_NOT_BALANCE"));
    }

    private static Map<String, Object> summaryPayload(StatementService.Summary summary) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("kind", summary.kind().name());
        row.put("ref", summary.ref());
        row.put("name", summary.name());
        row.put("net", money(summary.net()));
        row.put("direction", summary.direction().name());
        row.put("orders", summary.orders());
        row.put("recipient", summary.recipient());
        row.put("lastSentAt", summary.lastSentAt() == null ? null : summary.lastSentAt().toString());
        return row;
    }

    /**
     * The statement, exactly in the shape the contract states.
     *
     * <p>Built by hand rather than serialised from the record, and that is not ceremony. The record
     * carries an order count the contract does not, and every amount has to reach the wire as a
     * string with two decimals — Jackson would render a {@code BigDecimal} as a JSON number, which
     * loses the trailing zero on 17.00 and invites the client to parse money as a float.
     */
    private static Map<String, Object> statementPayload(Statement statement) {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("kind", statement.kind().name());
        payload.put("ref", statement.ref());
        payload.put("name", statement.name());
        payload.put("from", statement.from().toString());
        payload.put("to", statement.to().toString());
        payload.put("currency", statement.currency());
        payload.put("generatedAt", statement.generatedAt().toString());

        payload.put("lines", statement.lines().stream().map(line -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("label", line.label());
            row.put("amount", money(line.amount()));
            row.put("direction", line.direction().name());
            row.put("note", line.note());
            return row;
        }).toList());

        Map<String, Object> net = new LinkedHashMap<>();
        net.put("amount", money(statement.net().amount()));
        net.put("direction", statement.net().direction().name());
        payload.put("net", net);

        payload.put("entries", statement.entries().stream().map(entry -> {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("orderId", entry.orderId() == null ? null : entry.orderId().toString());
            row.put("at", entry.at() == null ? null : entry.at().toString());
            row.put("gross", money(entry.gross()));
            row.put("commission", money(entry.commission()));
            row.put("net", money(entry.net()));
            row.put("paymentMethod", entry.paymentMethod());
            return row;
        }).toList());

        payload.put("note", statement.note());
        return payload;
    }

    /** Money on the wire is a string with exactly two decimals. Never a JSON number. */
    private static String money(BigDecimal amount) {
        return Statement.money(amount).toPlainString();
    }
}

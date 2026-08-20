package com.delivery.whatsapp.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.data.domain.Example;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;

import com.delivery.whatsapp.domain.ConnectedNumber;
import com.delivery.whatsapp.repo.ConnectedNumberRepository;

/**
 * Who owns which number.
 *
 * <p>The routing table for the whole feature, so the interesting cases are all about somebody else's
 * shop: a wrong answer here does not lose a message, it delivers one merchant's customer to another.
 */
class NumberDirectoryTest {

    private static final String SHOP = "merchant-a";
    private static final String OTHER_SHOP = "merchant-b";
    private static final String NUMBER = "PN-100";

    private InMemoryNumbers repository;
    private NumberDirectory directory;

    @BeforeEach
    void setUp() {
        repository = new InMemoryNumbers();
        directory = new NumberDirectory(repository);
    }

    @Test
    void anUnclaimedNumberBelongsToNobody() {
        assertThat(directory.merchantFor(NUMBER)).isEmpty();
    }

    @Test
    void aConnectedNumberRoutesToItsMerchant() {
        directory.connect(SHOP, NUMBER, "Front counter", "+96170000001");

        assertThat(directory.merchantFor(NUMBER)).contains(SHOP);
    }

    @Test
    void refusesANumberAnotherShopAlreadyHolds() {
        directory.connect(SHOP, NUMBER, "Front counter", "+96170000001");

        assertThatThrownBy(() -> directory.connect(OTHER_SHOP, NUMBER, "Mine now", "+96170000001"))
                .isInstanceOf(NumberDirectory.NumberAlreadyConnectedException.class);

        // The point of the refusal: silently reassigning would hand a competitor's live
        // conversations to whoever claimed the number second.
        assertThat(directory.merchantFor(NUMBER)).contains(SHOP);
    }

    @Test
    void reconnectingYourOwnNumberJustRenamesIt() {
        directory.connect(SHOP, NUMBER, "Front counter", "+96170000001");
        directory.connect(SHOP, NUMBER, "Main line", "+96170000002");

        assertThat(directory.merchantFor(NUMBER)).contains(SHOP);
        assertThat(directory.of(SHOP)).singleElement()
                .satisfies(number -> {
                    assertThat(number.getLabel()).isEqualTo("Main line");
                    assertThat(number.getDisplayNumber()).isEqualTo("+96170000002");
                });
    }

    @Test
    void aShopCanHoldSeveralNumbers() {
        directory.connect(SHOP, "PN-1", "Front counter", "+96170000001");
        directory.connect(SHOP, "PN-2", "Branch line", "+96170000002");

        assertThat(directory.of(SHOP)).hasSize(2);
        assertThat(directory.merchantFor("PN-2")).contains(SHOP);
    }

    @Test
    void aMerchantCannotDisconnectSomeoneElsesNumber() {
        directory.connect(SHOP, NUMBER, "Front counter", "+96170000001");

        assertThat(directory.disconnect(OTHER_SHOP, NUMBER)).isFalse();
        assertThat(directory.merchantFor(NUMBER)).contains(SHOP);
    }

    @Test
    void disconnectingStopsRoutingWithoutTouchingConversations() {
        directory.connect(SHOP, NUMBER, "Front counter", "+96170000001");

        assertThat(directory.disconnect(SHOP, NUMBER)).isTrue();
        assertThat(directory.merchantFor(NUMBER)).isEmpty();
        // Conversations live in their own table with no foreign key to this one, so releasing a
        // number cannot cascade a shop's customer history away.
        assertThat(directory.of(SHOP)).isEmpty();
    }

    @Test
    void disconnectingSomethingThatWasNeverConnectedIsNotAnError() {
        assertThat(directory.disconnect(SHOP, "PN-never")).isFalse();
    }

    @Test
    void aBlankNumberIdBelongsToNobody() {
        directory.connect(SHOP, NUMBER, "Front counter", "+96170000001");

        // A callback with no metadata must not fall through to some arbitrary shop.
        assertThat(directory.merchantFor(null)).isEmpty();
        assertThat(directory.merchantFor("")).isEmpty();
        assertThat(directory.merchantFor("   ")).isEmpty();
    }

    /**
     * Enough of the repository to exercise the rules, without a database. The directory's logic is
     * entirely about ownership, and none of it is expressed in SQL.
     */
    private static class InMemoryNumbers implements ConnectedNumberRepository {

        private final Map<String, ConnectedNumber> rows = new LinkedHashMap<>();

        @Override
        public List<ConnectedNumber> findByMerchantRefOrderByConnectedAtAsc(String merchantRef) {
            List<ConnectedNumber> found = new ArrayList<>();
            rows.values().forEach(number -> {
                if (number.belongsTo(merchantRef)) {
                    found.add(number);
                }
            });
            return found;
        }

        @Override
        public <S extends ConnectedNumber> S save(S entity) {
            rows.put(entity.getPhoneNumberId(), entity);
            return entity;
        }

        @Override
        public Optional<ConnectedNumber> findById(String id) {
            return Optional.ofNullable(rows.get(id));
        }

        @Override
        public void delete(ConnectedNumber entity) {
            rows.remove(entity.getPhoneNumberId());
        }

        // Everything below is unused by the directory.
        @Override public <S extends ConnectedNumber> List<S> saveAll(Iterable<S> entities) { throw new UnsupportedOperationException(); }
        @Override public boolean existsById(String id) { return rows.containsKey(id); }
        @Override public List<ConnectedNumber> findAll() { return new ArrayList<>(rows.values()); }
        @Override public List<ConnectedNumber> findAllById(Iterable<String> ids) { throw new UnsupportedOperationException(); }
        @Override public long count() { return rows.size(); }
        @Override public void deleteById(String id) { rows.remove(id); }
        @Override public void deleteAllById(Iterable<? extends String> ids) { throw new UnsupportedOperationException(); }
        @Override public void deleteAll(Iterable<? extends ConnectedNumber> entities) { throw new UnsupportedOperationException(); }
        @Override public void deleteAll() { rows.clear(); }
        @Override public List<ConnectedNumber> findAll(Sort sort) { throw new UnsupportedOperationException(); }
        @Override public Page<ConnectedNumber> findAll(Pageable pageable) { throw new UnsupportedOperationException(); }
        @Override public void flush() { }
        @Override public <S extends ConnectedNumber> S saveAndFlush(S entity) { return save(entity); }
        @Override public <S extends ConnectedNumber> List<S> saveAllAndFlush(Iterable<S> entities) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllInBatch(Iterable<ConnectedNumber> entities) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllByIdInBatch(Iterable<String> ids) { throw new UnsupportedOperationException(); }
        @Override public void deleteAllInBatch() { rows.clear(); }
        @Override public ConnectedNumber getOne(String id) { throw new UnsupportedOperationException(); }
        @Override public ConnectedNumber getById(String id) { throw new UnsupportedOperationException(); }
        @Override public ConnectedNumber getReferenceById(String id) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber> Optional<S> findOne(Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber> List<S> findAll(Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber> List<S> findAll(Example<S> example, Sort sort) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber> Page<S> findAll(Example<S> example, Pageable pageable) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber> long count(Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber> boolean exists(Example<S> example) { throw new UnsupportedOperationException(); }
        @Override public <S extends ConnectedNumber, R> R findBy(Example<S> example,
                java.util.function.Function<org.springframework.data.repository.query.FluentQuery.FetchableFluentQuery<S>, R> queryFunction) {
            throw new UnsupportedOperationException();
        }
    }
}

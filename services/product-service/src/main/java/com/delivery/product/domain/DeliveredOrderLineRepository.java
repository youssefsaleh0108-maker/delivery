package com.delivery.product.domain;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface DeliveredOrderLineRepository
        extends JpaRepository<DeliveredOrderLine, DeliveredOrderLine.Key> {

    /**
     * What else was in the delivered baskets that contained this product.
     *
     * <p>The whole of the cross-sell rail's evidence, and it is worth being precise about what each
     * clause is doing, because the difference between this and a fabricated "popular items" list is
     * entirely in the detail.
     *
     * <p>{@code COUNT(DISTINCT other.orderId)} counts <em>baskets</em>, not units. A customer who
     * bought six of something in one order is one piece of evidence that the two things go together,
     * not six; summing quantities would let a single large order dominate the rail.
     *
     * <p>{@code other.storeId = mine.storeId} keeps the answer orderable. A basket cannot span two
     * shops today, so this changes nothing now — but if it ever can, a rail suggesting something the
     * customer cannot add to the basket they are looking at is worse than an empty rail.
     *
     * <p>The {@code HAVING} floor is what keeps this honest at low volume. One shared basket is an
     * anecdote; presenting it as "people also ordered" would dress a single stranger's shopping trip
     * up as a pattern. The caller supplies the floor — see
     * {@code delivery.catalog.cross-sell.min-orders-together}.
     *
     * <p>Ordering by count then by id, so a tie is resolved deterministically rather than by
     * whatever order the planner happened to produce. A rail that reshuffles itself on every refresh
     * reads as broken.
     *
     * @return rows of {@code [productId (UUID), ordersTogether (Long)]}, strongest first
     */
    @Query("""
            SELECT other.productId, COUNT(DISTINCT other.orderId)
            FROM DeliveredOrderLine mine
            JOIN DeliveredOrderLine other ON other.orderId = mine.orderId
            WHERE mine.productId = :productId
              AND other.productId <> :productId
              AND other.storeId = mine.storeId
            GROUP BY other.productId
            HAVING COUNT(DISTINCT other.orderId) >= :minOrdersTogether
            ORDER BY COUNT(DISTINCT other.orderId) DESC, other.productId ASC
            """)
    List<Object[]> findBoughtWith(@Param("productId") UUID productId,
                                  @Param("minOrdersTogether") long minOrdersTogether,
                                  Pageable limit);

    /**
     * What one shop actually sold in a window, best first — the Menu Insights screen's best-seller
     * list.
     *
     * <p>{@code COUNT(DISTINCT l.orderId)} ranks, and {@code SUM(l.qty)} is reported beside it. The
     * same choice {@link #findBoughtWith} makes and for the same reason: a customer who bought six
     * of something in one order is one order that wanted it, and ranking on units would let a
     * single catering order decide what a shop believes its menu's best item is. Both figures are
     * useful to a merchant, so both are returned and neither is used for the other's job.
     *
     * <p><strong>No floor here, unlike every other aggregate in this service.</strong> The floors
     * elsewhere protect people who are not the shop's customers — searchers in the neighbourhood,
     * readers of a public page. These rows are the shop's own delivered orders, which it filled
     * itself and already has on its own receipts, and the table holds no customer id at all. A
     * floor would hide a small shop's real sales from the only party entitled to them.
     *
     * <p>The window is half-open: {@code from} inclusive, {@code until} exclusive, so a day is not
     * counted twice by two adjacent windows.
     *
     * @return rows of {@code [productId (UUID), baskets (Long), units (Long)]}, best first
     */
    @Query("""
            SELECT l.productId, COUNT(DISTINCT l.orderId), SUM(l.qty)
            FROM DeliveredOrderLine l
            WHERE l.storeId = :storeId
              AND l.deliveredAt >= :from
              AND l.deliveredAt < :until
            GROUP BY l.productId
            ORDER BY COUNT(DISTINCT l.orderId) DESC, SUM(l.qty) DESC, l.productId ASC
            """)
    List<Object[]> topSellersIn(@Param("storeId") UUID storeId,
                                @Param("from") Instant from,
                                @Param("until") Instant until,
                                Pageable limit);
}

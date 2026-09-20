package com.delivery.product.api.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import com.delivery.product.service.MerchantUnmetDemand;

/**
 * The Demand Radar's second read: what the shop's own neighbourhood looked for and did not find.
 *
 * <p><strong>What is deliberately not in this response.</strong> No customer, no account, no session,
 * no coordinate, no distance, no time finer than a week, and no exact count — every figure is a band
 * ({@code about}). The radar's density read answers the same way and for the same reason: a number a
 * merchant can subtract their own trade from is a number that can be resolved back towards a
 * household, and the shop does not need it to decide what to stock.
 */
public final class DemandDtos {

    private DemandDtos() {
    }

    /**
     * One term the neighbourhood asked for.
     *
     * @param kind        {@code NONE} when nothing answered at all, {@code FAR} when only shops
     *                    further than {@code farMetres} did
     * @param about       roughly how many searches asked for it, rounded down to a round number. The
     *                    client says "about {about}"; the exact count is never served
     * @param alreadySold true when the merchant's own shops list something matching it — "you stock
     *                    this and people near you still could not find it"
     */
    public record UnmetTermResponse(UUID areaId, String areaName, String region, String kind,
                                    String term, int about, int rank, boolean alreadySold) {

        static UnmetTermResponse of(MerchantUnmetDemand.Term term) {
            return new UnmetTermResponse(term.areaId(), term.areaName(), term.region(),
                    term.kind().name(), term.term(), term.about(), term.rank(), term.alreadySold());
        }
    }

    /**
     * @param weekStart Monday 00:00 in the platform's zone, as an instant. Data, never a formatted
     *                  date: the client renders it in the reader's own locale
     */
    public record UnmetWeekResponse(Instant weekStart, List<UnmetTermResponse> terms) {

        static UnmetWeekResponse of(MerchantUnmetDemand.Week week) {
            return new UnmetWeekResponse(week.weekStart(),
                    week.terms().stream().map(UnmetTermResponse::of).toList());
        }
    }

    /**
     * @param areasAround     how many areas the shop's neighbourhood has at all. Zero means the
     *                        platform does not know where the shop is — a different thing to tell a
     *                        merchant than "nothing went unanswered near you"
     * @param minimumPeople   how many different people must have asked for a term before it is shown
     *                        to anybody, so the screen can explain an empty week rather than
     *                        implying a quiet one
     * @param farMetres       what "the nearest shop is far away" meant
     */
    public record UnmetDemandResponse(UUID storeId, String region, int areasAround,
                                      int minimumPeople, int farMetres,
                                      UnmetWeekResponse thisWeek, UnmetWeekResponse lastWeek) {

        public static UnmetDemandResponse of(MerchantUnmetDemand.Report report) {
            return new UnmetDemandResponse(report.storeId(), report.region(), report.areasAround(),
                    report.minimumPeople(), report.farMetres(),
                    UnmetWeekResponse.of(report.thisWeek()), UnmetWeekResponse.of(report.lastWeek()));
        }
    }
}

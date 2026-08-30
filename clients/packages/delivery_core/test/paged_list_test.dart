import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The paging engine every unbounded list rides on.
///
/// What matters: one request per page however often the scroll asks, a filter change discarding
/// the page that was already in flight, a short page stopping the loop whatever the server claims,
/// a failed later page keeping the earlier ones, and the server's total surviving for headers.
void main() {
  Paged<String> page({
    required int number,
    required int totalPages,
    int perPage = 2,
    int? totalElements,
  }) =>
      Paged<String>(
        content: List<String>.generate(perPage, (int i) => 'p$number-$i'),
        page: number,
        totalPages: totalPages,
        totalElements: totalElements ?? totalPages * perPage,
      );

  test('loadMore appends pages and stops exactly at the reported end', () async {
    final List<int> asked = <int>[];
    final PagedList<String> list = PagedList<String>(
      pageSize: 2,
      fetch: (int p, int size) async {
        asked.add(p);
        return page(number: p, totalPages: 2);
      },
    );

    await list.refresh();
    expect(list.items, hasLength(2));
    expect(list.hasMore, isTrue);

    await list.loadMore();
    expect(list.items, hasLength(4));
    expect(list.hasMore, isFalse);

    // Asking again fetches nothing: the end is the end.
    await list.loadMore();
    expect(asked, <int>[0, 1]);
  });

  test('concurrent loadMore calls collapse to one request', () async {
    int calls = 0;
    final Completer<Paged<String>> gate = Completer<Paged<String>>();
    final PagedList<String> list = PagedList<String>(
      pageSize: 2,
      fetch: (int p, int size) {
        calls++;
        return gate.future;
      },
    );

    final Future<void> first = list.refresh();
    // The scroll fires many times per second; only the first may start a request.
    unawaited(list.loadMore());
    unawaited(list.loadMore());
    gate.complete(page(number: 0, totalPages: 3));
    await first;

    expect(calls, 1);
  });

  test('a refresh mid-flight discards the stale page', () async {
    final Completer<Paged<String>> slow = Completer<Paged<String>>();
    int generation = 0;
    final PagedList<String> list = PagedList<String>(
      pageSize: 2,
      fetch: (int p, int size) {
        generation++;
        if (generation == 1) {
          return slow.future; // the old filter's page, still in the air
        }
        return Future<Paged<String>>.value(page(number: p, totalPages: 1, perPage: 1));
      },
    );

    final Future<void> first = list.refresh(); // old filter
    final Future<void> second = list.refresh(); // filter changed
    slow.complete(page(number: 0, totalPages: 5)); // old answer lands late
    await Future.wait(<Future<void>>[first, second]);

    // Only the new filter's single row survives; the stale page is nowhere.
    expect(list.items, <String>['p0-0']);
    expect(list.hasMore, isFalse);
  });

  test('a short page stops the loop even when the server reports more', () async {
    final PagedList<String> list = PagedList<String>(
      pageSize: 2,
      fetch: (int p, int size) async =>
          Paged<String>(content: const <String>[], page: p, totalPages: 9, totalElements: 18),
    );

    await list.refresh();
    // Empty content: whatever totalPages claims, asking again would loop forever.
    expect(list.hasMore, isFalse);
  });

  test('a failed later page keeps the earlier ones and records the error', () async {
    int calls = 0;
    final PagedList<String> list = PagedList<String>(
      pageSize: 2,
      fetch: (int p, int size) async {
        calls++;
        if (calls == 2) throw StateError('down');
        return page(number: p, totalPages: 3);
      },
    );

    await list.refresh();
    await list.loadMore();

    expect(list.items, hasLength(2), reason: 'page one must survive page two failing');
    expect(list.error, isA<StateError>());
  });

  test('totalElements carries the server total and resets with the list', () async {
    final PagedList<String> list = PagedList<String>(
      pageSize: 2,
      fetch: (int p, int size) async =>
          page(number: p, totalPages: 4, totalElements: 34),
    );

    expect(list.totalElements, isNull);
    await list.refresh();
    // The header can say "34 shops" while only one page of them has arrived.
    expect(list.totalElements, 34);
    expect(list.items, hasLength(2));
  });

  test('shouldLoadMore is a near-the-end check, not a rail-length one', () {
    // A tall page far from its end: no fetch.
    expect(
      shouldLoadMore(FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 4000,
        pixels: 0,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      )),
      isFalse,
    );
    // The same page near its end: fetch.
    expect(
      shouldLoadMore(FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 4000,
        pixels: 3500,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      )),
      isTrue,
    );
    // A SHORT scrollable — a sideways chip rail — satisfies the check at position zero, which is
    // why the home screen must only consult depth-0 notifications. This pins the behaviour the
    // guard exists for.
    expect(
      shouldLoadMore(FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 400,
        pixels: 0,
        viewportDimension: 300,
        axisDirection: AxisDirection.right,
        devicePixelRatio: 1,
      )),
      isTrue,
    );
  });
}

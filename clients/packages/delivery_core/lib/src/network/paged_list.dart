import 'package:flutter/widgets.dart';

import '../models/catalog_models.dart';

/// Loads a list one page at a time.
///
/// Every list in these apps is potentially unbounded — a customer's favourites, a supermarket's
/// shelf, a merchant's order history — and fetching all of it to render the first screenful costs
/// the server a large query, the network a large payload, and the client a large layout pass, all
/// to show twenty rows.
///
/// Owning this in one place rather than per screen matters for the bits that are easy to get wrong:
/// not firing two requests for the same page, not appending a stale page after a filter change,
/// and not losing the previously loaded items when a later page fails.
class PagedList<T> extends ChangeNotifier {
  PagedList({required this.fetch, this.pageSize = 20});

  /// Fetches one page. Zero-based, matching Spring's `Pageable`.
  final Future<Paged<T>> Function(int page, int size) fetch;

  final int pageSize;

  final List<T> _items = <T>[];
  int _nextPage = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;

  /// Incremented on every [refresh]. A page that comes back carrying an old token is discarded —
  /// without this, changing a filter mid-flight appends the previous filter's results.
  int _generation = 0;

  List<T> get items => List<T>.unmodifiable(_items);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  /// True while the very first page is in flight — the state that shows a spinner rather than rows.
  bool get isLoadingFirstPage => _loading && !_loadedOnce;

  /// True while a subsequent page is in flight — the state that shows a footer spinner.
  bool get isLoadingMore => _loading && _loadedOnce;

  bool get hasMore => _hasMore;

  Object? get error => _error;

  /// True once a load has completed and found nothing — distinct from "not loaded yet", so an
  /// empty-state message is never shown over a list that is still arriving.
  bool get isEmptyAfterLoad => _loadedOnce && _items.isEmpty && _error == null;

  /// Discards everything and loads page zero.
  Future<void> refresh() {
    _generation++;
    _items.clear();
    _nextPage = 0;
    _hasMore = true;
    _loadedOnce = false;
    _error = null;
    return _load(_generation);
  }

  /// Loads the next page, if there is one and nothing is already in flight.
  Future<void> loadMore() {
    if (_loading || !_hasMore) {
      return Future<void>.value();
    }
    return _load(_generation);
  }

  Future<void> _load(int generation) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final Paged<T> page = await fetch(_nextPage, pageSize);
      // A refresh happened while this was in flight; its results belong to a list that no longer
      // exists.
      if (generation != _generation) {
        return;
      }
      _items.addAll(page.content);
      _nextPage = page.page + 1;
      // Trust the reported page count, and stop anyway on a short page — a server that reports
      // totals loosely should not put this in a loop.
      _hasMore = page.page + 1 < page.totalPages && page.content.isNotEmpty;
      _loadedOnce = true;
    } catch (e) {
      if (generation != _generation) {
        return;
      }
      // The already-loaded items stay. A failed page five must not blank out pages one to four.
      _error = e;
      _loadedOnce = true;
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Replaces an item in place, for an optimistic toggle like a favourite star.
  void replaceWhere(bool Function(T) test, T replacement) {
    final int index = _items.indexWhere(test);
    if (index >= 0) {
      _items[index] = replacement;
      notifyListeners();
    }
  }

  void removeWhere(bool Function(T) test) {
    final int removed = _items.length;
    _items.removeWhere(test);
    if (_items.length != removed) {
      notifyListeners();
    }
  }
}

/// How close to the bottom of a scroll view triggers the next page.
///
/// Expressed in pixels rather than a fraction so it behaves the same on a short phone list and a
/// long desktop grid: the aim is to start fetching roughly one screen before the user arrives, so
/// the spinner is never actually seen.
const double kLoadMoreThreshold = 600;

/// Whether a scroll position is near enough the end to fetch the next page.
bool shouldLoadMore(ScrollMetrics metrics) =>
    metrics.pixels >= metrics.maxScrollExtent - kLoadMoreThreshold;

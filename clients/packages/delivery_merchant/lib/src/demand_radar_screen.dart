import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'store_pin_map.dart';

/// The map slot's height in the frame.
const double _mapHeight = 220;

/// Close enough to read neighbourhood names — where the camera sits over a single area, and the
/// closest a fit around several may come.
const double _areaZoom = 14;

/// Demand Radar — Figma 121:8 (`demand-heatmap`), built for the audience it belongs to.
///
/// **A merchant's screen.** The frame is drawn inside the customer app with Home lit. It is not built
/// there and cannot be reached from there: where other customers are ordering is not something a
/// customer gets to browse. The endpoint behind it answers MERCHANT (their own shop) and BACKOFFICE
/// only, and the hosts open it for the shop's owner.
///
/// **What it can say.** Order Manager counts different customers per delivery area around the shop —
/// never the shop owner's own trade — and answers with a level per area, never a count, and only for
/// areas that reached a privacy floor (the answer carries it: five customers in the window). So the
/// map draws circles at area centres labelled "Hamra (High)", the list names the same areas, and when
/// nothing reaches the floor the screen says so and why, instead of drawing an empty map that reads as
/// a quiet city. Levels are relative to the busiest area shown, and the legend says so: a lone quiet
/// area is still the high one.
///
/// **Honest empty states, not one.** A shop with no pin, or no placed area near its pin, has no
/// neighbourhood yet: the platform does not know what "around" means for it. A neighbourhood too quiet
/// to show is a different thing to tell a merchant, and it gets its own words. So does a shop that is
/// not live: its neighbourhood is not served at all, and the 404 that brings is said as "not live
/// yet" rather than offered as a retry that cannot work.
///
/// **What the frame's "Trending Searches Near You" became.** That section used to be left out
/// entirely: nothing on the platform recorded what customers searched for, so every figure in it
/// would have been invented. Customer item search now records each search against a neighbourhood —
/// never an account, a session or a pin — so the section is drawn, as **what your neighbours could
/// not find**: words searched for near this shop that came back with nothing, or only with shops
/// more than a couple of kilometres away. Which is the more useful half anyway. A merchant does not
/// need to be told what is selling; they need to be told what people wanted and nobody had.
///
/// It answers the way the density half does. A word appears only once at least
/// [UnmetDemand.minimumSearches] different searches asked for it in a week — one person's shopping
/// list is not a market signal, and the floor is what keeps this from being surveillance — and the
/// number beside it is rounded ("about 10"), never the count. Weekly, because the floor needs a week
/// to be reached honestly; this week and last, so a merchant can see a word arrive.
///
/// Words the shop already sells are marked rather than hidden: "you stock this and your neighbours
/// still could not find it" usually means out of stock, paused, or named something nobody types.
///
/// Fetched on a real refresh rather than on the minute poll. The weekly numbers move once a day at
/// most, and the section keeps its own last good answer, so a failed search read never blanks the
/// map above it and a failed density read never blanks the words.
///
/// **The map.** flutter_map over the platform's one tile setting ([mapTileUrlTemplate]) — the
/// dependency the merchant package already has for the shop pin, so nothing new is pulled in. Tiles
/// that will not load fall back to the styled slot the pin map uses, and the list below still names
/// every area; another window or a pull to refresh gives the tiles another try. An area arriving
/// without a centre is listed, and said to be off the map, but never drawn — the server counts only
/// placed areas, so that is a fallback rather than a state the screen expects.
///
/// **Live, for the last hour.** A silent refresh every minute, like the dashboard. The LIVE badge, the
/// "real-time" subtitle and "Live Syncing" belong to the hour window alone, and only while the last
/// refresh held; a failed one keeps the last good answer on screen and says it could not refresh,
/// rather than blanking the map. The server moves the 24-hour picture on once an hour and the 7-day
/// one once a day, and those windows say exactly that.
///
/// **Only while it can be seen.** The minute refresh stops while another route covers the radar or the
/// app is hidden — a phone in the background, a browser tab behind others — and coming back refreshes
/// at once. A window that has merely lost focus keeps refreshing: it is still on screen with LIVE on
/// it, and a live badge over a frozen map would be worse than the request it saves.
///
/// **Time windows.** The last hour (the frame's "real-time"), 24 hours or 7 days. The frame has no
/// control for this; without one a quiet evening or a small neighbourhood would show nothing most of
/// the day. The server answers these three and refuses any other.
class DemandRadarScreen extends StatefulWidget {
  const DemandRadarScreen({
    super.key,
    required this.api,
    required this.storeId,
    this.onBack,
    this.pollInterval = const Duration(seconds: 60),
  });

  final DemandApi api;

  /// The shop to look around. Null — a merchant with no shop yet — says so instead of asking.
  final String? storeId;

  /// Drawn as the header's back button when the host has somewhere to go back to.
  final VoidCallback? onBack;

  /// How often the answer is silently refreshed while the radar can be seen.
  final Duration pollInterval;

  @override
  State<DemandRadarScreen> createState() => _DemandRadarScreenState();
}

class _DemandRadarScreenState extends State<DemandRadarScreen> with WidgetsBindingObserver {
  static const List<int> _windows = <int>[
    DemandApi.lastHour,
    DemandApi.lastDay,
    DemandApi.lastWeek,
  ];

  int _window = DemandApi.lastHour;

  /// The last good answer, for [_window].
  DemandDensity? _density;

  /// The last good answer about what the neighbourhood could not find. Independent of [_window],
  /// which is why it survives a window change and is not cleared with [_density].
  UnmetDemand? _unmet;

  /// True when the most recent read of the unmet words failed. The last good answer stays.
  bool _unmetFailed = false;

  /// Whether the unmet words are being read for the first time.
  bool _unmetLoading = false;

  /// Which week the words section is showing. False is the week that just finished.
  bool _unmetThisWeek = true;

  bool _loading = false;

  /// True when the most recent request failed. The last good answer stays; the LIVE badge goes.
  bool _refreshFailed = false;

  /// True when the answer was a 404: the shop is not live, so it has no neighbourhood to show.
  bool _notLive = false;

  /// Bumped by every request, so an answer for a window the merchant has since left is dropped.
  int _generation = 0;

  /// The same, for the unmet words, which belong to no window.
  int _unmetGeneration = 0;

  Timer? _poll;

  /// Whether the app is on screen: resumed, or inactive (visible without focus). Not hidden, paused
  /// or detached.
  bool _appOnScreen = true;

  /// Whether no other route covers the radar's.
  bool _routeOnTop = true;

  /// Set when the refresh was stopped for being unseen, so coming back asks at once instead of
  /// leaving an old answer up for another minute.
  bool _stale = false;

  late final MapTileWatch _tiles = MapTileWatch(onGiveUp: _tilesGaveUp);
  bool _tilesFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.storeId == null) return;
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    _appOnScreen = lifecycle == null || _isOnScreen(lifecycle);
    _loading = true;
    _load();
    unawaited(_loadUnmet());
    // The minute refresh starts in didChangeDependencies, which runs next: the first moment the
    // route can be asked whether it is on top.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depends on isCurrent alone, so this runs again exactly when another route covers the radar or
    // uncovers it. A host with no route around the screen answers null, as good as on top.
    _routeOnTop = ModalRoute.isCurrentOf(context) ?? true;
    _syncRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appOnScreen = _isOnScreen(state);
    _syncRefresh();
  }

  static bool _isOnScreen(AppLifecycleState state) =>
      state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

  /// Runs the minute refresh while the radar can be seen, and stops it while it cannot.
  void _syncRefresh() {
    if (widget.storeId == null) return;
    if (!_appOnScreen || !_routeOnTop) {
      _poll?.cancel();
      _poll = null;
      _stale = true;
      return;
    }
    if (_poll != null) return;
    _poll = Timer.periodic(widget.pollInterval, (_) => _load(silent: true));
    if (_stale) {
      _stale = false;
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _tiles.dispose();
    super.dispose();
  }

  void _tilesGaveUp() {
    if (mounted) setState(() => _tilesFailed = true);
  }

  /// Reads what the neighbourhood could not find.
  ///
  /// Deliberately not part of the minute poll: the numbers are weekly and move once a day at most,
  /// and a screen left open would otherwise ask for them sixty times an hour. It keeps its own
  /// failure flag, so a search read that fails leaves the map and its areas exactly as they were.
  Future<void> _loadUnmet() async {
    final String? storeId = widget.storeId;
    if (storeId == null) return;
    // Its own counter, not the density's: the words do not belong to a window, so a merchant
    // switching from the hour to the week must not throw away the answer already on its way.
    final int generation = ++_unmetGeneration;
    if (_unmet == null && !_unmetLoading) {
      setState(() => _unmetLoading = true);
    }
    try {
      final UnmetDemand unmet = await widget.api.unmet(storeId: storeId);
      if (!mounted || generation != _unmetGeneration) return;
      setState(() {
        _unmet = unmet;
        _unmetLoading = false;
        _unmetFailed = false;
      });
    } catch (_) {
      if (!mounted || generation != _unmetGeneration) return;
      // Including the 404 a shop that is not live answers: _notLive already says that once, and
      // saying it twice on one screen reads as two faults.
      setState(() {
        _unmetLoading = false;
        _unmetFailed = true;
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    final String? storeId = widget.storeId;
    if (storeId == null) return;
    final int generation = ++_generation;
    final int window = _window;
    if (!silent && _density == null && !_loading) {
      setState(() => _loading = true);
    }
    try {
      final DemandDensity density =
          await widget.api.density(storeId: storeId, windowMinutes: window);
      if (!mounted || generation != _generation) return;
      setState(() {
        _density = density;
        _loading = false;
        _refreshFailed = false;
        _notLive = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      // A 404 is not a failure worth retrying: the neighbourhood of a shop that is not live is not
      // served at all. Anything else keeps the last good answer and says the refresh failed.
      final bool notLive = error is DioException && error.response?.statusCode == 404;
      setState(() {
        _loading = false;
        _notLive = notLive;
        _refreshFailed = !notLive;
        if (notLive) _density = null;
      });
    }
  }

  /// A refresh somebody asked for: a pull, or Try again. It gives failed tiles another try too, which
  /// the minute refresh does not — a map whose tiles are blocked would otherwise flash back and give
  /// up again every minute.
  Future<void> _refresh() {
    if (_tilesFailed) setState(() => _tilesFailed = false);
    // The words too: a refresh somebody asked for is the one moment they are worth re-reading,
    // and the one moment a merchant whose last read failed can retry it.
    unawaited(_loadUnmet());
    return _load();
  }

  void _choose(int window) {
    if (window == _window) return;
    setState(() {
      _window = window;
      // The last answer described another window; showing it under this chip would be wrong.
      _density = null;
      _refreshFailed = false;
      _loading = true;
      // A fresh look: tiles that failed a moment ago may load now.
      _tilesFailed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DemandDensity? density = _density;

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          _RadarHeader(
            title: t.heatmapTitle,
            subtitle: switch (_window) {
              DemandApi.lastDay => t.heatmapSubtitleDay,
              DemandApi.lastWeek => t.heatmapSubtitleWeek,
              _ => t.heatmapSubtitle,
            },
            // LIVE belongs to the hour window, and only while the last refresh held.
            liveLabel: _window == DemandApi.lastHour && density != null && !_refreshFailed
                ? t.carrBadgeLive
                : null,
            region: density?.region,
            onBack: widget.onBack,
            backLabel: t.back,
          ),
          Expanded(child: _body(t, density)),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t, DemandDensity? density) {
    if (widget.storeId == null) {
      return YdEmptyState(
        icon: Icons.storefront_outlined,
        title: t.noShopYet,
        message: t.heatmapNoShopMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: DeliveryColors.brand,
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsetsDirectional.fromSTEB(
              DeliverySpacing.md,
              DeliverySpacing.md,
              DeliverySpacing.md,
              DeliverySpacing.lg,
            ),
            children: <Widget>[
              if (_notLive)
                // No window chips: there is no window in which a shop that is not live has demand.
                YdEmptyState(
                  icon: Icons.storefront_outlined,
                  title: t.heatmapNotLiveTitle,
                  message: t.heatmapNotLiveMessage,
                )
              else ...<Widget>[
                _windowChips(t),
                const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                if (density != null) ...<Widget>[
                  _mapCard(t, density),
                  if (density.zones.isNotEmpty) ...<Widget>[
                    const SizedBox(height: DeliverySpacing.lg),
                    YdSectionHeader(title: t.heatmapAreasTitle, fontSize: 15),
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    for (final DemandZone zone in density.zones)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: DeliverySpacing.md - DeliverySpacing.xs,
                        ),
                        child: _AreaRow(zone: zone, strings: t),
                      ),
                  ],
                  // Under the areas rather than above them: the map and its list are what the radar
                  // has always been, and the words are read after a merchant has seen where their
                  // neighbourhood is.
                  ..._unmetSection(t),
                ] else if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xxl),
                    child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
                  )
                else
                  YdEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: t.heatmapCouldNotLoad,
                    action: YdPillButton.secondary(
                      label: t.tryAgain,
                      onPressed: _refresh,
                      size: YdPillButtonSize.compact,
                      expand: false,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "What your neighbours could not find" — the frame's Trending Searches slot, answered honestly.
  ///
  /// Drawn only for a shop whose neighbourhood the platform knows: with no placed area near the pin
  /// there is nothing this could be about, and the map card above has already said so in its own
  /// words. Everything else has a state of its own, because they mean different things — still
  /// loading, could not be read, and a genuinely quiet week under the floor.
  List<Widget> _unmetSection(DeliveryStrings t) {
    final UnmetDemand? unmet = _unmet;
    if (unmet != null && !unmet.hasNeighbourhood) return const <Widget>[];
    if (unmet == null && !_unmetLoading && !_unmetFailed) return const <Widget>[];

    final UnmetWeek? week =
        unmet == null ? null : (_unmetThisWeek ? unmet.thisWeek : unmet.lastWeek);

    return <Widget>[
      const SizedBox(height: DeliverySpacing.lg),
      YdSectionHeader(title: t.heatmapUnmetTitle, fontSize: 15),
      const SizedBox(height: DeliverySpacing.xs),
      Text(
        t.heatmapUnmetBlurb,
        style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
      ),
      const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
      if (unmet != null) ...<Widget>[
        Wrap(
          spacing: DeliverySpacing.sm,
          runSpacing: DeliverySpacing.sm,
          children: <Widget>[
            YdChip(
              label: t.heatmapUnmetThisWeek,
              selected: _unmetThisWeek,
              onTap: () => setState(() => _unmetThisWeek = true),
            ),
            YdChip(
              label: t.heatmapUnmetLastWeek,
              selected: !_unmetThisWeek,
              onTap: () => setState(() => _unmetThisWeek = false),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
      ],
      if (unmet == null && _unmetLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
          child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
        )
      else if (unmet == null)
        YdEmptyState(
          icon: Icons.cloud_off_rounded,
          title: t.heatmapUnmetCouldNotLoad,
          action: YdPillButton.secondary(
            label: t.tryAgain,
            onPressed: _loadUnmet,
            size: YdPillButtonSize.compact,
            expand: false,
          ),
        )
      else if (week == null || week.isEmpty)
        YdCard.bordered(
          padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
          radius: DeliveryRadius.md,
          child: _CardNotice(
            icon: Icons.search_off_rounded,
            title: t.heatmapUnmetQuietTitle,
            message: t.heatmapUnmetQuietMessage(unmet.minimumSearches),
          ),
        )
      else ...<Widget>[
        for (final UnmetTerm term in week.terms)
          Padding(
            padding: const EdgeInsets.only(bottom: DeliverySpacing.md - DeliverySpacing.xs),
            child: _UnmetRow(term: term, farMetres: unmet.farMetres, strings: t),
          ),
        Text(
          t.heatmapUnmetPrivacy,
          style: const TextStyle(fontSize: 12, color: DeliveryColors.faint, height: 1.4),
        ),
      ],
    ];
  }

  Widget _windowChips(DeliveryStrings t) {
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        for (final int window in _windows)
          YdChip(
            label: switch (window) {
              DemandApi.lastDay => t.heatmapWindowDay,
              DemandApi.lastWeek => t.heatmapWindowWeek,
              _ => t.heatmapWindowHour,
            },
            selected: window == _window,
            onTap: () => _choose(window),
          ),
      ],
    );
  }

  Widget _mapCard(DeliveryStrings t, DemandDensity density) {
    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  t.heatmapActiveOrderDensities,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Flexible(
                child: Text(
                  _refreshFailed
                      ? t.heatmapCantRefresh
                      // How often this window's picture actually moves: live for the hour, and
                      // no livelier than the server's own boundaries for the day and the week.
                      : switch (_window) {
                          DemandApi.lastDay => t.heatmapUpdatedHourly,
                          DemandApi.lastWeek => t.heatmapUpdatedDaily,
                          _ => t.heatmapLiveSyncing,
                        },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _refreshFailed ? DeliveryAccent.caution.onTint : DeliveryColors.brand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _mapArea(t, density),
          if (density.zones.isNotEmpty) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm + 2),
            _Legend(strings: t),
          ],
        ],
      ),
    );
  }

  Widget _mapArea(DeliveryStrings t, DemandDensity density) {
    if (!density.hasNeighbourhood) {
      return _CardNotice(
        icon: Icons.travel_explore,
        title: t.heatmapNoAreaTitle,
        message: t.heatmapNoAreaMessage,
      );
    }
    if (density.zones.isEmpty) {
      return _CardNotice(
        icon: Icons.groups_outlined,
        title: t.heatmapNotEnoughTitle,
        message: t.heatmapNotEnoughMessage(density.minimumCustomers),
      );
    }

    final List<DemandZone> placed = density.placed;
    final Widget map;
    if (placed.isEmpty) {
      map = MapSlotPlaceholder(label: t.heatmapNoneOnMap);
    } else if (_tilesFailed) {
      map = MapSlotPlaceholder(label: t.heatmapMapUnavailable);
    } else {
      map = _DensityMap(zones: placed, tiles: _tiles, strings: t);
    }
    return SizedBox(
      height: _mapHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: map,
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------- levels

Color _levelColor(DemandLevel level) => switch (level) {
      DemandLevel.high => DeliveryColors.brand,
      DemandLevel.medium => DeliveryAccent.caution.color,
      DemandLevel.low => DeliveryAccent.positive.color,
      DemandLevel.unknown => DeliveryColors.faint,
    };

Color _levelTint(DemandLevel level) => switch (level) {
      DemandLevel.high => DeliveryColors.brandSoft,
      DemandLevel.medium => DeliveryAccent.caution.tint,
      DemandLevel.low => DeliveryAccent.positive.tint,
      DemandLevel.unknown => DeliveryColors.background,
    };

Color _levelInk(DemandLevel level) => switch (level) {
      DemandLevel.high => DeliveryColors.brand,
      DemandLevel.medium => DeliveryAccent.caution.onTint,
      DemandLevel.low => DeliveryAccent.positive.onTint,
      DemandLevel.unknown => DeliveryColors.muted,
    };

/// Null for a level this build does not know: an area is then named without one, never guessed.
String? _levelLabel(DeliveryStrings t, DemandLevel level) => switch (level) {
      DemandLevel.high => t.heatmapLevelHigh,
      DemandLevel.medium => t.heatmapLevelMedium,
      DemandLevel.low => t.heatmapLevelLow,
      DemandLevel.unknown => null,
    };

/// The circle's radius on the ground. Sized by level, as the frame draws it; it is a picture of
/// "busier here", not a boundary, which a delivery area does not have.
double _haloMetres(DemandLevel level) => switch (level) {
      DemandLevel.high => 650,
      DemandLevel.medium => 520,
      _ => 400,
    };

// ---------------------------------------------------------------------------------------- pieces

/// The frame's header: back, the title with its LIVE badge, the subtitle, and the city pill.
///
/// Not [YdScreenHeader], which centres a plain title: the frame puts a badge beside a start-aligned
/// title and a region pill at the end. Same height token, same top inset handling.
class _RadarHeader extends StatelessWidget {
  const _RadarHeader({
    required this.title,
    required this.subtitle,
    this.liveLabel,
    this.region,
    this.onBack,
    this.backLabel,
  });

  final String title;
  final String subtitle;

  /// Null hides the badge — nothing is live until an answer has arrived and the last refresh held,
  /// and nothing but the hour window is live at all.
  final String? liveLabel;

  /// The region most of the shop's areas name. Data from the server, never a translated string.
  final String? region;

  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final double topInset = MediaQuery.paddingOf(context).top;

    return Container(
      constraints: BoxConstraints(minHeight: YdScreenHeader.height + topInset),
      padding: EdgeInsetsDirectional.only(
        top: topInset,
        start: DeliverySpacing.md,
        end: DeliverySpacing.md,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          if (onBack != null) ...<Widget>[
            YdBackButton(onPressed: onBack!, semanticLabel: backLabel),
            const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          ],
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.ink,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (liveLabel != null) ...<Widget>[
                        const SizedBox(width: DeliverySpacing.sm),
                        _LiveBadge(label: liveLabel!),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeliveryColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (region != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: DeliverySpacing.sm,
                  vertical: DeliverySpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: DeliveryColors.brandSoft,
                  borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                ),
                child: Text(
                  region!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DeliveryColors.brand,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The green "LIVE" pill with its dot.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DeliveryAccent.positive.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: DeliveryAccent.positive.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DeliverySpacing.xs),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: DeliveryAccent.positive.onTint,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The map itself: a translucent circle per placed area, a solid core on the busiest, and a label.
class _DensityMap extends StatefulWidget {
  const _DensityMap({required this.zones, required this.tiles, required this.strings});

  /// Placed areas only; the caller has already set the others aside.
  final List<DemandZone> zones;

  final MapTileWatch tiles;
  final DeliveryStrings strings;

  @override
  State<_DensityMap> createState() => _DensityMapState();
}

class _DensityMapState extends State<_DensityMap> {
  /// Moves the camera when the areas change under a map that is already showing — a refresh that
  /// brings a new area over the floor, or another window. [MapOptions] read the camera once, so
  /// without this a new area could land outside the view and simply never be seen.
  final MapController _camera = MapController();

  @override
  void initState() {
    super.initState();
    // The deadline starts when a map is actually on screen, not when the page opens — and again
    // for each map built after tiles failed, which is what gives a retry its fresh attempt.
    widget.tiles.start();
  }

  @override
  void didUpdateWidget(_DensityMap old) {
    super.didUpdateWidget(old);
    if (_places(old.zones).containsAll(_places(widget.zones)) &&
        _places(widget.zones).containsAll(_places(old.zones))) {
      // Same areas in the same spots: a level changed, or nothing did. Leave the camera where the
      // merchant put it.
      return;
    }
    // After this frame: the camera belongs to the map, which is mid-build right now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final List<LatLng> points = _points(widget.zones);
      if (points.length > 1) {
        _camera.fitCamera(_fit(points));
      } else {
        _camera.move(points.first, _areaZoom);
      }
    });
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  static Set<String> _places(List<DemandZone> zones) => <String>{
        for (final DemandZone zone in zones) '${zone.zoneId}@${zone.centerLat},${zone.centerLng}',
      };

  static List<LatLng> _points(List<DemandZone> zones) => <LatLng>[
        for (final DemandZone zone in zones) LatLng(zone.centerLat!, zone.centerLng!),
      ];

  static CameraFit _fit(List<LatLng> points) => CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.all(40),
        maxZoom: _areaZoom,
      );

  @override
  Widget build(BuildContext context) {
    final List<LatLng> points = _points(widget.zones);

    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _camera,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: _areaZoom,
            initialCameraFit: points.length > 1 ? _fit(points) : null,
            backgroundColor: DeliveryColors.background,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: <Widget>[
            osmTiles(widget.tiles),
            CircleLayer(
              circles: <CircleMarker>[
                for (final DemandZone zone in widget.zones)
                  CircleMarker(
                    point: LatLng(zone.centerLat!, zone.centerLng!),
                    radius: _haloMetres(zone.level),
                    useRadiusInMeter: true,
                    color: _levelColor(zone.level).withValues(alpha: 0.32),
                    borderColor: _levelColor(zone.level).withValues(alpha: 0.6),
                    borderStrokeWidth: 1,
                  ),
                for (final DemandZone zone in widget.zones)
                  if (zone.level == DemandLevel.high)
                    CircleMarker(
                      point: LatLng(zone.centerLat!, zone.centerLng!),
                      radius: 7,
                      color: _levelColor(zone.level),
                    ),
              ],
            ),
            MarkerLayer(
              markers: <Marker>[
                for (final DemandZone zone in widget.zones)
                  Marker(
                    point: LatLng(zone.centerLat!, zone.centerLng!),
                    width: 160,
                    // Twice the label's height, so the label sits below the centre and clear of
                    // the core rather than on top of it.
                    height: 56,
                    child: _MapLabel(
                      text: switch (_levelLabel(widget.strings, zone.level)) {
                        final String level => widget.strings.heatmapZoneWithLevel(zone.name, level),
                        null => zone.name,
                      },
                      level: zone.level,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const PositionedDirectional(
          end: 4,
          bottom: 4,
          child: OsmAttributionLabel(compact: true),
        ),
      ],
    );
  }
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.text, required this.level});

  final String text;
  final DemandLevel level;

  @override
  Widget build(BuildContext context) {
    final bool strong = level == DemandLevel.high;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: strong ? DeliveryColors.brand : DeliveryColors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(DeliveryRadius.sm),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: strong ? DeliveryColors.white : DeliveryColors.ink,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// What the circle colours mean, and what they are measured against.
///
/// The scale is said because it is relative: High is the busiest area shown, whatever that is. A
/// lone area five customers deep over a week reads High, and without this line a merchant would read
/// that as a busy street rather than the busiest of a quiet few.
class _Legend extends StatelessWidget {
  const _Legend({required this.strings});

  final DeliveryStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: DeliverySpacing.md,
          runSpacing: DeliverySpacing.xs,
          children: <Widget>[
            for (final DemandLevel level in <DemandLevel>[
              DemandLevel.high,
              DemandLevel.medium,
              DemandLevel.low,
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _levelColor(level), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: DeliverySpacing.xs + 2),
                  Text(
                    _levelLabel(strings, level)!,
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          strings.heatmapLegendRelative,
          style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.3),
        ),
      ],
    );
  }
}

/// A calm explanation inside the map card, in place of a map that would say nothing.
class _CardNotice extends StatelessWidget {
  const _CardNotice({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: DeliverySpacing.lg,
        horizontal: DeliverySpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 32, color: DeliveryColors.faint),
          const SizedBox(height: DeliverySpacing.sm + 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeliveryColors.ink,
            ),
          ),
          const SizedBox(height: DeliverySpacing.xs + 2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// One area in the list under the map: its name, its region, whether it is drawn, and its level.
class _AreaRow extends StatelessWidget {
  const _AreaRow({required this.zone, required this.strings});

  final DemandZone zone;
  final DeliveryStrings strings;

  @override
  Widget build(BuildContext context) {
    final String? level = _levelLabel(strings, zone.level);
    final String caption = <String>[
      if (zone.region != null && zone.region!.trim().isNotEmpty) zone.region!.trim(),
      if (!zone.isPlaced) strings.heatmapNotOnMap,
    ].join(' · ');

    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      radius: DeliveryRadius.md,
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _levelTint(zone.level),
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Icon(Icons.place_rounded, size: 20, color: _levelColor(zone.level)),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  zone.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
                if (caption.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                  ),
                ],
              ],
            ),
          ),
          if (level != null) ...<Widget>[
            const SizedBox(width: DeliverySpacing.sm),
            YdBadge(
              label: level,
              color: _levelInk(zone.level),
              background: _levelTint(zone.level),
              uppercase: false,
              fontSize: 12,
            ),
          ],
        ],
      ),
    );
  }
}

/// One word the neighbourhood looked for and did not find: the word, where it was asked, why it
/// counts as unmet, and roughly how many searches asked for it.
///
/// The word is shown as it was searched for — folded, lower case, whatever the customer typed. Not
/// prettified: a merchant deciding what to stock is better served by the spelling people actually
/// use than by one the platform invented for them.
class _UnmetRow extends StatelessWidget {
  const _UnmetRow({required this.term, required this.farMetres, required this.strings});

  final UnmetTerm term;
  final int farMetres;
  final DeliveryStrings strings;

  @override
  Widget build(BuildContext context) {
    final String? why = switch (term.kind) {
      UnmetKind.none => strings.heatmapUnmetNothingNearby,
      UnmetKind.far => strings.heatmapUnmetOnlyFar(_km(farMetres)),
      UnmetKind.unknown => null,
    };
    final String caption = <String>[
      if (term.areaName != null) term.areaName!,
      strings.heatmapUnmetAbout(term.about),
      if (why != null) why,
      // In the caption rather than in a badge beside the word. A badge would be easier to scan, and
      // in Arabic on a 320px phone "أنت تبيع هذا أصلاً" beside a five-word product name overflows the
      // row — so the green tile carries the mark and the words go where they can wrap.
      if (term.alreadySold) strings.heatmapUnmetYouSell,
    ].join(' · ');

    return YdCard.bordered(
      padding: const EdgeInsets.all(DeliverySpacing.md - DeliverySpacing.xs),
      radius: DeliveryRadius.md,
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: term.alreadySold ? DeliveryAccent.positive.tint : DeliveryColors.brandSoft,
              borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            ),
            child: Icon(
              term.alreadySold ? Icons.inventory_2_outlined : Icons.search_rounded,
              size: 20,
              color: term.alreadySold ? DeliveryAccent.positive.color : DeliveryColors.brand,
            ),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  term.term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Metres as a reader says them: "2" rather than "2.0", and "1.5" where it matters.
  static String _km(int metres) {
    final double km = metres / 1000;
    return km == km.roundToDouble() ? km.round().toString() : km.toStringAsFixed(1);
  }
}

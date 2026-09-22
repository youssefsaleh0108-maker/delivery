import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'order_detail_screen.dart' show MerchantMetricCard, MerchantTileGrid, merchantMaxContentWidth;

/// Menu Insights (Figma 139:255): what a shop's menu has been doing.
///
/// The frame asked for six figures. This screen draws four of them and says, in place of the other
/// two, why they are not there — which is the part worth explaining, because a screen that quietly
/// dropped them would read as a screen that was still being built.
///
/// **Menu opens** and **opened from a table code** are bands over a floor, never counts: Product
/// Service rounds down and publishes nothing under [MenuInsights.minimumOpens], so every figure
/// here is drawn with "about" in front of it and an under-the-floor window says *too few to report*
/// rather than drawing a zero. The note under them is not a disclaimer to be trimmed later: this
/// counts requests the service answered, so a reader whose browser or network still had the page
/// is genuinely not in it, and a merchant deciding anything from the number needs to know that.
///
/// **When your menu is read** is four parts of the day. The frame drew hourly bars; the platform
/// will not answer hourly, because "one open at seven on Tuesday" is a sentence about a person and
/// the quiet shops it would be truest for are most shops.
///
/// **What sold** replaces the frame's *most viewed items*. There is no per-item view count and
/// there honestly cannot be one — the public page is a single document holding the whole menu, so
/// every item on it is read exactly as often as every other, and producing that rail would have
/// meant tracking each item's interactions to answer a question delivered baskets answer better.
/// These figures are exact, unlike the opens above them, because they are the shop's own receipts.
///
/// The frame's *QR scans* tile is gone for a different reason again: the shop's counter code
/// encodes the page's plain address, so a scan of it and a tapped link reach the server
/// identically. The table-code figure beside it is the honest half of that question.
///
/// What the neighbourhood searched for is not rebuilt here — that is the Demand Radar, and this
/// screen offers a door to it rather than a second copy of its numbers.
class MenuInsightsScreen extends StatefulWidget {
  const MenuInsightsScreen({
    super.key,
    required this.api,
    this.storeId,
    this.onBack,
    this.onDemandRadar,
  });

  final MenuInsightsApi api;

  /// The shop being looked at. Named rather than implied, because an account can own several.
  ///
  /// Null when the account has no shop yet — the portal resolves it from "shops you own" and hands
  /// null when there are none, exactly as it does for the menu builder. That draws the same empty
  /// state rather than a failed request.
  final String? storeId;

  final VoidCallback? onBack;

  /// The way to the Demand Radar, when the host has one. Null draws no row — a door that goes
  /// nowhere is worse than no door.
  final VoidCallback? onDemandRadar;

  @override
  State<MenuInsightsScreen> createState() => _MenuInsightsScreenState();
}

class _MenuInsightsScreenState extends State<MenuInsightsScreen> {
  /// The windows offered, in the order the frame draws them.
  static const List<int> _windows = <int>[
    MenuInsightsApi.today,
    MenuInsightsApi.lastWeek,
    MenuInsightsApi.lastMonth,
  ];

  int _days = MenuInsightsApi.lastWeek;
  MenuInsights? _insights;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? storeId = widget.storeId;
    if (storeId == null) {
      setState(() {
        _loading = false;
        _error = null;
        _insights = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final MenuInsights insights =
          await widget.api.forStore(storeId: storeId, days: _days);
      if (!mounted) return;
      setState(() {
        _insights = insights;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _chooseWindow(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  /// Surfaces the server's own explanation, the way every other merchant screen does.
  static String _serverMessage(Object error) {
    final RegExpMatch? detail =
        RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(error.toString());
    return detail?.group(1) ?? error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: Column(
        children: <Widget>[
          YdScreenHeader(
            title: t.merchMenuInsightsTitle,
            onBack: widget.onBack,
            backSemanticLabel: t.back,
          ),
          Expanded(child: _body(t)),
        ],
      ),
    );
  }

  Widget _body(DeliveryStrings t) {
    if (widget.storeId == null) {
      return YdEmptyState(icon: Icons.storefront_outlined, title: t.noShopYet);
    }
    final Object? error = _error;
    if (error != null) {
      return YdEmptyState(
        icon: Icons.cloud_off_rounded,
        title: t.merchMenuInsightsFailed,
        message: _serverMessage(error),
        action: YdPillButton.secondary(
          label: t.tryAgain,
          onPressed: _load,
          size: YdPillButtonSize.compact,
          expand: false,
        ),
      );
    }

    final MenuInsights? insights = _insights;
    return RefreshIndicator(
      onRefresh: _load,
      color: DeliveryColors.brand,
      child: Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              DeliverySpacing.lg,
              DeliverySpacing.lg - DeliverySpacing.xs,
              DeliverySpacing.lg,
              DeliverySpacing.lg + MediaQuery.paddingOf(context).bottom,
            ),
            children: <Widget>[
              // Drawn while loading too, so the window a merchant just picked stays lit rather
              // than vanishing under a spinner.
              _windowPicker(t),
              const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
              if (_loading || insights == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: DeliverySpacing.xl),
                  child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
                )
              else ...<Widget>[
                _opens(insights, t),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _whenRead(insights, t),
                const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                _bestSellers(insights, t),
                if (widget.onDemandRadar != null) ...<Widget>[
                  const SizedBox(height: DeliverySpacing.lg - DeliverySpacing.xs),
                  _demandRadarDoor(t),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- the window

  /// A Wrap rather than a Row: three chips of Arabic at 320 dp are wider than the column, and a
  /// picker that overflowed would hide the window a merchant is trying to choose.
  Widget _windowPicker(DeliveryStrings t) {
    return Wrap(
      spacing: DeliverySpacing.sm,
      runSpacing: DeliverySpacing.sm,
      children: <Widget>[
        for (final int days in _windows)
          YdChip(
            label: _windowLabel(days, t),
            selected: days == _days,
            onTap: () => _chooseWindow(days),
          ),
      ],
    );
  }

  String _windowLabel(int days, DeliveryStrings t) => switch (days) {
        MenuInsightsApi.today => t.merchMenuInsightsWindowToday,
        MenuInsightsApi.lastMonth => t.merchMenuInsightsWindowMonth,
        _ => t.merchMenuInsightsWindowWeek,
      };

  // ------------------------------------------------------------------ the opens

  /// How a banded figure is said out loud in the space a figure gets.
  ///
  /// The under-the-floor case is deliberately not a zero — "too few to report" and "nobody" are
  /// different facts, and the server only ever claimed the first. Short here because a tile's
  /// value and a bar's end label have room for two words; the sentence that names the floor is
  /// drawn beside it by [_floorNote].
  String _figure(MenuOpens opens, DeliveryStrings t) =>
      opens.enough ? t.merchMenuOpensAbout(opens.about) : t.merchMenuOpensTooFewShort;

  /// The full sentence, with the floor in it, for the footnote under a suppressed figure.
  String? _floorNote(MenuOpens opens, int minimum, DeliveryStrings t) =>
      opens.enough ? null : t.merchMenuOpensTooFew(minimum);

  Widget _opens(MenuInsights insights, DeliveryStrings t) {
    final bool nothingAtAll = insights.countingSince == null && !insights.opens.enough;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        YdSectionHeader(title: t.merchMenuOpensTitle),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        if (nothingAtAll)
          _note(t.merchMenuOpensNothingYet, icon: Icons.hourglass_empty_rounded)
        else ...<Widget>[
          MerchantTileGrid(tiles: <Widget>[
            MerchantMetricCard.brand(
              icon: Icons.menu_book_outlined,
              label: t.merchMenuOpensTitle,
              value: _figure(insights.opens, t),
              footnote: _floorNote(insights.opens, insights.minimumOpens, t),
            ),
            MerchantMetricCard.accent(
              icon: Icons.table_restaurant_outlined,
              label: t.merchMenuFromTablesTitle,
              // A shop with no table codes has a true zero here, which is a different sentence
              // from "too few to report" and reads better as its own words.
              value: insights.fromTableCodes.enough
                  ? t.merchMenuOpensAbout(insights.fromTableCodes.about)
                  : t.merchMenuFromTablesNone,
              accent: DeliveryAccent.info,
            ),
          ]),
          const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
          _note(t.merchMenuOpensWhatItCounts, icon: Icons.info_outline_rounded),
          const SizedBox(height: DeliverySpacing.sm),
          _note(t.merchMenuNoScanCount, icon: Icons.qr_code_2_outlined),
          if (insights.countingSince case final DateTime since) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            _note(t.merchMenuOpensCountingSince(_shortDate(since)),
                icon: Icons.event_available_outlined),
          ],
        ],
      ],
    );
  }

  // -------------------------------------------------------------- when it is read

  Widget _whenRead(MenuInsights insights, DeliveryStrings t) {
    final List<MenuDayPartOpens> parts = insights.shape
        .where((MenuDayPartOpens p) => p.part != MenuDayPart.unknown)
        .toList();
    final bool anything = parts.any((MenuDayPartOpens p) => p.opens.enough);
    final int tallest = parts.fold(
        0, (int best, MenuDayPartOpens p) => p.opens.about > best ? p.opens.about : best);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        YdSectionHeader(title: t.merchMenuWhenTitle),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        YdCard(
          child: anything
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final MenuDayPartOpens part in parts) ...<Widget>[
                      _dayPartRow(part, tallest, t),
                      if (part != parts.last)
                        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    ],
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    _quiet(t.merchMenuWhenWhyNotHours),
                  ],
                )
              : _quiet(t.merchMenuWhenTooQuiet),
        ),
      ],
    );
  }

  Widget _dayPartRow(MenuDayPartOpens part, int tallest, DeliveryStrings t) {
    // Proportion of the busiest part shown, never of a total: a bar that encoded a share would
    // let the other bars be worked back out of it.
    final double fill = tallest == 0 || !part.opens.enough
        ? 0
        : (part.opens.about / tallest).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text.rich(
                TextSpan(children: <InlineSpan>[
                  TextSpan(
                    text: _partName(part.part, t),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: DeliveryColors.ink,
                    ),
                  ),
                  TextSpan(
                    text: '  ${_partHours(part.part, t)}',
                    style: const TextStyle(fontSize: 11, color: DeliveryColors.faint),
                  ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            // Flexible, because "too few to report" in Arabic is most of a 320 dp row on its own.
            Flexible(
              child: Text(
                _figure(part.opens, t),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: part.opens.enough ? FontWeight.w700 : FontWeight.w500,
                  color: part.opens.enough ? DeliveryColors.ink : DeliveryColors.faint,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xs + 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: 6,
            backgroundColor: DeliveryColors.background,
            valueColor: const AlwaysStoppedAnimation<Color>(DeliveryColors.brand),
          ),
        ),
      ],
    );
  }

  String _partName(MenuDayPart part, DeliveryStrings t) => switch (part) {
        MenuDayPart.morning => t.merchMenuPartMorning,
        MenuDayPart.midday => t.merchMenuPartMidday,
        MenuDayPart.evening => t.merchMenuPartEvening,
        MenuDayPart.night => t.merchMenuPartNight,
        MenuDayPart.unknown => '',
      };

  /// The hours a part covers are named here rather than sent: the server keeps the boundaries and
  /// has deliberately not got a clock in its response to put them in.
  String _partHours(MenuDayPart part, DeliveryStrings t) => switch (part) {
        MenuDayPart.morning => t.merchMenuPartMorningHours,
        MenuDayPart.midday => t.merchMenuPartMiddayHours,
        MenuDayPart.evening => t.merchMenuPartEveningHours,
        MenuDayPart.night => t.merchMenuPartNightHours,
        MenuDayPart.unknown => '',
      };

  // ------------------------------------------------------------------ what sold

  Widget _bestSellers(MenuInsights insights, DeliveryStrings t) {
    final List<MenuBestSeller> items = insights.bestSellers;
    final int tallest = items.isEmpty
        ? 0
        : items.fold(0, (int best, MenuBestSeller i) => i.baskets > best ? i.baskets : best);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        YdSectionHeader(title: t.merchMenuBestSellersTitle),
        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
        YdCard(
          child: items.isEmpty
              ? _quiet(t.merchMenuBestSellersEmpty)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (int i = 0; i < items.length; i++) ...<Widget>[
                      _bestSellerRow(i + 1, items[i], tallest, t),
                      if (i != items.length - 1)
                        const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    ],
                    const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
                    _quiet(t.merchMenuBestSellersNote),
                  ],
                ),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        _note(t.merchMenuNoItemViews, icon: Icons.visibility_off_outlined),
      ],
    );
  }

  Widget _bestSellerRow(int rank, MenuBestSeller item, int tallest, DeliveryStrings t) {
    final double fill = tallest == 0 ? 0 : (item.baskets / tallest).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '$rank. ${item.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.ink,
                ),
              ),
            ),
            const SizedBox(width: DeliverySpacing.sm),
            Flexible(
              child: Text(
                // Exact, unlike everything above: a shop's own delivered orders are its own record.
                t.merchMenuBestSellerLine(item.baskets, item.units),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xs + 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fill,
            minHeight: 6,
            backgroundColor: DeliveryColors.background,
            valueColor: const AlwaysStoppedAnimation<Color>(DeliveryColors.brand),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- the radar door

  Widget _demandRadarDoor(DeliveryStrings t) {
    return YdCard(
      onTap: widget.onDemandRadar,
      child: Row(
        children: <Widget>[
          const Icon(Icons.travel_explore_outlined, size: 20, color: DeliveryColors.brand),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Text(
              t.merchMenuDemandRadarRow,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: DeliveryColors.ink,
              ),
            ),
          ),
          Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.chevron_left
                : Icons.chevron_right,
            size: 20,
            color: DeliveryColors.faint,
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- pieces

  /// A line of explanation that earns its place: every one of these says what a figure above it
  /// cannot tell a shop.
  Widget _note(String text, {required IconData icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 14, color: DeliveryColors.faint),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _quiet(String text) => Text(
        text,
        style: const TextStyle(fontSize: 11, color: DeliveryColors.muted, height: 1.4),
      );

  /// A date the merchant can read, in their own locale's order, with no time on it — there is no
  /// time in the data.
  String _shortDate(DateTime date) => MaterialLocalizations.of(context)
      .formatShortDate(date);
}

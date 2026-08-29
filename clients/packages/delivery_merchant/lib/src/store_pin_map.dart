import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// The shop's pin on a real map — the preview that sits in the shop-config frame's map slot, and
/// the picker behind it.
///
/// Both hosts mount this: the Android app and the Flutter Web portal. Nothing here touches
/// `dart:io`, and the tiles are plain raster PNGs, so the same widget renders in a browser.
///
/// Tiles come from OpenStreetMap's own servers, which is a courtesy rather than a contract — they
/// can and do refuse. Every map here therefore watches for a failed tile and falls back to the
/// styled slot this screen has always drawn, rather than leaving the grey lattice a failed
/// [TileLayer] paints. A merchant who cannot see a map should see the shop-config screen they had
/// before maps existed, not a broken one.

/// OpenStreetMap's standard raster style.
const String osmTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Identifies this app to the tile server, as OSM's usage policy requires.
const String osmUserAgentPackageName = 'shop.youdrop.app';

/// The attribution OpenStreetMap's licence requires on every view of its tiles.
///
/// Deliberately a plain always-visible label rather than the package's expandable attribution
/// button: the licence asks for a credit that is visible, and a credit folded behind an "i" that
/// nobody presses is not one.
const String osmAttribution = '© OpenStreetMap contributors';

/// Where the camera starts when nothing at all is known yet.
///
/// Not a pin and never saved as one — no marker is drawn until the merchant puts one down. It is
/// the platform's own city (`delivery.platform.zone` is `Asia/Beirut`), at a zoom wide enough that
/// a merchant anywhere in the country can see where they are before they start panning.
const LatLng _fallbackCamera = LatLng(33.8938, 35.5018);
const double _fallbackZoom = 11;

/// Close enough to read a street name — where the camera sits once there is a pin to look at.
const double _pinnedZoom = 16;

/// How long a map is given to put one tile on screen before it admits it cannot.
///
/// Generous, because a shop on a slow connection is the ordinary case and a placeholder that
/// flashes up while the tiles are still on their way is worse than a blank moment. Short enough
/// that a merchant is not left looking at nothing.
const Duration _tilePatience = Duration(seconds: 8);

/// Watches one map's tiles and decides when it should stop pretending.
///
/// Two failure shapes, not one. A refused tile is the obvious case; the quiet one is a request
/// that never comes back at all — a blocked host, a stalled cache — and that one raises no error
/// to catch. So the watch is a deadline as well as an error handler: unless something actually
/// arrives, the map gives up on its own.
class MapTileWatch {
  MapTileWatch({required this.onGiveUp, this.patience = _tilePatience});

  /// Called at most once per [start], never synchronously from a tile callback.
  final VoidCallback onGiveUp;

  final Duration patience;

  Timer? _deadline;
  bool _sawATile = false;
  bool _given = false;

  /// Begins (or restarts) the deadline for a freshly built map.
  void start() {
    _deadline?.cancel();
    _sawATile = false;
    _given = false;
    _deadline = Timer(patience, () {
      if (_sawATile) return;
      _fire();
    });
  }

  /// A tile the server refused. Only fatal while nothing has drawn: one missing square at the edge
  /// of a map that is otherwise fine is not a reason to throw the map away.
  void noteError() {
    if (_sawATile) return;
    _fire();
  }

  /// Every tile the layer builds, loaded or not. One that actually arrived proves the map works.
  void noteTile(TileImage tile) {
    if (_sawATile || tile.loadError || tile.loadFinishedAt == null) return;
    _sawATile = true;
    _deadline?.cancel();
  }

  void dispose() => _deadline?.cancel();

  void _fire() {
    if (_given) return;
    _given = true;
    _deadline?.cancel();
    // Tile callbacks land mid-frame; the swap happens on a clean one.
    scheduleMicrotask(onGiveUp);
  }
}

/// The tile layer every map in this package uses.
TileLayer osmTiles(MapTileWatch watch) => TileLayer(
      urlTemplate: osmTileUrlTemplate,
      userAgentPackageName: osmUserAgentPackageName,
      errorTileCallback: (TileImage _, Object __, StackTrace? ___) => watch.noteError(),
      tileBuilder: (BuildContext _, Widget tile, TileImage image) {
        watch.noteTile(image);
        return tile;
      },
      // A tile that failed is not kept on screen as a grey square; it leaves, and the caller has
      // already been told to draw the placeholder instead.
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
    );

/// The required credit, as a small legible chip in the corner of a map.
class OsmAttributionLabel extends StatelessWidget {
  const OsmAttributionLabel({super.key, this.compact = false});

  /// The 100px preview has less room than the picker; the label shrinks rather than wraps.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? 4 : DeliverySpacing.xs + 2,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: DeliveryColors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm - 2),
      ),
      child: Text(
        osmAttribution,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // Not localised on purpose: it is the licence's own credit line, and OpenStreetMap asks
        // for it by name.
        style: TextStyle(
          fontSize: compact ? 8 : 10,
          color: DeliveryColors.muted,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The pin itself: the same glyph the address card uses, sized to be seen on a photograph of a
/// city.
class ShopPinGlyph extends StatelessWidget {
  const ShopPinGlyph({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.place,
      size: size,
      color: DeliveryColors.brand,
      shadows: const <Shadow>[
        Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
      ],
    );
  }
}

/// The faint lattice the shop-config screen has always drawn where a map goes.
///
/// Kept exactly as it was, and now reached only when the tiles genuinely will not load — the state
/// it was always describing.
class MapSlotPlaceholder extends StatelessWidget {
  const MapSlotPlaceholder({super.key, required this.label, this.trailing});

  /// Already localised by the caller.
  final String label;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.place_outlined, size: 18, color: DeliveryColors.faint),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.faint,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: DeliverySpacing.sm),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The faint 16px lattice behind the map slot — enough to read as "a map goes here", not enough to
/// be mistaken for one.
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = DeliveryColors.border
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------- preview

/// The 100px map thumbnail in the shop-config frame's address section.
///
/// Shows where the shop is, and is the way in to changing it. Not interactive itself: a small map
/// inside a scrolling form that eats vertical drags is a map that stops the page scrolling, so the
/// thumbnail is a picture and the panning happens in the picker.
class StorePinPreview extends StatefulWidget {
  const StorePinPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onTap,
    this.height = 100,
  });

  /// Null when this shop has never been pinned; the slot says so instead of drawing a marker
  /// somewhere plausible.
  final double? latitude;
  final double? longitude;

  final VoidCallback? onTap;
  final double height;

  @override
  State<StorePinPreview> createState() => _StorePinPreviewState();
}

class _StorePinPreviewState extends State<StorePinPreview> {
  bool _tilesFailed = false;

  late final MapTileWatch _watch = MapTileWatch(onGiveUp: _giveUp);

  /// Rebuilt whenever the pin moves, because [FlutterMap] reads `initialCenter` once.
  Key _mapKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _watch.start();
  }

  @override
  void didUpdateWidget(StorePinPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude || oldWidget.longitude != widget.longitude) {
      _mapKey = UniqueKey();
      // A new pin deserves a fresh attempt at the tiles: the last failure may have been the
      // network rather than the server.
      _tilesFailed = false;
      _watch.start();
    }
  }

  @override
  void dispose() {
    _watch.dispose();
    super.dispose();
  }

  void _giveUp() {
    if (!mounted || _tilesFailed) return;
    setState(() => _tilesFailed = true);
  }

  bool get _hasPin => widget.latitude != null && widget.longitude != null;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String caption = _hasPin ? t.addressPinnedOnMap : t.merchPinNoneYet;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Semantics(
        button: widget.onTap != null,
        label: '${t.merchPinShopLocation} · $caption',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (_tilesFailed)
                MapSlotPlaceholder(label: t.merchMapUnavailable)
              else
                _map(),
              if (!_tilesFailed)
                PositionedDirectional(
                  bottom: 3,
                  end: 3,
                  child: const OsmAttributionLabel(compact: true),
                ),
              PositionedDirectional(
                bottom: 4,
                start: 4,
                child: _caption(caption, t),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: widget.onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _map() {
    final LatLng centre = _hasPin
        ? LatLng(widget.latitude!, widget.longitude!)
        : _fallbackCamera;

    return FlutterMap(
      key: _mapKey,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: _hasPin ? _pinnedZoom : _fallbackZoom,
        backgroundColor: DeliveryColors.background,
        // The thumbnail is a picture. Everything else happens in the picker.
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
      ),
      children: <Widget>[
        osmTiles(_watch),
        if (_hasPin)
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: centre,
                width: 34,
                height: 34,
                alignment: Alignment.topCenter,
                child: const ShopPinGlyph(size: 28),
              ),
            ],
          ),
      ],
    );
  }

  Widget _caption(String caption, DeliveryStrings t) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: DeliveryColors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm - 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _hasPin ? Icons.place : Icons.place_outlined,
            size: 12,
            color: _hasPin ? DeliveryColors.brand : DeliveryColors.faint,
          ),
          const SizedBox(width: 4),
          Text(
            widget.onTap == null ? caption : '$caption · ${_hasPin ? t.edit : t.merchPinSetIt}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _hasPin ? DeliveryColors.ink : DeliveryColors.muted,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------- picker

/// What the picker came back with: a point to save, or an instruction to clear the pin.
///
/// A sealed pair rather than a nullable [LatLng], because "the merchant cancelled" and "the
/// merchant asked to remove the pin" are opposite intentions and a null cannot tell them apart.
sealed class StorePinChoice {
  const StorePinChoice();
}

/// Save this point.
class StorePinPlaced extends StorePinChoice {
  const StorePinPlaced(this.point);

  final LatLng point;
}

/// Remove whatever pin the shop had.
class StorePinRemoved extends StorePinChoice {
  const StorePinRemoved();
}

/// Opens the picker as a sheet and returns what the merchant decided, or null if they backed out.
Future<StorePinChoice?> showStorePinPicker(
  BuildContext context, {
  double? latitude,
  double? longitude,
  GeocodingApi? geocoding,
  String? addressHint,
}) {
  return showModalBottomSheet<StorePinChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    useSafeArea: true,
    // A sheet rather than a dialog, and capped: most merchants are holding a phone, and a map
    // stretched across a 1400px portal window is harder to aim than one the width of a column.
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext context) => _StorePinPicker(
      latitude: latitude,
      longitude: longitude,
      geocoding: geocoding,
      addressHint: addressHint,
    ),
  );
}

class _StorePinPicker extends StatefulWidget {
  const _StorePinPicker({
    this.latitude,
    this.longitude,
    this.geocoding,
    this.addressHint,
  });

  final double? latitude;
  final double? longitude;

  /// Optional. Without it the picker is still a picker — it just has no search box, and the
  /// merchant pans instead of typing.
  final GeocodingApi? geocoding;

  /// The address already typed into the form, offered as the first search so the merchant usually
  /// does not have to type it twice.
  final String? addressHint;

  @override
  State<_StorePinPicker> createState() => _StorePinPickerState();
}

class _StorePinPickerState extends State<_StorePinPicker> {
  final MapController _map = MapController();
  final TextEditingController _search = TextEditingController();

  LatLng? _picked;
  bool _tilesFailed = false;

  late final MapTileWatch _watch = MapTileWatch(onGiveUp: _giveUp);

  List<PlaceCandidate> _results = <PlaceCandidate>[];
  bool _searching = false;
  Object? _searchError;

  /// Bumped on every keystroke so a slow answer to an old query cannot overwrite a fast answer to
  /// the current one.
  int _searchGeneration = 0;
  Timer? _debounce;

  /// [MapController.move] throws before the map has been laid out; a move requested earlier —
  /// the opening device fix, mostly — waits here for [MapOptions.onMapReady].
  bool _mapReady = false;
  LatLng? _pendingMove;
  double _pendingZoom = _pinnedZoom;

  /// True while the my-location control is resolving a fix.
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    if (widget.latitude != null && widget.longitude != null) {
      _picked = LatLng(widget.latitude!, widget.longitude!);
    } else {
      // No saved pin: quietly aim the camera at the phone instead of city-wide Beirut. Camera
      // ONLY — `_picked` stays null and Save stays disabled, because a merchant standing in their
      // shop and a merchant setting it up from home are indistinguishable here, and the pin is a
      // claim about the SHOP. Refusals of any kind just leave the fallback view; the my-location
      // button is where the question is asked out loud.
      DeviceLocation.current().then((DeviceLocationResult fix) {
        if (!mounted || _picked != null) return;
        if (fix is LocationFix) {
          _moveTo(LatLng(fix.latitude, fix.longitude), _pinnedZoom);
        }
      });
    }
    _search.text = widget.addressHint ?? '';
    _watch.start();
  }

  /// Points the camera somewhere, whether or not the map has finished building.
  void _moveTo(LatLng point, double zoom) {
    if (!_mapReady) {
      _pendingMove = point;
      _pendingZoom = zoom;
      return;
    }
    _map.move(point, zoom);
  }

  /// The my-location control's flow: a fix drops the pin there; each refusal is worded as its own
  /// problem, with the settings shortcut where one exists.
  Future<void> _useMyLocation(DeliveryStrings t) async {
    setState(() => _locating = true);
    final DeviceLocationResult result = await DeviceLocation.current();
    if (!mounted) return;
    setState(() => _locating = false);

    switch (result) {
      case LocationFix(:final double latitude, :final double longitude):
        _place(LatLng(latitude, longitude));
      case LocationServicesOff():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(t.locServicesOff),
            action: SnackBarAction(
              label: t.locTurnOn,
              onPressed: DeviceLocation.openLocationSettings,
            ),
          ));
      case LocationDenied():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t.locPermissionNeeded)));
      case LocationDeniedForever():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(t.locPermissionNeeded),
            action: SnackBarAction(
              label: t.locOpenSettings,
              onPressed: DeviceLocation.openAppSettings,
            ),
          ));
      case LocationFailed():
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t.locNoFix)));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _watch.dispose();
    _search.dispose();
    _map.dispose();
    super.dispose();
  }

  void _giveUp() {
    if (!mounted || _tilesFailed) return;
    setState(() => _tilesFailed = true);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // The server answers anything under three characters with an empty list without calling the
    // provider, so there is nothing to spend a round trip on here either.
    if (value.trim().length < 3) {
      setState(() {
        _results = <PlaceCandidate>[];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String query) async {
    final GeocodingApi? api = widget.geocoding;
    if (api == null) return;

    final int generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final PlaceSearchResult found = await api.searchPlaces(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = found.results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchError = e;
        _searching = false;
        _results = <PlaceCandidate>[];
      });
    }
  }

  void _place(LatLng point, {double? zoom}) {
    setState(() => _picked = point);
    _moveTo(point, zoom ?? _pinnedZoom);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final LatLng? picked = _picked;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
            DeliverySpacing.lg, 0, DeliverySpacing.lg, DeliverySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            YdSectionHeader(title: t.merchPinShopLocation),
            const SizedBox(height: DeliverySpacing.sm),
            if (widget.geocoding != null) ...<Widget>[
              _searchField(t),
              if (_results.isNotEmpty || _searching || _searchError != null) ...<Widget>[
                const SizedBox(height: DeliverySpacing.sm),
                _resultList(t),
              ],
              const SizedBox(height: DeliverySpacing.sm),
            ],
            SizedBox(
              // Two fifths of the window: enough map to aim with, and it still leaves the buttons
              // above the fold on a short phone.
              height: MediaQuery.sizeOf(context).height * 0.42,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
                child: _tilesFailed
                    ? MapSlotPlaceholder(label: t.merchMapUnavailable)
                    : _interactiveMap(picked),
              ),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            Text(
              _tilesFailed ? t.merchPinWhyItMatters : t.merchPinDropHint,
              style: const TextStyle(fontSize: 11, color: DeliveryColors.faint, height: 1.35),
            ),
            if (picked != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                // The point itself, to five places — about a metre. Shown because a merchant who
                // has just moved a pin should be able to see that it moved.
                '${picked.latitude.toStringAsFixed(5)}, ${picked.longitude.toStringAsFixed(5)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: DeliveryColors.muted,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md - DeliverySpacing.xs),
            _actions(t, picked),
          ],
        ),
      ),
    );
  }

  Widget _interactiveMap(LatLng? picked) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: picked ?? _fallbackCamera,
        initialZoom: picked == null ? _fallbackZoom : _pinnedZoom,
        backgroundColor: DeliveryColors.background,
        onMapReady: () {
          _mapReady = true;
          final LatLng? queued = _pendingMove;
          if (queued != null) {
            _pendingMove = null;
            _map.move(queued, _pendingZoom);
          }
        },
        onTap: (TapPosition _, LatLng point) => setState(() => _picked = point),
        interactionOptions: const InteractionOptions(
          // No rotation: a shop pin does not need a tilted north, and a two-finger twist on a
          // phone is the gesture people trigger by accident while pinching.
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
      ),
      children: <Widget>[
        osmTiles(_watch),
        if (picked != null)
          MarkerLayer(
            markers: <Marker>[
              Marker(
                point: picked,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const ShopPinGlyph(),
              ),
            ],
          ),
        // My-location, floated at the start corner so the attribution keeps the end one. Drops
        // the pin at the phone — the one-tap answer for the common case of a merchant standing
        // in their own shop.
        Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Padding(
            padding: const EdgeInsets.all(DeliverySpacing.sm),
            child: Material(
              color: DeliveryColors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _locating ? null : () => _useMyLocation(t),
                child: SizedBox.square(
                  dimension: 40,
                  child: _locating
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: DeliveryColors.brand),
                        )
                      : Semantics(
                          button: true,
                          label: t.locMyLocation,
                          child: const Icon(Icons.my_location_rounded,
                              size: 20, color: DeliveryColors.brand),
                        ),
                ),
              ),
            ),
          ),
        ),
        const Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: OsmAttributionLabel(),
          ),
        ),
      ],
    );
  }

  Widget _searchField(DeliveryStrings t) {
    return TextField(
      controller: _search,
      onChanged: _onSearchChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: (String v) => _runSearch(v.trim()),
      cursorColor: DeliveryColors.brand,
      style: const TextStyle(fontSize: 13, color: DeliveryColors.ink, height: 1.35),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: DeliveryColors.background,
        hintText: t.searchForAPlace,
        hintStyle: const TextStyle(fontSize: 13, color: DeliveryColors.faint),
        prefixIcon: const Icon(Icons.search, size: 18, color: DeliveryColors.faint),
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: DeliverySpacing.md - DeliverySpacing.xs,
          vertical: DeliverySpacing.md - DeliverySpacing.xs,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DeliveryRadius.sm + 2),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _resultList(DeliveryStrings t) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: DeliveryColors.brand),
          ),
        ),
      );
    }
    if (_searchError != null) {
      return Text(
        t.couldNotSearchPlaces,
        style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
      );
    }
    if (_results.isEmpty) {
      return Text(
        t.noPlacesFound,
        style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.35),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 132),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _results.length,
        itemBuilder: (BuildContext context, int index) {
          final PlaceCandidate place = _results[index];
          return InkWell(
            onTap: () {
              FocusScope.of(context).unfocus();
              _place(LatLng(place.latitude, place.longitude));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.place_outlined, size: 16, color: DeliveryColors.faint),
                  const SizedBox(width: DeliverySpacing.sm),
                  Expanded(
                    child: Text(
                      // Text from an open map database: rendered as text, never as markup.
                      place.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: DeliveryColors.ink, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actions(DeliveryStrings t, LatLng? picked) {
    final bool hadPin = widget.latitude != null && widget.longitude != null;

    return Row(
      children: <Widget>[
        if (hadPin) ...<Widget>[
          Expanded(
            child: _SheetButton(
              label: t.remove,
              icon: Icons.location_off_outlined,
              onPressed: () => Navigator.of(context).pop(const StorePinRemoved()),
            ),
          ),
          const SizedBox(width: DeliverySpacing.sm),
        ],
        Expanded(
          flex: 2,
          child: _SheetButton(
            label: t.save,
            icon: Icons.check_rounded,
            primary: true,
            // Nothing to save until a point exists. A disabled button says that better than a
            // snackbar after the fact.
            onPressed: picked == null
                ? null
                : () => Navigator.of(context).pop(StorePinPlaced(picked)),
          ),
        ),
      ],
    );
  }
}

/// The sheet's paired action button — the shop-config frame's button language, kept here so the
/// picker matches the screen that opened it.
class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  /// Already localised by the caller.
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color background = primary
        ? (enabled ? DeliveryColors.brand : DeliveryColors.brandLine)
        : DeliveryColors.background;
    final Color foreground = primary
        ? DeliveryColors.white
        : (enabled ? DeliveryColors.muted : DeliveryColors.faint);
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.sm + 2);

    return Semantics(
      button: true,
      child: Material(
        color: background,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            // 48dp of height with the 13px label inside it — the size a thumb needs.
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: DeliverySpacing.md - DeliverySpacing.xs,
              vertical: 14,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'rider_job_card.dart' show riderOsmTileTemplate, riderOsmUserAgent;

/// The circles this company works (Figma 88:107).
///
/// <p>A map of every zone as a translucent crimson circle with a label chip, and a card per zone
/// with its switch, edit and delete. Adding or editing opens a full-screen picker: tap to place
/// the pin, slide to size the circle — one pin and one slider, the same grammar as the merchant's
/// delivery radius, because a phone is not a GIS console.
///
/// <p>Every change goes straight to the server and the list re-reads the reply, so what the
/// screen shows is always what dispatch would read — never an optimistic circle that quietly
/// failed to save.
class CarrierZonesScreen extends StatefulWidget {
  const CarrierZonesScreen({super.key, required this.api});

  final DeliveryProviderApi api;

  @override
  State<CarrierZonesScreen> createState() => _CarrierZonesScreenState();
}

class _CarrierZonesScreenState extends State<CarrierZonesScreen> {
  List<CoverageZone> _zones = <CoverageZone>[];
  bool _loading = true;
  Object? _error;
  bool _busy = false;

  /// Beirut, where the fleet almost certainly is when there is nothing else to centre on.
  static const LatLng _fallbackCentre = LatLng(33.8938, 35.5018);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _zones.isEmpty;
      _error = null;
    });
    try {
      final List<CoverageZone> zones = await widget.api.myZones();
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(CoverageZone zone, bool active) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final CoverageZone updated =
          await widget.api.redrawZone(zone.copyWith(active: active));
      if (!mounted) return;
      setState(() => _zones = <CoverageZone>[
            for (final CoverageZone z in _zones)
              z.id == updated.id ? updated : z,
          ]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).somethingWentWrong)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(CoverageZone zone) async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: Text(t.carrDeleteZoneAsk(zone.name)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
            child: Text(t.remove),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.eraseZone(zone.id);
      if (!mounted) return;
      setState(() => _zones = <CoverageZone>[
            for (final CoverageZone z in _zones)
              if (z.id != zone.id) z,
          ]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(DeliveryStrings.of(context).somethingWentWrong)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([CoverageZone? zone]) async {
    final CoverageZone? result = await Navigator.of(context).push(
      MaterialPageRoute<CoverageZone>(
        builder: (BuildContext context) => _ZoneEditor(
          api: widget.api,
          zone: zone,
          centre: zone != null
              ? LatLng(zone.latitude, zone.longitude)
              : (_zones.isNotEmpty
                  ? LatLng(_zones.first.latitude, _zones.first.longitude)
                  : _fallbackCentre),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final int i = _zones.indexWhere((CoverageZone z) => z.id == result.id);
      if (i < 0) {
        _zones = <CoverageZone>[..._zones, result];
      } else {
        _zones = <CoverageZone>[
          for (final CoverageZone z in _zones) z.id == result.id ? result : z,
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: t.carrCoverageZones,
        onBack: () => Navigator.of(context).pop(),
        backSemanticLabel: t.back,
        trailing: YdPillButton(
          label: t.carrAddZone,
          expand: false,
          size: YdPillButtonSize.compact,
          onPressed: _busy ? null : () => _edit(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: DeliveryColors.brand))
          : _error != null && _zones.isEmpty
              ? Center(
                  child: YdEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: t.somethingWentWrong,
                    message: t.couldNotReachTheServer,
                    action: YdPillButton.secondary(
                      label: t.tryAgain,
                      expand: false,
                      size: YdPillButtonSize.compact,
                      onPressed: _load,
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: DeliveryColors.brand,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(DeliverySpacing.md),
                    children: <Widget>[
                      if (_zones.isNotEmpty) ...<Widget>[
                        _zonesMap(),
                        const SizedBox(height: DeliverySpacing.md),
                      ],
                      if (_zones.isEmpty)
                        YdCard.bordered(
                          child: Text(t.carrNoZones,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: DeliveryColors.muted,
                                  height: 1.4)),
                        ),
                      for (final CoverageZone zone in _zones)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: DeliverySpacing.sm),
                          child: _zoneCard(t, zone),
                        ),
                      const SizedBox(height: DeliverySpacing.lg),
                    ],
                  ),
                ),
    );
  }

  /// The map card: every zone drawn as a circle, active ones crimson and paused ones grey, each
  /// with a small label chip at its centre.
  Widget _zonesMap() {
    final LatLngBounds bounds = LatLngBounds.fromPoints(<LatLng>[
      for (final CoverageZone z in _zones) LatLng(z.latitude, z.longitude),
    ]);

    return ClipRRect(
      borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(48),
              maxZoom: 14,
            ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: riderOsmTileTemplate,
              userAgentPackageName: riderOsmUserAgent,
              maxNativeZoom: 19,
            ),
            CircleLayer(
              circles: <CircleMarker>[
                for (final CoverageZone z in _zones)
                  CircleMarker(
                    point: LatLng(z.latitude, z.longitude),
                    radius: z.radiusMetres.toDouble(),
                    useRadiusInMeter: true,
                    color: (z.active
                            ? DeliveryColors.brand
                            : DeliveryColors.faint)
                        .withValues(alpha: 0.14),
                    borderColor:
                        z.active ? DeliveryColors.brand : DeliveryColors.faint,
                    borderStrokeWidth: 2,
                  ),
              ],
            ),
            MarkerLayer(
              markers: <Marker>[
                for (final CoverageZone z in _zones)
                  Marker(
                    point: LatLng(z.latitude, z.longitude),
                    width: 160,
                    height: 32,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: DeliveryColors.ink.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          z.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: DeliveryColors.white,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoneCard(DeliveryStrings t, CoverageZone zone) {
    final String km = (zone.radiusMetres / 1000).toStringAsFixed(
        zone.radiusMetres % 1000 == 0 ? 0 : 1);
    return YdCard.bordered(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(zone.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: DeliverySpacing.sm),
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: zone.active
                            ? const Color(0xFFE7F6EC)
                            : const Color(0xFFFDF3DE),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        zone.active ? t.carrZoneActive : t.carrZonePaused,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: zone.active
                              ? const Color(0xFF167A4B)
                              : const Color(0xFFB07B0F),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(t.carrZoneRadiusKm(km),
                    style: const TextStyle(
                        fontSize: 12, color: DeliveryColors.muted)),
              ],
            ),
          ),
          Switch(
            value: zone.active,
            activeThumbColor: DeliveryColors.white,
            activeTrackColor: DeliveryColors.brand,
            onChanged: _busy ? null : (bool v) => _toggle(zone, v),
          ),
          IconButton(
            onPressed: _busy ? null : () => _edit(zone),
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: DeliveryColors.muted),
            tooltip: t.carrEditZone,
          ),
          IconButton(
            onPressed: _busy ? null : () => _delete(zone),
            icon: const Icon(Icons.delete_outline,
                size: 20, color: DeliveryColors.brand),
            tooltip: t.remove,
          ),
        ],
      ),
    );
  }
}

/// The full-screen add/edit surface: tap places the pin, the slider sizes the circle, the name
/// field names it. Save posts and pops the server's answer.
class _ZoneEditor extends StatefulWidget {
  const _ZoneEditor({required this.api, required this.centre, this.zone});

  final DeliveryProviderApi api;
  final CoverageZone? zone;
  final LatLng centre;

  @override
  State<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<_ZoneEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.zone?.name ?? '');
  late LatLng _pin =
      widget.zone == null ? widget.centre : LatLng(widget.zone!.latitude, widget.zone!.longitude);
  late double _radiusKm = (widget.zone?.radiusMetres ?? 3000) / 1000;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = t.requiredField);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final int metres = (_radiusKm * 1000).round();
      final CoverageZone saved = widget.zone == null
          ? await widget.api.drawZone(
              name: _name.text.trim(),
              latitude: _pin.latitude,
              longitude: _pin.longitude,
              radiusMetres: metres,
            )
          : await widget.api.redrawZone(widget.zone!.copyWith(
              name: _name.text.trim(),
              latitude: _pin.latitude,
              longitude: _pin.longitude,
              radiusMetres: metres,
            ));
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = t.somethingWentWrong;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      appBar: YdScreenHeader(
        title: widget.zone == null ? t.carrNewZone : t.carrEditZone,
        onBack: _saving ? null : () => Navigator.of(context).pop(),
        backSemanticLabel: t.back,
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _pin,
                initialZoom: 12,
                onTap: _saving
                    ? null
                    : (TapPosition _, LatLng point) =>
                        setState(() => _pin = point),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: riderOsmTileTemplate,
                  userAgentPackageName: riderOsmUserAgent,
                  maxNativeZoom: 19,
                ),
                CircleLayer(
                  circles: <CircleMarker>[
                    CircleMarker(
                      point: _pin,
                      radius: _radiusKm * 1000,
                      useRadiusInMeter: true,
                      color: DeliveryColors.brand.withValues(alpha: 0.14),
                      borderColor: DeliveryColors.brand,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: <Marker>[
                    Marker(
                      point: _pin,
                      width: 32,
                      height: 32,
                      child: const Icon(Icons.place,
                          size: 32, color: DeliveryColors.brand),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(DeliverySpacing.md),
            color: DeliveryColors.white,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _name,
                    enabled: !_saving,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: t.carrZoneName,
                      hintText: t.carrZoneNameHint,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: DeliverySpacing.sm),
                  Row(
                    children: <Widget>[
                      Text(
                        t.carrZoneRadiusKm(_radiusKm.toStringAsFixed(1)),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      Expanded(
                        child: Slider(
                          value: _radiusKm,
                          min: 0.5,
                          max: 30,
                          divisions: 59,
                          activeColor: DeliveryColors.brand,
                          onChanged: _saving
                              ? null
                              : (double v) => setState(() => _radiusKm = v),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...<Widget>[
                    Text(_error!,
                        style: const TextStyle(
                            fontSize: 12.5, color: DeliveryColors.brand)),
                    const SizedBox(height: DeliverySpacing.sm),
                  ],
                  YdPillButton(
                    label: t.save,
                    busy: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Merchant Blitz: a shop's catalogue from photographs of its shelves.
///
/// Figma `merchant-blitz` (121:198). The merchant photographs a shelf, or several, a photo reader
/// lists the products it can see, and the merchant checks every one before it becomes a DRAFT
/// product. Three steps, drawn as the frame's strip: scan the shop, check the items, save the drafts.
///
/// What this screen deliberately does NOT say, although the frame does:
///  * "Review & Publish Catalog" and "Start Selling". Nothing here publishes. An accepted line is a
///    draft customers cannot see: a vision model's reading of a shelf does not go in front of
///    customers without a person publishing it, and a draft with no photo could not be published
///    anyway.
///  * "Zero Manual Entry Required", "matches them to active wholesale price guides in Beirut" and
///    "Your shop online in 24 hours". No price guide exists anywhere in the platform (a price here is
///    the reader's guess, labelled as one), the merchant always confirms a price, and a shop's
///    approval is not this screen's to promise.
///  * The customer bottom nav the frame is drawn in. The catalogue is a merchant's, so this is pushed
///    from the merchant's own Inventory and Settings, over whichever shell hosts them.
///
/// Sample results are said to be samples. Until the owner provisions the reader, the server answers
/// with fixed example lines and marks the scan `sample`; presenting those as a reading of the
/// merchant's shelf would be showing items the platform does not actually have.
///
/// A scan belongs to the server, not to this screen. Opening the page picks up the merchant's newest
/// scan that still waits on them — photos still to add, a reading under way, lines to check — so an
/// app Android killed while the camera was open, a merchant who left during the reading, or a
/// reloaded portal tab carries on instead of stranding the scan with its photos, a share of the day's
/// allowance and a paid reading. On Android a photo the camera took while the app was gone is
/// recovered too.
///
/// Host-agnostic like the rest of the package: the phone pushes it from the Inventory tab and from
/// Settings, the portal from its Inventory page — where there is no camera, so "Choose photos" is
/// the only way in and "Take photo" is never drawn.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'catalog_scan_review_screen.dart';
import 'order_detail_screen.dart';
import 'photo_source.dart';

/// The Merchant Blitz screen. Pushed as its own route; see the library comment.
class MerchantBlitzScreen extends StatefulWidget {
  const MerchantBlitzScreen({
    super.key,
    required this.api,
    required this.catalogApi,
    this.storeId,
    this.photoSource = const DeviceShelfPhotoSource(),
    this.pollInterval = const Duration(seconds: 3),
    this.onBack,
  });

  final CatalogScanApi api;

  /// The shop's own sections and the platform's, for the review's section picker.
  final CatalogApi catalogApi;

  /// Which of the merchant's shops to fill. Null lets the server use the merchant's own — and
  /// create it, the way a first product does, for a merchant who has not set a shop up yet.
  final String? storeId;

  final ShelfPhotoSource photoSource;

  /// How often an analysing scan is re-read. A reading takes tens of seconds; three seconds keeps
  /// the wait honest without spending the shared gateway budget on a spinner.
  final Duration pollInterval;

  /// Overrides the back button. Null pops the route when there is one to pop, and draws no back
  /// button when there is not.
  final VoidCallback? onBack;

  @override
  State<MerchantBlitzScreen> createState() => _MerchantBlitzScreenState();
}

class _MerchantBlitzScreenState extends State<MerchantBlitzScreen>
    with SingleTickerProviderStateMixin {
  /// The frame's viewfinder height.
  static const double _viewfinderHeight = 270;

  /// Tags drawn over one photo at most. The frame draws two; a crowded shelf reads as dozens, and a
  /// photo buried under labels shows the merchant nothing. The most certain lines win.
  static const int _maxTags = 6;

  CatalogScan? _scan;

  /// True until the server has said whether a scan is waiting to be picked up. Nothing that would
  /// start a scan can be tapped meanwhile: a merchant quick enough to pick a photo first would
  /// otherwise spend a second scan beside the one being fetched.
  bool _resuming = true;

  /// The photos this visit uploaded, by file id, so the viewfinder draws them from memory instead of
  /// downloading what the phone already holds. A scan picked up again has none here and draws its
  /// photos from the server.
  final Map<String, Uint8List> _bytesByFile = <String, Uint8List>{};

  String? _selectedFileId;

  bool _starting = false;
  int _uploadDone = 0;
  int _uploadTotal = 0;
  bool _requestingAnalysis = false;
  bool _refreshing = false;

  /// The last poll failed. The scan is still running on the server; only our view of it is stale.
  bool _pollFailed = false;

  /// A sentence about the last thing that could not be done — a spent quota, a scan that would
  /// not start. Cleared by the next attempt.
  String? _error;

  Timer? _poll;
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  bool get _uploading => _uploadTotal > 0;

  @override
  void initState() {
    super.initState();
    unawaited(_resume());
  }

  /// Picks up where the merchant left off: the newest scan still waiting on them, then — on Android
  /// — a photo the camera took while the app was gone, sent on that scan, or on a new one exactly as
  /// a first photo always starts one.
  Future<void> _resume() async {
    CatalogScan? waiting;
    try {
      waiting = await widget.api.current(storeId: widget.storeId);
    } catch (e) {
      // Not being able to look is no reason to lock the merchant out: the page opens fresh, as it
      // did before a scan could be picked up again.
      debugPrint('BLITZ RESUME FAILED: $e');
    }
    if (!mounted) return;
    final CatalogScan? found = waiting;
    setState(() {
      _resuming = false;
      if (found != null) _apply(found);
    });

    PickedShelfPhoto? lost;
    try {
      lost = await widget.photoSource.retrieveLostPhoto();
    } catch (e) {
      debugPrint('BLITZ LOST PHOTO FAILED: $e');
    }
    if (lost == null || !mounted) return;
    final CatalogScan? scan = _scan;
    if (scan != null && scan.status != CatalogScanStatus.uploading) {
      // Only reachable from another device: the camera is only offered while a scan takes photos,
      // and nothing moved this one on while the app was dead. Starting a scan the merchant did not
      // ask for would spend their allowance, so the photo is left.
      debugPrint('BLITZ LOST PHOTO LEFT: scan ${scan.id} is ${scan.status.wireValue}');
      return;
    }
    await _upload(<PickedShelfPhoto>[lost]);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- state

  /// Adopts what the server says, and starts or stops everything that depends on the status.
  void _apply(CatalogScan scan) {
    _scan = scan;
    final List<ScanPhoto> photos = scan.photos;
    if (_selectedFileId == null || !photos.any((ScanPhoto p) => p.fileId == _selectedFileId)) {
      final List<ScanPhoto> uploaded = scan.uploadedPhotos;
      _selectedFileId = uploaded.isEmpty ? null : uploaded.last.fileId;
    }

    final bool analyzing = scan.status == CatalogScanStatus.analyzing;
    if (analyzing) {
      _poll ??= Timer.periodic(widget.pollInterval, (_) => _refresh());
    } else {
      _poll?.cancel();
      _poll = null;
      _pollFailed = false;
    }

    // The sweep is decoration. With animations switched off in accessibility settings the line is
    // still drawn, just still.
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (analyzing && !still) {
      if (!_sweep.isAnimating) _sweep.repeat(reverse: true);
    } else if (_sweep.isAnimating) {
      _sweep.stop();
    }
  }

  void _reset() {
    setState(() {
      _poll?.cancel();
      _poll = null;
      _sweep.stop();
      _scan = null;
      _bytesByFile.clear();
      _selectedFileId = null;
      _error = null;
      _pollFailed = false;
    });
  }

  Future<void> _refresh() async {
    final CatalogScan? scan = _scan;
    if (scan == null || _refreshing) return;
    _refreshing = true;
    try {
      final CatalogScan next = await widget.api.read(scan.id);
      if (!mounted) return;
      setState(() {
        _pollFailed = false;
        _apply(next);
      });
    } catch (_) {
      if (!mounted) return;
      // Keep polling: a dropped connection on a phone usually comes back, and the scan is still
      // running server-side whatever this screen can see.
      setState(() => _pollFailed = true);
    } finally {
      _refreshing = false;
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> _takePhoto() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final PickedShelfPhoto? photo;
    try {
      photo = await widget.photoSource.takePhoto();
    } catch (e) {
      // Surfaced, never swallowed: a camera that silently fails to open reads as a dead button.
      debugPrint('BLITZ CAMERA FAILED: $e');
      if (!mounted) return;
      _snack(t.blitzCameraFailed);
      return;
    }
    if (photo == null || !mounted) return;
    await _upload(<PickedShelfPhoto>[photo]);
  }

  Future<void> _choosePhotos() async {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<PickedShelfPhoto> photos;
    try {
      photos = await widget.photoSource.choosePhotos(label: t.images);
    } catch (e) {
      debugPrint('BLITZ PICKER FAILED: $e');
      if (!mounted) return;
      _snack(t.couldNotOpenPicker(_reasonFrom(e)));
      return;
    }
    if (photos.isEmpty || !mounted) return;
    await _upload(photos);
  }

  /// Starts the scan on the first photo, then sends each photo in turn.
  ///
  /// One at a time on purpose: each is a presign, a PUT of up to two megabytes and a confirm, and a
  /// shop on mobile data sending six at once gets six timeouts instead of six photos.
  Future<void> _upload(List<PickedShelfPhoto> picked) async {
    final DeliveryStrings t = DeliveryStrings.of(context);

    CatalogScan? scan = _scan;
    if (scan == null) {
      setState(() {
        _starting = true;
        _error = null;
      });
      try {
        scan = await widget.api.start(storeId: widget.storeId);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _starting = false;
          _error = _startFailure(e, t);
        });
        return;
      }
      if (!mounted) return;
      final CatalogScan started = scan;
      setState(() {
        _starting = false;
        _apply(started);
      });
    }

    final int room = scan.maxPhotos - scan.photos.length;
    if (picked.length > room) {
      _snack(t.blitzTooManyPhotos(scan.maxPhotos));
    }
    if (room <= 0) return;
    final List<PickedShelfPhoto> sending = picked.take(room).toList();

    setState(() {
      _error = null;
      _uploadDone = 0;
      _uploadTotal = sending.length;
    });
    for (final PickedShelfPhoto photo in sending) {
      final CatalogScan current = _scan!;
      final Set<String> before = current.photos.map((ScanPhoto p) => p.fileId).toSet();
      try {
        final CatalogScan next = await widget.api.addPhoto(
          scanId: current.id,
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
        if (!mounted) return;
        String? added;
        for (final ScanPhoto p in next.photos) {
          if (!before.contains(p.fileId)) added = p.fileId;
        }
        setState(() {
          if (added != null) {
            _bytesByFile[added] = photo.bytes;
            _selectedFileId = added;
          }
          _uploadDone++;
          _apply(next);
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _uploadTotal = 0);
        _snack(_messageFor(e, fallback: t.blitzUploadFailed));
        return;
      }
    }
    if (mounted) setState(() => _uploadTotal = 0);
  }

  Future<void> _analyze() async {
    final CatalogScan? scan = _scan;
    if (scan == null || _requestingAnalysis) return;
    final DeliveryStrings t = DeliveryStrings.of(context);
    setState(() {
      _requestingAnalysis = true;
      _error = null;
    });
    try {
      final CatalogScan next = await widget.api.analyze(scan.id);
      if (!mounted) return;
      setState(() {
        _requestingAnalysis = false;
        _apply(next);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requestingAnalysis = false;
        _error = _messageFor(e, fallback: t.blitzCouldNotStart);
      });
      // A 409 means the scan is further along than this screen thought — already analysing, say,
      // from a double tap. Re-read it rather than leave a stale state on screen.
      unawaited(_refresh());
    }
  }

  Future<void> _openReview() async {
    final CatalogScan? scan = _scan;
    if (scan == null) return;
    final CatalogScan? updated = await Navigator.of(context).push<CatalogScan>(
      MaterialPageRoute<CatalogScan>(
        builder: (_) => CatalogScanReviewScreen(
          api: widget.api,
          catalogApi: widget.catalogApi,
          scan: scan,
          storeId: scan.storeId ?? widget.storeId,
        ),
      ),
    );
    if (!mounted) return;
    if (updated != null) setState(() => _apply(updated));
    // And read it again however the review closed: a save whose answer was lost, then a back press,
    // would otherwise leave this page offering to review lines that are already drafts.
    unawaited(_refresh());
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// A spent daily quota is worded with its own number; anything else gets the server's sentence.
  String _startFailure(Object e, DeliveryStrings t) {
    if (e is DioException && e.response?.statusCode == 429) {
      final Object? body = e.response?.data;
      final Object? limit = body is Map<String, dynamic> ? body['limit'] : null;
      if (limit is num) return t.blitzQuotaReached(limit.toInt());
    }
    return _messageFor(e, fallback: t.blitzCouldNotStart);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final CatalogScan? scan = _scan;
    final NavigatorState? navigator = Navigator.maybeOf(context);
    final VoidCallback? back = widget.onBack ??
        ((navigator?.canPop() ?? false) ? () => navigator!.maybePop() : null);

    return Scaffold(
      backgroundColor: DeliveryColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            MerchantScreenHeader(
              title: t.blitzTitle,
              subtitle: t.blitzSubtitle,
              onBack: back,
              backSemanticLabel: t.back,
              trailing: YdBadge.brand(label: t.blitzFastSetup, uppercase: false),
            ),
            _StepStrip(step: _stepOf(scan), allDone: _allDecided(scan)),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: merchantMaxContentWidth),
                  child: ListView(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      DeliverySpacing.md,
                      DeliverySpacing.md,
                      DeliverySpacing.md,
                      DeliverySpacing.lg + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: <Widget>[
                      // A sample result is read as a sample before anything else on the page:
                      // above the photo, and above the green "Scan complete".
                      if (_showsSamples(scan)) ...<Widget>[
                        _Notice(
                          accent: DeliveryAccent.caution,
                          icon: Icons.science_outlined,
                          title: t.blitzSampleTitle,
                          body: t.blitzSampleBody,
                        ),
                        const SizedBox(height: DeliverySpacing.md),
                      ],
                      _viewfinder(t, scan),
                      if ((scan?.photos.length ?? 0) > 1) ...<Widget>[
                        const SizedBox(height: DeliverySpacing.sm),
                        _photoStrip(t, scan!),
                      ],
                      const SizedBox(height: DeliverySpacing.md),
                      ..._status(t, scan),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A finished reading made of sample lines: the page says so first.
  static bool _showsSamples(CatalogScan? scan) =>
      scan != null &&
      scan.sample &&
      scan.status == CatalogScanStatus.complete &&
      scan.lines.isNotEmpty;

  /// 1 while photos are being gathered, 2 from the reading until every line is decided.
  static int _stepOf(CatalogScan? scan) {
    if (scan == null || scan.status == CatalogScanStatus.uploading) return 1;
    return _allDecided(scan) ? 3 : 2;
  }

  /// Every line the reader found has been kept or skipped — the last step is behind the merchant.
  static bool _allDecided(CatalogScan? scan) =>
      scan != null &&
      scan.status == CatalogScanStatus.complete &&
      scan.lines.isNotEmpty &&
      scan.pendingLines.isEmpty;

  Widget _viewfinder(DeliveryStrings t, CatalogScan? scan) {
    final List<ScanPhoto> photos = scan?.photos ?? const <ScanPhoto>[];
    final int index = photos.indexWhere((ScanPhoto p) => p.fileId == _selectedFileId);
    final ScanPhoto? shown = index < 0 ? null : photos[index];

    ImageProvider? image;
    if (shown != null) {
      final Uint8List? bytes = _bytesByFile[shown.fileId];
      final String? url = shown.imageUrl;
      if (bytes != null) {
        image = MemoryImage(bytes);
      } else if (url != null) {
        image = DeliveryImages.provider(url);
      }
    }

    // Sample lines are not a reading of this photo: their boxes are made up, and a tag drawn on the
    // merchant's own shelf would say the reader found that product there. So samples get none.
    final List<ScanLine> tagged = shown == null || scan == null || scan.sample
        ? const <ScanLine>[]
        : (scan.lines
                .where((ScanLine l) => l.photoFileId == shown.fileId && l.box != null)
                .toList()
              ..sort((ScanLine a, ScanLine b) => b.confidence.compareTo(a.confidence)))
            .take(_maxTags)
            .toList();

    return _Viewfinder(
      height: _viewfinderHeight,
      image: image,
      semanticLabel: shown == null ? t.blitzIntroTitle : t.blitzPhotoLabel(index + 1),
      lines: tagged,
      tagFor: (ScanLine line) => line.priceGuess == null
          ? line.name
          : t.blitzTag(line.name, '\$${merchantMoney(line.priceGuess!)}'),
      analyzing: scan?.status == CatalogScanStatus.analyzing,
      sweep: _sweep,
    );
  }

  Widget _photoStrip(DeliveryStrings t, CatalogScan scan) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: scan.photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: DeliverySpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final ScanPhoto photo = scan.photos[i];
          final Uint8List? bytes = _bytesByFile[photo.fileId];
          final String? url = photo.imageUrl;
          final bool selected = photo.fileId == _selectedFileId;
          final ImageProvider? image = bytes != null
              ? MemoryImage(bytes)
              : (url != null ? DeliveryImages.provider(url) : null);
          return Semantics(
            button: true,
            selected: selected,
            label: t.blitzPhotoLabel(i + 1),
            child: InkWell(
              onTap: photo.uploaded ? () => setState(() => _selectedFileId = photo.fileId) : null,
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  color: DeliveryColors.shellDeep,
                  borderRadius: BorderRadius.circular(DeliveryRadius.md),
                  border: Border.all(
                    color: selected ? DeliveryColors.brand : DeliveryColors.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: image == null
                    ? const Icon(Icons.image_outlined, color: DeliveryColors.onShellMuted)
                    : Image(image: image, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _status(DeliveryStrings t, CatalogScan? scan) {
    final List<Widget> out = <Widget>[];
    final String? error = _error;
    if (error != null) {
      out
        ..add(_Notice(accent: DeliveryAccent.critical, icon: Icons.error_outline, body: error))
        ..add(const SizedBox(height: DeliverySpacing.md));
    }

    switch (scan?.status) {
      case null:
      case CatalogScanStatus.uploading:
        out.addAll(_gathering(t, scan));
      case CatalogScanStatus.analyzing:
        out.addAll(_reading(t));
      case CatalogScanStatus.complete:
        out.addAll(_complete(t, scan!));
      case CatalogScanStatus.failed:
      case CatalogScanStatus.unknown:
        out.addAll(_failed(t, scan!));
    }

    final int? left = scan?.scansLeftToday;
    if (left != null) {
      out
        ..add(const SizedBox(height: DeliverySpacing.md))
        ..add(Text(
          t.blitzScansLeft(left),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
        ));
    }
    out
      ..add(const SizedBox(height: DeliverySpacing.sm))
      ..add(Text(
        t.blitzFooter,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, color: DeliveryColors.faint),
      ));
    return out;
  }

  /// No scan yet, or photos still being added.
  List<Widget> _gathering(DeliveryStrings t, CatalogScan? scan) {
    final int uploaded = scan?.uploadedPhotos.length ?? 0;
    final bool busy = _resuming || _starting || _uploading || _requestingAnalysis;
    final bool full = scan != null && scan.photos.length >= scan.maxPhotos;
    final bool camera = widget.photoSource.canUseCamera;
    final VoidCallback? take = busy || full ? null : _takePhoto;
    final VoidCallback? choose = busy || full ? null : _choosePhotos;

    return <Widget>[
      if (uploaded == 0) ...<Widget>[
        _Explainer(title: t.blitzIntroTitle, body: t.blitzIntroBody),
        const SizedBox(height: DeliverySpacing.md),
      ],
      if (scan != null && scan.photos.isNotEmpty) ...<Widget>[
        Text(
          t.blitzPhotoCount(uploaded, scan.maxPhotos),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DeliveryColors.ink),
        ),
        const SizedBox(height: DeliverySpacing.sm),
      ],
      if (_uploading) ...<Widget>[
        _Progress(
          label: t.blitzUploading(
            (_uploadDone + 1).clamp(1, _uploadTotal),
            _uploadTotal,
          ),
          value: _uploadDone / _uploadTotal,
        ),
        const SizedBox(height: DeliverySpacing.md),
      ] else if (_starting || _resuming) ...<Widget>[
        const _Progress(),
        const SizedBox(height: DeliverySpacing.md),
      ],
      if (uploaded == 0) ...<Widget>[
        if (camera) ...<Widget>[
          _PrimaryButton(icon: Icons.photo_camera_outlined, label: t.blitzTakePhoto, onPressed: take),
          const SizedBox(height: DeliverySpacing.sm),
          _SecondaryButton(
              icon: Icons.photo_library_outlined, label: t.blitzChoosePhotos, onPressed: choose),
        ] else
          _PrimaryButton(
              icon: Icons.photo_library_outlined, label: t.blitzChoosePhotos, onPressed: choose),
      ] else ...<Widget>[
        if (!full)
          Wrap(
            spacing: DeliverySpacing.sm,
            runSpacing: DeliverySpacing.sm,
            children: <Widget>[
              if (camera)
                _SecondaryButton(
                    icon: Icons.photo_camera_outlined,
                    label: t.blitzTakePhoto,
                    onPressed: take,
                    expand: false),
              _SecondaryButton(
                  icon: Icons.photo_library_outlined,
                  label: t.blitzChoosePhotos,
                  onPressed: choose,
                  expand: false),
            ],
          ),
        const SizedBox(height: DeliverySpacing.md),
        _PrimaryButton(
          icon: Icons.document_scanner_outlined,
          label: t.blitzScanPhotos(uploaded),
          busy: _requestingAnalysis,
          onPressed: busy ? null : _analyze,
        ),
      ],
    ];
  }

  /// The reader is working. The review button is drawn, disabled, so the merchant can see where
  /// this is going.
  List<Widget> _reading(DeliveryStrings t) {
    return <Widget>[
      _Notice(
        accent: DeliveryAccent.info,
        icon: Icons.hourglass_top_rounded,
        title: t.blitzAnalyzing,
        body: _pollFailed ? t.blitzConnectionLost : t.blitzAnalyzingHint,
        busy: true,
      ),
      const SizedBox(height: DeliverySpacing.md),
      _PrimaryButton(label: t.blitzReviewCta, onPressed: null),
    ];
  }

  List<Widget> _complete(DeliveryStrings t, CatalogScan scan) {
    final int found = scan.lines.length;
    // A sample notice, when there is one, is already at the top of the page — see [_showsSamples].
    final List<Widget> out = <Widget>[
      _CompleteBanner(title: t.blitzScanComplete, count: t.blitzItemsFound(found)),
      const SizedBox(height: DeliverySpacing.md),
    ];

    if (found == 0) {
      return out
        ..add(_Explainer(title: t.blitzNoneFound, body: t.blitzNoneFoundHint))
        ..add(const SizedBox(height: DeliverySpacing.md))
        ..add(_PrimaryButton(icon: Icons.refresh, label: t.blitzNewScan, onPressed: _reset));
    }

    if (_allDecided(scan)) {
      final int kept =
          scan.lines.where((ScanLine l) => l.status == ScanLineStatus.accepted).length;
      return out
        ..add(_Explainer(
          title: t.blitzSavedTitle,
          body: kept == 0 ? t.blitzSavedCount(0) : '${t.blitzSavedCount(kept)} ${t.blitzSavedHint}',
        ))
        ..add(const SizedBox(height: DeliverySpacing.md))
        ..add(_SecondaryButton(icon: Icons.refresh, label: t.blitzNewScan, onPressed: _reset));
    }

    return out
      ..add(_Explainer(title: t.blitzIntroTitle, body: t.blitzIntroBody))
      ..add(const SizedBox(height: DeliverySpacing.md))
      ..add(_PrimaryButton(label: t.blitzReviewCta, onPressed: _openReview));
  }

  List<Widget> _failed(DeliveryStrings t, CatalogScan scan) {
    return <Widget>[
      _Notice(
        accent: DeliveryAccent.critical,
        icon: Icons.error_outline,
        title: _failureText(t, scan.failure),
        body: scan.canRetry ? null : t.blitzNoRetriesLeft,
      ),
      const SizedBox(height: DeliverySpacing.md),
      if (scan.canRetry)
        _PrimaryButton(
          icon: Icons.refresh,
          label: t.tryAgain,
          busy: _requestingAnalysis,
          onPressed: _requestingAnalysis ? null : _analyze,
        )
      else
        _PrimaryButton(icon: Icons.add_a_photo_outlined, label: t.blitzNewScan, onPressed: _reset),
    ];
  }

  static String _failureText(DeliveryStrings t, ScanFailure? failure) {
    switch (failure) {
      case ScanFailure.refused:
        return t.blitzFailedRefused;
      case ScanFailure.unreadablePhoto:
        return t.blitzFailedUnreadable;
      case ScanFailure.providerError:
        return t.blitzFailedProvider;
      case ScanFailure.busy:
        return t.blitzFailedBusy;
      case ScanFailure.interrupted:
        return t.blitzFailedInterrupted;
      case ScanFailure.unknown:
      case null:
        return t.blitzFailedOther;
    }
  }
}

// ---------------------------------------------------------------- parts

/// The frame's progress strip: three step names over a track.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.step, required this.allDone});

  /// 1-based: the step the merchant is on.
  final int step;

  /// All three are behind the merchant.
  final bool allDone;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final List<String> names = <String>[t.blitzStepScan, t.blitzStepCheck, t.blitzStepSave];

    return Container(
      decoration: const BoxDecoration(
        color: DeliveryColors.white,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(
        DeliverySpacing.md,
        DeliverySpacing.sm + DeliverySpacing.xs,
        DeliverySpacing.md,
        DeliverySpacing.sm + DeliverySpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: DeliverySpacing.md,
            runSpacing: DeliverySpacing.xs,
            children: <Widget>[
              for (int i = 0; i < names.length; i++)
                _StepName(
                  name: names[i],
                  done: allDone || i + 1 < step,
                  current: !allDone && i + 1 == step,
                ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.sm),
          YdStepper(step: allDone ? names.length : step, totalSteps: names.length, trackHeight: 6),
        ],
      ),
    );
  }
}

class _StepName extends StatelessWidget {
  const _StepName({required this.name, required this.done, required this.current});

  final String name;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    // The strong green is for glyphs; words take the darker shade that stays readable on white.
    final Color color = done
        ? DeliveryAccent.positive.onTint
        : (current ? DeliveryColors.brand : DeliveryColors.faint);
    final FontWeight weight =
        done ? FontWeight.w700 : (current ? FontWeight.w600 : FontWeight.w500);

    return Semantics(
      label: done ? t.blitzStepDone(name) : (current ? t.blitzStepCurrent(name) : name),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(name, style: TextStyle(fontSize: 12, fontWeight: weight, color: color)),
          if (done) ...<Widget>[
            const SizedBox(width: 2),
            Icon(Icons.check_rounded, size: 14, color: color),
          ],
        ],
      ),
    );
  }
}

/// The photo card: the shelf, the four corner brackets, the tags and — while reading — the sweep.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.height,
    required this.image,
    required this.semanticLabel,
    required this.lines,
    required this.tagFor,
    required this.analyzing,
    required this.sweep,
  });

  final double height;
  final ImageProvider? image;
  final String semanticLabel;
  final List<ScanLine> lines;
  final String Function(ScanLine line) tagFor;
  final bool analyzing;
  final Animation<double> sweep;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? photo = image;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        child: SizedBox(
          height: height,
          child: ColoredBox(
            color: DeliveryColors.shellDeep,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (photo == null)
                  const Center(
                    child: Icon(Icons.photo_camera_outlined,
                        size: 48, color: DeliveryColors.onShellMuted),
                  )
                else
                  _PhotoWithTags(image: photo, lines: lines, tagFor: tagFor),
                const IgnorePointer(child: CustomPaint(painter: _CornerBrackets())),
                if (analyzing) IgnorePointer(child: _Sweep(animation: sweep)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo at its own aspect ratio, with each tag at the place the reader said the product is.
///
/// Contained, never cropped: a box is a fraction of the WHOLE photo, so a cover-fit that trims the
/// edges would put every tag somewhere the product is not. The size is read off the decoded image
/// before any tag is drawn for the same reason.
class _PhotoWithTags extends StatefulWidget {
  const _PhotoWithTags({required this.image, required this.lines, required this.tagFor});

  final ImageProvider image;
  final List<ScanLine> lines;
  final String Function(ScanLine line) tagFor;

  @override
  State<_PhotoWithTags> createState() => _PhotoWithTagsState();
}

class _PhotoWithTagsState extends State<_PhotoWithTags> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _size;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_PhotoWithTags oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _size = null;
      _resolve();
    }
  }

  void _resolve() {
    final ImageStream stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stopListening();
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!mounted) return;
        setState(() => _size = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      },
      onError: (Object _, StackTrace? __) {},
    );
    _listener = listener;
    _stream = stream..addListener(listener);
  }

  void _stopListening() {
    final ImageStreamListener? listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size? size = _size;
    if (size == null || size.isEmpty) {
      return Image(image: widget.image, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final double w = box.maxWidth;
            final double h = box.maxHeight;
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Image(image: widget.image, fit: BoxFit.fill, gaplessPlayback: true),
                ),
                for (final ScanLine line in widget.lines)
                  // Physical, not directional: the reader's box is measured from the photo's own
                  // left edge, which does not move when the interface is in Arabic.
                  Positioned(
                    left: (line.box!.left * w).clamp(0, (w - 48).clamp(0, w)).toDouble(),
                    top: (line.box!.top * h).clamp(0, (h - 28).clamp(0, h)).toDouble(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: (w - line.box!.left * w).clamp(48, w).toDouble(),
                      ),
                      child: _Tag(label: widget.tagFor(line)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A detection tag: a dark pill, a green dot, the name and the price guess.
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DeliveryColors.shellDeep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
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
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame's four white 3px corner brackets.
class _CornerBrackets extends CustomPainter {
  const _CornerBrackets();

  static const double _inset = 20;
  static const double _arm = 40;
  static const double _radius = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = DeliveryColors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final double l = _inset;
    final double t = _inset;
    final double r = size.width - _inset;
    final double b = size.height - _inset;

    Path corner(double x, double y, double dx, double dy) => Path()
      ..moveTo(x, y + dy * _arm)
      ..lineTo(x, y + dy * _radius)
      ..arcToPoint(Offset(x + dx * _radius, y),
          radius: const Radius.circular(_radius), clockwise: dx * dy > 0)
      ..lineTo(x + dx * _arm, y);

    canvas
      ..drawPath(corner(l, t, 1, 1), paint)
      ..drawPath(corner(r, t, -1, 1), paint)
      ..drawPath(corner(l, b, 1, -1), paint)
      ..drawPath(corner(r, b, -1, -1), paint);
  }

  @override
  bool shouldRepaint(_CornerBrackets oldDelegate) => false;
}

/// The scan line, moving down and back while the reader works.
class _Sweep extends StatelessWidget {
  const _Sweep({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) => Align(
        alignment: Alignment(0, -0.8 + 1.6 * animation.value),
        child: child,
      ),
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
        decoration: BoxDecoration(
          color: DeliveryColors.brand,
          boxShadow: <BoxShadow>[
            BoxShadow(color: DeliveryColors.brand.withValues(alpha: 0.6), blurRadius: 8),
          ],
        ),
      ),
    );
  }
}

/// The frame's green "scan complete" row with the item count on the end.
class _CompleteBanner extends StatelessWidget {
  const _CompleteBanner({required this.title, required this.count});

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    final Color words = DeliveryAccent.positive.onTint;
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: DeliveryAccent.positive.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.bolt_rounded, size: 18, color: DeliveryAccent.positive.color),
          const SizedBox(width: DeliverySpacing.xs),
          Expanded(
            child: Text(title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: words)),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Text(count,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: DeliveryColors.ink)),
        ],
      ),
    );
  }
}

/// A tinted note: a failure, the sample warning, the reader at work.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.accent,
    required this.icon,
    this.title,
    this.body,
    this.busy = false,
  });

  final DeliveryAccent accent;
  final IconData icon;
  final String? title;
  final String? body;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DeliverySpacing.md),
      decoration: BoxDecoration(
        color: accent.tint,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (busy)
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent.onTint),
            )
          else
            Icon(icon, size: 18, color: accent.onTint),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null)
                  Text(title!,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700, color: accent.onTint)),
                if (title != null && body != null) const SizedBox(height: 2),
                if (body != null)
                  Text(body!, style: const TextStyle(fontSize: 13, color: DeliveryColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame's "Zero Manual Entry Required" block, with honest words in it.
class _Explainer extends StatelessWidget {
  const _Explainer({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: DeliveryColors.ink)),
        const SizedBox(height: DeliverySpacing.xs),
        Text(body, style: const TextStyle(fontSize: 13, height: 1.4, color: DeliveryColors.muted)),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({this.label, this.value});

  final String? label;

  /// Null draws the indeterminate bar.
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(label!, style: const TextStyle(fontSize: 13, color: DeliveryColors.muted)),
          const SizedBox(height: DeliverySpacing.xs),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            color: DeliveryColors.brand,
            backgroundColor: DeliveryColors.border,
          ),
        ),
      ],
    );
  }
}

/// The frame's full-width brand CTA: the theme's 12px-radius button, not the customer pill.
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(label, textAlign: TextAlign.center);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 6),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (icon == null
                ? text
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 18),
                      const SizedBox(width: DeliverySpacing.sm),
                      Flexible(child: text),
                    ],
                  )),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onPressed,
    required this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// The server's own sentence for a refusal when it sent one, else [fallback].
String _messageFor(Object error, {required String fallback}) {
  if (error is DioException) {
    final Object? body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final String? detail = body['detail'] as String?;
      final String? correlationId = body['correlationId'] as String?;
      if (detail != null) {
        return correlationId == null ? detail : '$detail (ref: $correlationId)';
      }
    }
  }
  return fallback;
}

/// The shortest true sentence about a picker failure, for a snackbar.
String _reasonFrom(Object e) {
  final String text = e is DioException ? (e.message ?? e.type.name) : e.toString();
  return text.length > 140 ? '${text.substring(0, 140)}…' : text;
}

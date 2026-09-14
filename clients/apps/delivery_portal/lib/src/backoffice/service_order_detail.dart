import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';
import 'services_admin_parts.dart';

/// A service order's own part of the orders ledger's detail: the one line of work (packs × unit,
/// options, instructions), how the customer gets it, when the work is promised, the steps the order
/// has taken, and the customer's files.
///
/// The files are read through back office's audited read: order-manager writes one record per file
/// whose link it hands to a back-office account, in the same transaction as the links. So the list is
/// not fetched when the order opens — that would record a read of a document nobody asked to see — but
/// when the operator asks, under a notice saying that asking is recorded. Opening a file says so again.
class ServiceOrderDetail extends StatefulWidget {
  const ServiceOrderDetail({
    super.key,
    required this.order,
    required this.orderApi,
    required this.attachmentApi,
    required this.openLink,
  });

  final DeliveryOrder order;
  final OrderApi orderApi;

  /// Null in a build without the attachment client; the files block then does not draw.
  final OrderAttachmentApi? attachmentApi;

  /// Opens a file's short-lived link in a new browser tab. A parameter so a test can see what opened.
  final void Function(String url) openLink;

  @override
  State<ServiceOrderDetail> createState() => _ServiceOrderDetailState();
}

class _ServiceOrderDetailState extends State<ServiceOrderDetail> {
  late final Future<List<OrderStatusChange>> _history =
      widget.orderApi.statusHistory(widget.order.id);

  /// Null until the operator asks for the files: asking is the audited read.
  List<OrderAttachment>? _files;
  bool _filesLoading = false;
  Object? _filesError;

  /// The file last opened, which carries the "recorded" line.
  String? _opened;

  Future<List<OrderAttachment>?> _readFiles() async {
    final OrderAttachmentApi? api = widget.attachmentApi;
    if (api == null) return null;
    setState(() {
      _filesLoading = true;
      _filesError = null;
    });
    try {
      final List<OrderAttachment> files = await api.forOrder(widget.order.id);
      if (!mounted) return null;
      setState(() {
        _files = files;
        _filesLoading = false;
      });
      return files;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _filesError = e;
        _filesLoading = false;
      });
      return null;
    }
  }

  Future<void> _open(OrderAttachment file) async {
    OrderAttachment current = file;
    // A link that has run out is asked for again — a second read, recorded like the first, as the
    // notice above says — rather than handed to the browser to fail.
    if (file.isExpiredAt(DateTime.now())) {
      final List<OrderAttachment>? again = await _readFiles();
      final OrderAttachment? fresh =
          again?.where((OrderAttachment f) => f.fileId == file.fileId).firstOrNull;
      if (fresh == null || !mounted) return;
      current = fresh;
    }
    widget.openLink(current.url);
    setState(() => _opened = current.fileId);
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final DeliveryOrder o = widget.order;
    final ServiceOrderLine? line = o.serviceLine;
    final OrderLine? item =
        o.items.where((OrderLine l) => l.service != null).firstOrNull ?? o.items.firstOrNull;
    final ServiceCategory? category = o.serviceCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Fact(
          label: t.svcBoDetailKind,
          value: category == null ? t.svcBoServiceTag : t.svcBoKindServiceIn(category.labelIn(t)),
        ),
        _Fact(label: t.svcBoDetailService, value: _lineText(t, item, line)),
        if (item?.optionsSummary != null)
          _Fact(label: t.svcBoDetailOptions, value: item!.optionsSummary!),
        if (line?.instructionsPrompt != null)
          _Fact(label: t.svcBoTermPrompt, value: line!.instructionsPrompt!),
        _Fact(
          label: t.svcBoDetailInstructions,
          value: line?.instructions ?? t.svcBoNoInstructions,
        ),
        _Fact(
          label: t.svcBoTermFulfilment,
          value: switch (o.fulfilment) {
            Fulfilment.pickup => t.svcBoFulfilPickup,
            Fulfilment.delivery => t.svcBoFulfilDelivery,
            Fulfilment.unknown => t.svcBoTermUnknown,
          },
        ),
        // The server's stamp — acceptance plus the offer's longest turnaround — or a dash until the
        // provider accepts. Never hours added up here.
        _Fact(
          label: t.svcBoDetailReadyBy,
          value: o.estimatedReadyAt == null ? '—' : localMoment(context, o.estimatedReadyAt!),
        ),
        const SizedBox(height: DeliverySpacing.sm),
        Text(t.svcBoHistoryTitle, style: ConsoleText.fieldLabel),
        const SizedBox(height: DeliverySpacing.sm),
        FutureBuilder<List<OrderStatusChange>>(
          future: _history,
          builder: (BuildContext context, AsyncSnapshot<List<OrderStatusChange>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator(color: DeliveryColors.brand);
            }
            if (snapshot.hasError) {
              return Text(t.svcBoHistoryFailed, style: ConsoleText.cellMuted);
            }
            final List<OrderStatusChange> steps = snapshot.data!;
            if (steps.isEmpty) {
              return Text(t.svcBoHistoryNone, style: ConsoleText.cellMuted);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final OrderStatusChange step in steps)
                  _Step(
                    label: serviceStepLabel(t, step.status,
                        pickup: o.isPickup, cancelReason: step.note),
                    note: _stepNote(t, step),
                    at: step.changedAt == null ? null : localMoment(context, step.changedAt!),
                  ),
              ],
            );
          },
        ),
        if (widget.attachmentApi != null) ...<Widget>[
          const SizedBox(height: DeliverySpacing.md),
          Text(t.svcBoFilesTitle, style: ConsoleText.fieldLabel),
          const SizedBox(height: DeliverySpacing.sm),
          _filesBlock(t, line),
        ],
      ],
    );
  }

  Widget _filesBlock(DeliveryStrings t, ServiceOrderLine? line) {
    if (line?.attachmentPolicy == ServiceAttachmentPolicy.none) {
      return Text(t.svcBoFilesNotTaken, style: ConsoleText.cellMuted);
    }
    final List<OrderAttachment>? files = _files;
    final Object? error = _filesError;
    final int? refused = error == null ? null : refusalStatus(error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ServicesNote(text: t.svcBoFilesAuditNotice, icon: Icons.visibility_outlined),
        const SizedBox(height: DeliverySpacing.sm),
        if (_filesLoading)
          const LinearProgressIndicator(color: DeliveryColors.brand)
        else if (error != null) ...<Widget>[
          Text(
            switch (refused) {
              403 || 404 => t.svcBoFilesRefused,
              503 => t.svcBoFilesUnavailable,
              _ => t.svcBoFilesFailed,
            },
            style: TextStyle(fontSize: 13, color: DeliveryAccent.critical.color),
          ),
          // A refusal is not changed by asking again; anything else may be.
          if (refused != 403 && refused != 404) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConsoleButton(
                label: t.svcBoFilesShow,
                tone: ConsoleButtonTone.outlined,
                onPressed: () => unawaited(_readFiles()),
              ),
            ),
          ],
        ] else if (files == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConsoleButton(
              label: t.svcBoFilesShow,
              icon: Icons.folder_open_outlined,
              tone: ConsoleButtonTone.outlined,
              onPressed: () => unawaited(_readFiles()),
            ),
          )
        else if (files.isEmpty)
          Text(t.svcBoFilesEmpty, style: ConsoleText.cellMuted)
        else
          for (final OrderAttachment file in files) _fileRow(t, file),
      ],
    );
  }

  Widget _fileRow(DeliveryStrings t, OrderAttachment file) {
    final String type = file.isPdf
        ? t.svcBoFilePdf
        : file.isImage
            ? t.svcBoFileImage
            : t.svcBoFileOther;
    final int? bytes = file.sizeBytes;
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                file.isPdf
                    ? Icons.picture_as_pdf_outlined
                    : file.isImage
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                size: 18,
                color: DeliveryColors.muted,
              ),
              const SizedBox(width: DeliverySpacing.sm),
              Expanded(
                child: Text(
                  <String>[type, if (bytes != null) _size(t, bytes)].join(' · '),
                  style: ConsoleText.body,
                ),
              ),
              ConsoleButton(
                label: t.svcBoFileOpen,
                icon: Icons.open_in_new,
                onPressed: _filesLoading ? null : () => unawaited(_open(file)),
              ),
            ],
          ),
          if (_opened == file.fileId) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            ServicesNote(
              text: t.svcBoFileOpened,
              icon: Icons.check_circle_outline,
              accent: DeliveryAccent.positive,
            ),
          ],
        ],
      ),
    );
  }

  static String _lineText(DeliveryStrings t, OrderLine? item, ServiceOrderLine? line) {
    final String quantity = line == null
        ? '—'
        : line.unitLabel != null
            ? t.svcBoPacksOfUnits(line.packs, line.unitSize, line.unitLabel!)
            : line.unitSize > 1
                ? t.svcBoPacksOf(line.packs, line.unitSize)
                : t.svcBoPackUnits(line.packs);
    return item == null ? quantity : '${item.productName} — $quantity';
  }

  static String _size(DeliveryStrings t, int bytes) => bytes >= 1024 * 1024
      ? t.svcBoSizeMb((bytes / (1024 * 1024)).toStringAsFixed(1))
      : t.svcBoSizeKb((bytes / 1024).ceil().toString());

  /// What a step recorded, as a reader should see it: a decline's reason in the reader's language, the
  /// shop's own words after a not-collected cancel, or the server's sentence as written.
  static String? _stepNote(DeliveryStrings t, OrderStatusChange step) {
    final String? note = step.note?.trim();
    if (note == null || note.isEmpty) return null;
    final DeclineReason? declined = DeclineReason.fromCancelReason(note);
    if (declined != null) return declined.labelIn(t);
    if (note.toUpperCase().startsWith(DeliveryOrder.notCollectedCancelReason)) {
      final String rest = note.substring(DeliveryOrder.notCollectedCancelReason.length).trim();
      final String words = rest.startsWith(':') ? rest.substring(1).trim() : '';
      return words.isEmpty ? null : words;
    }
    return note;
  }
}

/// A service order's status in the words its kind uses: in production rather than preparing, ready for
/// pickup or for delivery, collected rather than delivered, and a decline or a never-collected pickup
/// named as what it was.
String serviceStepLabel(
  DeliveryStrings t,
  OrderStatus status, {
  required bool pickup,
  String? cancelReason,
}) =>
    switch (status) {
      OrderStatus.placed => t.svcBoStatusPlaced,
      OrderStatus.accepted => t.svcBoStatusAccepted,
      OrderStatus.preparing => t.svcBoStatusInProduction,
      OrderStatus.ready => pickup ? t.svcBoStatusReadyPickup : t.svcBoStatusReadyDelivery,
      OrderStatus.pickedUp => t.svcBoStatusOnTheWay,
      OrderStatus.delivered => pickup ? t.svcBoStatusCollected : t.svcBoStatusDelivered,
      OrderStatus.cancelled => DeclineReason.fromCancelReason(cancelReason) != null
          ? t.svcBoStatusDeclined
          : (cancelReason ?? '').trim().toUpperCase().startsWith(DeliveryOrder.notCollectedCancelReason)
              ? t.svcBoStatusNotCollected
              : t.svcBoStatusCancelled,
    };

/// [serviceStepLabel] for where the order stands now.
String serviceOrderStatusLabel(DeliveryStrings t, DeliveryOrder order) =>
    serviceStepLabel(t, order.status, pickup: order.isPickup, cancelReason: order.cancelReason);

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 130, child: Text(label, style: ConsoleText.controlLabel)),
          Expanded(child: Text(value, style: ConsoleText.body)),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, this.note, this.at});

  final String label;
  final String? note;
  final String? at;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 8, color: DeliveryColors.brand),
          ),
          const SizedBox(width: DeliverySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: ConsoleText.cellStrong),
                if (note != null) Text(note!, style: ConsoleText.body),
                if (at != null) Text(at!, style: ConsoleText.meta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

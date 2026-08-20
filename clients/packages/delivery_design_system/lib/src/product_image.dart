import 'package:flutter/material.dart';

import 'tokens.dart';

/// A product photo, with all four states it can actually be in.
///
/// Product images are served from MinIO through presigned GET URLs, which means three things this
/// widget has to handle and a plain [Image.network] does not:
///
///  * **There may be no image.** A DRAFT product has none until the merchant uploads one, and that
///    is a normal state, not an error — Phase 1 refuses to publish without one precisely because
///    the gap is expected until then.
///  * **The URL expires.** Presigned links are short-lived by design (Section 5). A stale one must
///    degrade to a placeholder, never to a red error box or an exception.
///  * **It loads over the network.** On a catalog grid that is a dozen requests at once, so an
///    unstyled gap while they arrive looks broken.
///
/// Shared between the Merchant Portal and the Backoffice so a product looks the same in both. The
/// two screens had drifted to a 56px `ListTile` thumbnail in one and an 84px square in the other.
class DeliveryProductImage extends StatelessWidget {
  const DeliveryProductImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.onTap,
  });

  final String? url;
  final double? height;
  final double? width;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Tapping opens the full-size preview. Null leaves the image inert.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = borderRadius ?? BorderRadius.circular(DeliveryRadius.md);

    Widget content;
    if (url == null || url!.isEmpty) {
      content = const _Placeholder(
        icon: Icons.image_outlined,
        label: 'No photo',
      );
    } else {
      content = Image.network(
        url!,
        fit: fit,
        width: width,
        height: height,
        loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) {
          if (progress == null) {
            return child;
          }
          return _Placeholder(
            icon: Icons.image_outlined,
            label: null,
            // Determinate where the server sent a length, indeterminate otherwise — a bar stuck at
            // zero reads as broken.
            progress: progress.expectedTotalBytes == null
                ? null
                : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
          );
        },
        // Covers an expired presigned URL, a deleted object and an offline client alike. The user
        // cannot act differently on any of them, so they get one honest message.
        errorBuilder: (_, __, ___) => const _Placeholder(
          icon: Icons.broken_image_outlined,
          label: 'Image unavailable',
        ),
      );
    }

    final Widget framed = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: DeliveryColors.background,
        border: Border.all(color: DeliveryColors.border),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (onTap == null) {
      return framed;
    }

    return Semantics(
      button: true,
      label: 'Open full-size photo',
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: framed,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, this.label, this.progress});

  final IconData icon;
  final String? label;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: DeliveryColors.muted, size: 28),
          if (progress != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.sm),
            SizedBox(
              width: 64,
              child: LinearProgressIndicator(value: progress, minHeight: 3),
            ),
          ],
          if (label != null) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              label!,
              style: const TextStyle(fontSize: 11, color: DeliveryColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens a product's photos full size.
///
/// Takes the whole list rather than one URL because a product can carry several images, and seeing
/// only the first defeats the point of a preview — the second photo is usually the one that shows
/// whether the listing is right.
Future<void> showProductImagePreview(
  BuildContext context, {
  required List<String> urls,
  String? title,
  int initialIndex = 0,
}) {
  if (urls.isEmpty) {
    return Future<void>.value();
  }
  return showDialog<void>(
    context: context,
    // Dismissing by tapping outside matters here: the dialog is nearly full-bleed, so the close
    // button is not always where a hand expects it.
    barrierDismissible: true,
    builder: (BuildContext context) => _ImagePreviewDialog(
      urls: urls,
      title: title,
      initialIndex: initialIndex.clamp(0, urls.length - 1),
    ),
  );
}

class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({
    required this.urls,
    required this.initialIndex,
    this.title,
  });

  final List<String> urls;
  final int initialIndex;
  final String? title;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  late int _index = widget.initialIndex;

  void _step(int delta) {
    setState(() {
      _index = (_index + delta) % widget.urls.length;
      if (_index < 0) {
        _index += widget.urls.length;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final bool multiple = widget.urls.length > 1;

    return Dialog(
      insetPadding: const EdgeInsets.all(DeliverySpacing.lg),
      child: ConstrainedBox(
        // Bounded to the viewport so a large photo cannot push the dialog off screen.
        constraints: BoxConstraints(
          maxWidth: screen.width * 0.9,
          maxHeight: screen.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  DeliverySpacing.md, DeliverySpacing.sm, DeliverySpacing.sm, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.title ?? 'Photo',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (multiple)
                    Text('${_index + 1} of ${widget.urls.length}',
                        style: const TextStyle(color: DeliveryColors.muted)),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                child: Row(
                  children: <Widget>[
                    if (multiple)
                      IconButton(
                        onPressed: () => _step(-1),
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Previous',
                      ),
                    Expanded(
                      child: InteractiveViewer(
                        // Zoom, because the reason to open a full-size photo is usually to read
                        // something small in it — a label, a price sticker, a damaged corner.
                        maxScale: 4,
                        child: DeliveryProductImage(
                          url: widget.urls[_index],
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (multiple)
                      IconButton(
                        onPressed: () => _step(1),
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Next',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

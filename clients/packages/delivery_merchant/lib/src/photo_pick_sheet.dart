/// The sheet a camera icon opens: where the photo comes from, and where it goes.
///
/// One sheet for every photo the platform reads on the spot — a customer's search by photo and a
/// merchant's find in their own catalogue — so both say the same thing about the photo, in the same
/// words, every time: that it is sent to Anthropic to recognise the product and not kept. The line is
/// on the sheet itself, before the photo is taken, with no extra tap to reach it.
library;

import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'photo_source.dart';

/// Where the user chose to get the photo from.
enum PhotoPick { camera, gallery }

/// Opens the sheet over [context], then the camera or the picker the user chose, and returns the
/// photo, or null when they backed out anywhere along the way.
///
/// "Take photo" is drawn only when [source] can use a camera — a phone, never the web — and "Choose
/// photo" always. A camera or picker that fails to open says so in a snack bar rather than doing
/// nothing, which would read as a dead button.
Future<PickedShelfPhoto?> pickPhotoToRead(
  BuildContext context, {
  required ShelfPhotoSource source,
  required String title,
  String? message,
  int? photosLeft,
}) async {
  final DeliveryStrings t = DeliveryStrings.of(context);
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final PhotoPick? choice = await showModalBottomSheet<PhotoPick>(
    context: context,
    backgroundColor: DeliveryColors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext _) => PhotoPickSheet(
        title: title,
        message: message,
        canUseCamera: source.canUseCamera,
        photosLeft: photosLeft),
  );
  switch (choice) {
    case null:
      return null;
    case PhotoPick.camera:
      try {
        return await source.takePhoto();
      } catch (e) {
        debugPrint('PHOTO CAMERA FAILED: $e');
        messenger?.showSnackBar(SnackBar(content: Text(t.blitzCameraFailed)));
        return null;
      }
    case PhotoPick.gallery:
      try {
        return await source.choosePhoto(label: t.images);
      } catch (e) {
        debugPrint('PHOTO PICKER FAILED: $e');
        messenger?.showSnackBar(SnackBar(content: Text(t.couldNotOpenPicker('$e'))));
        return null;
      }
  }
}

/// The sheet's body: a title, an optional line about what happens next, the two ways to get a
/// photo, and the consent line. Pops with the [PhotoPick] chosen.
class PhotoPickSheet extends StatelessWidget {
  const PhotoPickSheet({
    super.key,
    required this.title,
    required this.canUseCamera,
    this.message,
    this.photosLeft,
  });

  final String title;
  final String? message;

  /// Whether to offer "Take photo". False on the web and on desktops, where there is no camera to
  /// open.
  final bool canUseCamera;

  /// How many photos the server says this account has left today, drawn under the buttons as Merchant
  /// Blitz draws its own count. Null when the caller has no count to give, and then nothing is drawn:
  /// a photo read is a few cents of somebody else's money, and a number nobody checked is worse than
  /// no number.
  final int? photosLeft;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: DeliveryColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DeliveryColors.ink,
                height: 1.25,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.xs),
              Text(
                message!,
                style: const TextStyle(fontSize: 13, color: DeliveryColors.muted, height: 1.4),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            if (canUseCamera) ...<Widget>[
              YdPillButton(
                label: t.psrchTakePhoto,
                icon: Icons.photo_camera_outlined,
                onPressed: () => Navigator.of(context).pop(PhotoPick.camera),
              ),
              const SizedBox(height: DeliverySpacing.sm),
            ],
            YdPillButton.secondary(
              label: t.psrchChoosePhoto,
              icon: Icons.photo_library_outlined,
              onPressed: () => Navigator.of(context).pop(PhotoPick.gallery),
            ),
            if (photosLeft != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Text(
                t.psrchLeftToday(photosLeft!),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
              ),
            ],
            const SizedBox(height: DeliverySpacing.md),
            PhotoConsentLine(text: t.psrchConsent),
          ],
        ),
      ),
    );
  }
}

/// The line that says where a photo goes, drawn the same wherever a photo is read.
class PhotoConsentLine extends StatelessWidget {
  const PhotoConsentLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsetsDirectional.only(top: 1),
          child: Icon(Icons.lock_outline, size: 16, color: DeliveryColors.muted),
        ),
        const SizedBox(width: DeliverySpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: DeliveryColors.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}

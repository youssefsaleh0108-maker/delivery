/// Where photos come from: the camera on a phone, the gallery or the file system everywhere.
///
/// Merchant Blitz's shelf photos first, and now every photo the platform reads: a customer's search by
/// photo and a merchant's find in their own catalogue. One seam for all of them, so the rules about a
/// camera that exists only on a phone, the types the server can read, and the photo Android hands back
/// after it destroyed the app live in one place.
library;

import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:file_selector/file_selector.dart' show XFile, XTypeGroup, openFile, openFiles;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource, LostDataResponse;

/// One photo as it was picked, before anything has been sent.
class PickedShelfPhoto {
  const PickedShelfPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;

  /// `image/jpeg` or `image/png` — the only types the server can decode and read.
  final String contentType;
}

/// Where photos come from.
///
/// A seam rather than calls to the plugins inline, for two reasons. The camera exists only on a
/// phone, so a screen has to ask whether to draw "Take photo" at all rather than draw a button that
/// cannot work on the web. And a widget test cannot drive a platform picker, so the tests hand the
/// screen photos directly through this.
abstract class ShelfPhotoSource {
  const ShelfPhotoSource();

  /// Whether this device can take a photo. False on the web and on desktops.
  bool get canUseCamera;

  /// One photo from the camera, or null when the user backed out.
  Future<PickedShelfPhoto?> takePhoto();

  /// Photos from the gallery or the file system — several at once, one per shelf. Empty when the
  /// user backed out.
  Future<List<PickedShelfPhoto>> choosePhotos({required String label});

  /// One photo from the gallery or the file system, for a search that reads one: null when the user
  /// backed out. The first of [choosePhotos] unless a source can open a single-photo picker.
  Future<PickedShelfPhoto?> choosePhoto({required String label}) async {
    final List<PickedShelfPhoto> photos = await choosePhotos(label: label);
    return photos.isEmpty ? null : photos.first;
  }

  /// A photo the camera took while Android had destroyed this app, handed back once, the next time
  /// the flow starts. Null when there is none, and everywhere but Android.
  ///
  /// Android may destroy the app's activity — often its whole process — while the camera app is in
  /// front, and memory is shortest on exactly the phones shops use. The photo is still taken and the
  /// picker keeps it for the app to ask for once it runs again; if nothing asks, it is gone.
  Future<PickedShelfPhoto?> retrieveLostPhoto() async => null;
}

/// The real device: image_picker's camera on a phone, file_selector everywhere for the gallery.
class DeviceShelfPhotoSource extends ShelfPhotoSource {
  /// [cameraMaxEdge] is the long edge the camera is asked for. A shelf photo's default sits a little
  /// above the 2236 px the server sends its reader (the most of a 4:3 photo Claude reads at full
  /// detail), so the server only ever shrinks; a photo search asks for its own 1568 px
  /// ([StoreApi.photoSearchMaxEdge]), which is all its reader reads.
  const DeviceShelfPhotoSource({this.cameraMaxEdge = CatalogScanApi.shelfPhotoMaxEdge});

  final int cameraMaxEdge;

  /// The types a picker offers: what the server's decoder reads. Anything else would be refused by
  /// the server after the user had already waited for it.
  static const List<String> _extensions = <String>['jpg', 'jpeg', 'png'];
  static const List<String> _mimeTypes = <String>['image/jpeg', 'image/png'];

  @override
  bool get canUseCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<PickedShelfPhoto?> takePhoto() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: cameraMaxEdge.toDouble(),
      maxHeight: cameraMaxEdge.toDouble(),
      // Re-encoding at this quality also turns an iPhone's HEIC into a JPEG the server can read.
      imageQuality: 88,
    );
    if (file == null) return null;
    return PickedShelfPhoto(bytes: await file.readAsBytes(), contentType: _typeOf(file));
  }

  @override
  Future<List<PickedShelfPhoto>> choosePhotos({required String label}) async {
    final List<XFile> files = await openFiles(acceptedTypeGroups: <XTypeGroup>[
      XTypeGroup(label: label, extensions: _extensions, mimeTypes: _mimeTypes),
    ]);
    final List<PickedShelfPhoto> picked = <PickedShelfPhoto>[];
    for (final XFile file in files) {
      picked.add(PickedShelfPhoto(bytes: await file.readAsBytes(), contentType: _typeOf(file)));
    }
    return picked;
  }

  @override
  Future<PickedShelfPhoto?> choosePhoto({required String label}) async {
    final XFile? file = await openFile(acceptedTypeGroups: <XTypeGroup>[
      XTypeGroup(label: label, extensions: _extensions, mimeTypes: _mimeTypes),
    ]);
    if (file == null) return null;
    return PickedShelfPhoto(bytes: await file.readAsBytes(), contentType: _typeOf(file));
  }

  @override
  Future<PickedShelfPhoto?> retrieveLostPhoto() async {
    // Android only: image_picker keeps lost data nowhere else, and says so by throwing.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final LostDataResponse lost = await ImagePicker().retrieveLostData();
    final XFile? file = lost.file;
    // A capture that failed comes back as an exception with no file: nothing to recover.
    if (lost.isEmpty || file == null) return null;
    return PickedShelfPhoto(bytes: await file.readAsBytes(), contentType: _typeOf(file));
  }

  static String _typeOf(XFile file) {
    final String? mime = file.mimeType;
    if (mime == 'image/png' || mime == 'image/jpeg') return mime!;
    return file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
  }
}

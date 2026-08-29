import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A picked image, made ready to upload.
///
/// The picker hands back whatever the phone's camera or gallery produced — often several megabytes
/// of JPEG at full sensor resolution. A product thumbnail is shown a few hundred pixels wide, so
/// uploading the original wastes the shopkeeper's data and the platform's storage, and on a slow
/// connection it is the difference between an upload that finishes and one that times out.
///
/// [ImagePrep.forUpload] brings an image under a byte cap the way a person would: shrink the
/// dimensions first, and only then trade quality. A photo already under the cap is returned
/// untouched, so nothing is re-compressed needlessly.
class PreparedImage {
  const PreparedImage(this.bytes, this.contentType, {required this.wasResized});

  final Uint8List bytes;

  /// Always a concrete type the server's allow-list accepts. A re-encoded image is JPEG; an
  /// untouched one keeps whatever it came in as.
  final String contentType;

  /// Whether the bytes differ from what was picked — for a caller that wants to tell the user
  /// "we shrank this to fit" rather than silently changing their file.
  final bool wasResized;
}

class ImagePrep {
  const ImagePrep._();

  /// The default ceiling for a product photo: 1 MB.
  ///
  /// Comfortably above what a 1600px JPEG needs for good quality, and far below the server's own
  /// 10 MB presign limit — so an image prepared here always fits, and a shop on mobile data is not
  /// pushing multi-megabyte originals for a picture shown 320px wide. Change this one constant to
  /// move the cap.
  static const int defaultMaxBytes = 1024 * 1024;

  /// The longest edge a prepared image is allowed to have. A product card never renders larger than
  /// this, so anything bigger is detail nobody sees carried at the uploader's expense.
  static const int maxDimension = 1600;

  /// Brings [bytes] under [maxBytes], decoding only if it has to.
  ///
  /// - Already within the cap: returned as-is, with its original [contentType], [wasResized] false.
  /// - Over the cap: downscaled so its longest edge is at most [maxDimension], then encoded as JPEG
  ///   at a quality that steps down until the result fits — or the floor is reached, at which point
  ///   the smallest attempt is returned rather than nothing, because a slightly-too-large image the
  ///   server may still accept beats refusing the upload.
  /// - Not a decodable image: returned unchanged. The server re-checks the type and will refuse a
  ///   genuinely bad file with a message the caller surfaces; guessing here would only hide that.
  static PreparedImage forUpload(
    Uint8List bytes,
    String contentType, {
    int maxBytes = defaultMaxBytes,
  }) {
    if (bytes.length <= maxBytes) {
      return PreparedImage(bytes, contentType, wasResized: false);
    }

    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // Not something the pure-Dart decoder understands. Let the server be the authority on whether
      // it is a usable image rather than dropping it here.
      return PreparedImage(bytes, contentType, wasResized: false);
    }

    // Shrink the dimensions first — the cheapest quality per byte saved. Only downscale; a small
    // image over the cap (rare, but possible for a huge PNG of a plain colour) is left at its size
    // and handled by the quality steps below.
    img.Image working = decoded;
    final int longest =
        decoded.width >= decoded.height ? decoded.width : decoded.height;
    if (longest > maxDimension) {
      if (decoded.width >= decoded.height) {
        working = img.copyResize(decoded, width: maxDimension);
      } else {
        working = img.copyResize(decoded, height: maxDimension);
      }
    }

    // Then trade quality, from good down to a floor. JPEG because it is on the server's allow-list
    // and compresses a photograph far smaller than PNG.
    Uint8List best = Uint8List.fromList(img.encodeJpg(working, quality: 85));
    if (best.length <= maxBytes) {
      return PreparedImage(best, 'image/jpeg', wasResized: true);
    }
    for (final int quality in <int>[70, 55, 40, 30]) {
      final Uint8List attempt =
          Uint8List.fromList(img.encodeJpg(working, quality: quality));
      if (attempt.length < best.length) {
        best = attempt;
      }
      if (attempt.length <= maxBytes) {
        return PreparedImage(attempt, 'image/jpeg', wasResized: true);
      }
    }
    // Everything tried is still over the cap — return the smallest. The server's presign limit is
    // ten times this cap, so this near-miss is very likely still accepted, and a slightly-large
    // upload is a better outcome than a refusal the shopkeeper cannot act on.
    return PreparedImage(best, 'image/jpeg', wasResized: true);
  }
}

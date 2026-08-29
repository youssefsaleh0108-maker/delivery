import 'dart:typed_data';

import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Bringing a picked photo under the upload cap.
///
/// The point of this util is that a shop on mobile data does not push a multi-megabyte camera
/// original for a picture shown 320px wide — so what matters is that an oversized image comes back
/// SMALLER and under the cap, that a small one is left exactly as it was, and that a non-image is
/// never silently dropped. Those are the three things a caller relies on.
void main() {
  /// A JPEG of the given size with photo-like content: smooth gradients that carry real detail but
  /// compress the way a real photograph does, so "over the cap at full res, under it once shrunk"
  /// is achievable rather than a pathological high-frequency case JPEG can never squeeze.
  Uint8List jpeg(int width, int height) {
    final img.Image image = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int r = ((x * 255) ~/ width);
        final int g = ((y * 255) ~/ height);
        final int b = (((x + y) * 255) ~/ (width + height));
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 100));
  }

  group('ImagePrep.forUpload', () {
    test('a photo already under the cap is returned untouched', () {
      final Uint8List small = jpeg(64, 64);
      expect(small.length, lessThan(200 * 1024));

      final PreparedImage out = ImagePrep.forUpload(small, 'image/png', maxBytes: 200 * 1024);

      expect(out.wasResized, isFalse);
      expect(out.bytes, same(small));
      // The type is kept, not rewritten, when nothing was re-encoded.
      expect(out.contentType, 'image/png');
    });

    test('an oversized photo is brought under the cap and comes back smaller', () {
      // A large image whose full-quality JPEG is over the cap, but whose 1600px form fits.
      final Uint8List big = jpeg(4000, 3000);
      const int cap = 120 * 1024;
      expect(big.length, greaterThan(cap));

      final PreparedImage out = ImagePrep.forUpload(big, 'image/jpeg', maxBytes: cap);

      expect(out.wasResized, isTrue);
      expect(out.bytes.length, lessThanOrEqualTo(cap));
      expect(out.bytes.length, lessThan(big.length));
      // A re-encoded image is JPEG whatever it started as.
      expect(out.contentType, 'image/jpeg');
    });

    test('the longest edge is capped, so oversized detail is not carried', () {
      final Uint8List big = jpeg(4000, 1000);

      final PreparedImage out = ImagePrep.forUpload(big, 'image/jpeg', maxBytes: 100 * 1024);

      final img.Image? decoded = img.decodeImage(out.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(ImagePrep.maxDimension));
      expect(decoded.height, lessThanOrEqualTo(ImagePrep.maxDimension));
      // Aspect ratio is preserved: a 4:1 source stays 4:1.
      expect(decoded.width / decoded.height, closeTo(4.0, 0.05));
    });

    test('bytes that are not a decodable image are passed through, not dropped', () {
      // Over the cap, but not an image. The server is the authority on whether it is usable; this
      // must not swallow it, or a real problem would read as "nothing happened".
      final Uint8List garbage = Uint8List.fromList(List<int>.generate(300 * 1024, (int i) => i % 256));

      final PreparedImage out = ImagePrep.forUpload(garbage, 'image/jpeg', maxBytes: 100 * 1024);

      expect(out.wasResized, isFalse);
      expect(out.bytes, same(garbage));
    });
  });
}

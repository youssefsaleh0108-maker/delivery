import 'dart:convert';
import 'dart:typed_data';

/// A 40 x 20 JPEG laid out the way a phone camera writes a portrait photo: an EXIF APP1 segment
/// first, tagging Orientation 6 ("turn a quarter clockwise"), then pixels stored landscape — a dark
/// blue field with a red block in the stored top-left corner. Upright it is 20 wide and 40 tall.
///
/// Made with ImageIO and the same EXIF splice as product-service's TaggedJpeg test helper, so the
/// phone's viewfinder and the server's ExifOrientationTest are held to one and the same photo.
final Uint8List sidewaysCameraJpeg = base64Decode(
    '/9j/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8U'
    'HRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIy'
    'MjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAUACgDASIAAhEBAxEB/8QAHwAAAQUBAQEB'
    'AQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0Kx'
    'wRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJ'
    'ipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QA'
    'HwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMi'
    'MoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3'
    'eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP0'
    '9fb3+Pn6/9oADAMBAAIRAxEAPwDi80lFFe3hMsoYWbnSve1twzLiDG5lSVHENWTvora2a/UKKKK9A8MKKKKACiiigAoo'
    'ooAKKKKAP//Z');

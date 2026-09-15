/// Web half of the conditional import — see `download_file.dart`.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [content] as [fileName] through the browser's own download.
///
/// UTF-8 with a byte-order mark: without it a spreadsheet opens an Arabic rider name as mojibake,
/// and the export is read by people who will open it in exactly that spreadsheet.
void downloadTextFile(String fileName, String content, {String mimeType = 'text/csv'}) {
  final Uint8List bytes = Uint8List.fromList(utf8.encode('﻿$content'));
  final web.Blob blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}

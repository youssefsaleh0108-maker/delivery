/// Handing the reader a file their browser saves, without breaking the VM test build.
///
/// The carrier's reconciliation page exports its rider balances as CSV. On the web build that is a
/// Blob and a download link; under `flutter test` (which compiles for the VM, where `package:web`
/// does not exist) the stub does nothing, and the screens take the function as a parameter so a
/// test can capture what would have been saved instead.
library;

export 'download_file_stub.dart' if (dart.library.js_interop) 'download_file_web.dart';

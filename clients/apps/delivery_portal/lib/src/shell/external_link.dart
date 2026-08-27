/// Opening a URL in a new browser tab, without breaking the VM test build.
///
/// The document review drawers hand a reviewer a short-lived presigned GET for the paper they are
/// deciding on. On the web build that opens in a new tab; under `flutter test` (which compiles for
/// the VM, where `package:web` does not exist) the stub quietly does nothing, which is fine — the
/// tests assert the *link* is offered, not that a browser appeared.
library;

export 'external_link_stub.dart' if (dart.library.js_interop) 'external_link_web.dart';

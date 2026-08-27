/// Web half of the conditional import — see `external_link.dart`.
library;

import 'package:web/web.dart' as web;

/// Opens [url] in a new tab. Used for the presigned document GETs, which are short-lived and
/// belong in the browser's own viewer rather than embedded in the console.
void openExternalLink(String url) {
  web.window.open(url, '_blank');
}

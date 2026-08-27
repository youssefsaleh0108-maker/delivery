/// VM half of the conditional import — see `external_link.dart`.
library;

/// Does nothing off the web. The portal only ever ships as a web target; this exists so the
/// widget tests, which run on the VM, can build the screens that call it.
void openExternalLink(String url) {}

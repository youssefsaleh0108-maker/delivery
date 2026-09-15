/// VM half of the conditional import — see `download_file.dart`.
library;

/// Does nothing off the web. The portal only ships as a web target; this exists so widget tests,
/// which run on the VM, can build the screens that call it.
void downloadTextFile(String fileName, String content, {String mimeType = 'text/csv'}) {}

import 'package:flutter/widgets.dart';

/// Which language the app is in, and how that choice survives a restart.
///
/// Deliberately *not* defaulted to the device locale and left there. In Lebanon a phone set to
/// English is routinely used by someone who would rather read Arabic, and vice versa — so the
/// device is the starting guess and the user's explicit choice, once made, always wins.
///
/// Reading and writing go through a callback pair rather than a storage package, so this stays
/// dependency-free and each app persists it wherever it already keeps preferences.
class LocaleController extends ChangeNotifier {
  LocaleController({
    required Future<String?> Function() read,
    required Future<void> Function(String) write,
  })  : _read = read,
        _write = write;

  static const List<Locale> supported = <Locale>[Locale('en'), Locale('ar')];

  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;

  Locale? _locale;

  /// Null means "follow the device". MaterialApp resolves that against [supported].
  Locale? get locale => _locale;

  bool get isArabic => _locale?.languageCode == 'ar';

  Future<void> load() async {
    try {
      final String? saved = await _read();
      if (saved != null && supported.any((Locale l) => l.languageCode == saved)) {
        _locale = Locale(saved);
        notifyListeners();
      }
    } catch (_) {
      // A missing or unreadable preference just means "follow the device"; it must never stop
      // the app booting.
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (!supported.any((Locale l) => l.languageCode == languageCode)) {
      return;
    }
    _locale = Locale(languageCode);
    notifyListeners();
    try {
      await _write(languageCode);
    } catch (_) {
      // Persisting is a convenience; the switch has already taken effect for this session.
    }
  }

  /// Flips between the two supported languages — what a single toggle button calls.
  Future<void> toggle() => setLanguage(isArabic ? 'en' : 'ar');
}

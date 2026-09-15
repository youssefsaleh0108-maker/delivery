/// Lebanese phone numbers as the gift checkout takes them: the national number typed after a fixed
/// +961, normalised to the international form Order Manager accepts (`+96171234567`).
///
/// A shape check, not a registry lookup, and deliberately so. The recipient is not a platform user
/// and nothing can verify their line; what matters is that the rider is not handed a number that
/// cannot possibly ring in Lebanon — nine digits, a foreign prefix, a typo'd "0" — which is what
/// turns a gift into a parcel nobody can hand over. The shapes accepted:
///
/// * **Mobiles**, eight digits after +961 starting 70, 71, 76, 78, 79 or 81 (`71 234 567`), and the
///   older seven-digit 3 range (`3 123 456`, written domestically as 03 123 456).
/// * **Landlines**, seven digits after +961: an area code 1, 4, 5, 6, 7, 8 or 9 then six digits
///   (`1 234 567` for Beirut, written domestically as 01 234 567).
///
/// Whatever the customer pastes — `+961 71-234-567`, `0096171234567`, `03 123456` — is reduced to
/// those digits first, so the field never argues about formatting.
abstract final class LebanesePhone {
  /// Shown beside the field, never typed: the field takes the national number.
  static const String countryCode = '+961';

  static final RegExp _separators = RegExp(r'[\s\-.()]');
  static final RegExp _eightDigitMobile = RegExp(r'^(70|71|76|78|79|81)\d{6}$');
  static final RegExp _sevenDigit = RegExp(r'^[1345-9]\d{6}$');

  /// The national significant number — `71234567`, `3123456` — or null when [input] is not a
  /// Lebanese number.
  static String? nationalNumber(String input) {
    String digits = input.replaceAll(_separators, '');
    if (digits.startsWith('+961')) {
      digits = digits.substring(4);
    } else if (digits.startsWith('00961')) {
      digits = digits.substring(5);
    } else if (digits.startsWith('961') && digits.length > 9) {
      digits = digits.substring(3);
    }
    // The domestic trunk zero: 03 123 456 and 01 234 567 are the same numbers without it.
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
    if (_eightDigitMobile.hasMatch(digits) || _sevenDigit.hasMatch(digits)) return digits;
    return null;
  }

  /// `+96171234567` for anything [nationalNumber] accepts, or null.
  static String? international(String input) {
    final String? national = nationalNumber(input);
    return national == null ? null : '$countryCode$national';
  }

  /// "71 234 567" or "3 123 456": how a stored number is shown back in the field.
  static String grouped(String national) {
    final int split = national.length - 6;
    if (split < 1) return national;
    return '${national.substring(0, split)} ${national.substring(split, split + 3)} '
        '${national.substring(split + 3)}';
  }

  /// The grouped national part of a stored international number, for prefilling the field — null
  /// when there is nothing stored or it is not a Lebanese number.
  static String? prefill(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    final String? national = nationalNumber(stored);
    return national == null ? null : grouped(national);
  }
}

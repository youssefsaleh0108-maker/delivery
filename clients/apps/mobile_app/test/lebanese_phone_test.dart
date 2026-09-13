import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/lebanese_phone.dart';

/// The recipient's number is the one thing a rider needs to hand a gift over, and the recipient
/// cannot be asked to correct it. What is pinned: every way a customer writes a real Lebanese number
/// reaches the server as the one international form, and nothing that cannot ring in Lebanon does.
void main() {
  group('a Lebanese number however it is written', () {
    test('an eight-digit mobile, grouped or not', () {
      expect(LebanesePhone.international('71 234 567'), '+96171234567');
      expect(LebanesePhone.international('71234567'), '+96171234567');
      expect(LebanesePhone.international('81-234-567'), '+96181234567');
    });

    test('pasted with the country code, or the domestic trunk zero', () {
      expect(LebanesePhone.international('+961 71 234 567'), '+96171234567');
      expect(LebanesePhone.international('0096171234567'), '+96171234567');
      expect(LebanesePhone.international('96171234567'), '+96171234567');
      expect(LebanesePhone.international('03 123 456'), '+9613123456');
      expect(LebanesePhone.international('01 234 567'), '+9611234567');
    });
  });

  group('refused', () {
    test('too short, too long, or a prefix no Lebanese line has', () {
      expect(LebanesePhone.nationalNumber('12'), isNull);
      expect(LebanesePhone.nationalNumber('+961 00'), isNull);
      expect(LebanesePhone.nationalNumber('712345678'), isNull);
      expect(LebanesePhone.nationalNumber('72 234 567'), isNull);
      expect(LebanesePhone.nationalNumber('2 123 456'), isNull);
      expect(LebanesePhone.nationalNumber(''), isNull);
    });

    test('a foreign number is not read as a Lebanese one', () {
      expect(LebanesePhone.nationalNumber('+44 7700 900123'), isNull);
      expect(LebanesePhone.nationalNumber('+1 212 555 0100'), isNull);
    });
  });

  test('a stored number is shown back grouped, and a foreign one not at all', () {
    expect(LebanesePhone.prefill('+96171234567'), '71 234 567');
    expect(LebanesePhone.prefill('+9613123456'), '3 123 456');
    expect(LebanesePhone.prefill('+447700900123'), isNull);
    expect(LebanesePhone.prefill(null), isNull);
  });
}

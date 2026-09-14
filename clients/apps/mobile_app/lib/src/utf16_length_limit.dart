import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Holds a text field to [max] UTF-16 code units — what Java's `String.length()`, and so a Spring
/// `@Size`, counts — and cuts only between whole characters.
///
/// Not Flutter's `maxLength`, which counts characters as a person sees them: an emoji is one there and
/// two here, so text that field accepted could come back from the server as a 400 nobody can act on.
/// A counter beside such a field counts `text.length` for the same reason, so its figure reaches the
/// limit exactly when the field stops taking text.
///
/// The gift checkout holds its card to this rule with a private copy that predates this one; the
/// service order's instructions and a shop review's comment use this.
class Utf16LengthLimit extends TextInputFormatter {
  const Utf16LengthLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    // Already full and typed at a caret: the keystroke is refused, not the end of the text trimmed.
    if (oldValue.text.length == max && oldValue.selection.isCollapsed) return oldValue;
    final StringBuffer kept = StringBuffer();
    for (final String character in newValue.text.characters) {
      if (kept.length + character.length > max) break;
      kept.write(character);
    }
    final String text = kept.toString();
    int within(int offset) => offset > text.length ? text.length : offset;
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: within(newValue.selection.baseOffset),
        extentOffset: within(newValue.selection.extentOffset),
      ),
    );
  }
}

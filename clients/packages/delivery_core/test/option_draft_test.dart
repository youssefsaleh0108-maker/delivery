import 'package:delivery_core/delivery_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The option editor's client-side rules, which exist to mirror the server's.
///
/// They earn their place by letting the merchant be told beside the field instead of by a 400
/// after a round trip — but a mirror that drifts is worse than none, because it either blocks
/// something the server would accept or waves through something it will refuse. These pin the
/// mirror to OptionGroupRequest's actual constraints.
void main() {
  OptionGroupDraft valid() => OptionGroupDraft(
        name: 'Size',
        minSelect: 1,
        maxSelect: 1,
        options: <OptionDraft>[
          OptionDraft(name: 'Small', priceDelta: -1),
          OptionDraft(name: 'Large', priceDelta: 2),
        ],
      );

  group('what the server would accept', () {
    test('a complete group has no problem', () {
      expect(valid().problem, isNull);
    });

    test('a negative price delta is fine — "Small" may cost less', () {
      final OptionGroupDraft g = valid();
      expect(g.options.first.priceDelta, lessThan(0));
      expect(g.problem, isNull);
    });

    test('the request drops ids and sends only what the endpoint reads', () {
      final Map<String, dynamic> json = valid().toRequestJson();
      expect(json.keys, containsAll(<String>['name', 'minSelect', 'maxSelect', 'options']));
      expect(json.containsKey('id'), isFalse);
      expect((json['options'] as List<dynamic>).first, isNot(contains('id')));
    });

    test('names are trimmed, so a stray space is not a different option', () {
      final OptionGroupDraft g = OptionGroupDraft(
        name: '  Size  ',
        options: <OptionDraft>[OptionDraft(name: '  Large  ')],
      );
      final Map<String, dynamic> json = g.toRequestJson();
      expect(json['name'], 'Size');
      expect((json['options'] as List<dynamic>).first['name'], 'Large');
    });
  });

  group('what it refuses, and why', () {
    test('a group with no name', () {
      final OptionGroupDraft g = valid()..name = '   ';
      expect(g.problem, 'nameRequired');
    });

    test('a group with no options — the customer would be asked nothing', () {
      final OptionGroupDraft g = valid()..options.clear();
      expect(g.problem, 'needsAnOption');
    });

    test('an option with no name', () {
      final OptionGroupDraft g = valid()..options.first.name = '';
      expect(g.problem, 'optionNameRequired');
    });

    test('a minimum above the maximum', () {
      final OptionGroupDraft g = valid()
        ..minSelect = 2
        ..maxSelect = 1;
      expect(g.problem, 'minAboveMax');
    });

    test('a minimum no selection could satisfy', () {
      // Three required from two options: the server accepts this and the customer can then never
      // check out, because no valid selection exists. Caught here rather than at the till.
      final OptionGroupDraft g = valid()
        ..minSelect = 3
        ..maxSelect = 3;
      expect(g.problem, 'minAboveOptionCount');
    });

    test('numbers outside the range the server allows', () {
      expect((valid()..maxSelect = 51).problem, 'maxOutOfRange');
      expect((valid()..minSelect = -1).problem, 'minOutOfRange');
    });
  });

  group('reading an existing group back for editing', () {
    test('carries the values across and drops the ids', () {
      final OptionGroup existing = OptionGroup.fromJson(<String, dynamic>{
        'id': 'group-1',
        'name': 'Size',
        'minSelect': 1,
        'maxSelect': 1,
        'required': true,
        'singleChoice': true,
        'options': <dynamic>[
          <String, dynamic>{'id': 'opt-1', 'name': 'Large', 'priceDelta': 2.0, 'isDefault': true},
        ],
      });

      final OptionGroupDraft draft = OptionGroupDraft.from(existing);

      expect(draft.name, 'Size');
      expect(draft.minSelect, 1);
      expect(draft.options.single.name, 'Large');
      expect(draft.options.single.priceDelta, 2.0);
      expect(draft.options.single.isDefault, isTrue);
      // required/singleChoice are the server's to derive; a draft carries only the numbers.
      expect(draft.toRequestJson().containsKey('required'), isFalse);
      expect(draft.toRequestJson().containsKey('singleChoice'), isFalse);
    });
  });
}

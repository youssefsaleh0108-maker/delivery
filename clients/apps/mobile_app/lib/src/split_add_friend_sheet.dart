import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// One person at the table, before the server knows about the plan.
class SplitParticipant {
  const SplitParticipant({this.username, required this.name});

  /// Null = a guest with no app; their share is cash at the door by definition.
  final String? username;
  final String name;

  bool get isGuest => username == null;
}

/// The Add-to-Order sheet (Figma `add-friend-to-order` 83:161): search by username, quick-add the
/// people you split with last time, or add a guest by name for the rider to collect from.
Future<SplitParticipant?> showAddFriendSheet(
  BuildContext context, {
  required ProfileApi profileApi,
  required List<String> recentUsernames,
  required Map<String, String> recentNames,
}) {
  return showModalBottomSheet<SplitParticipant>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DeliveryColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(DeliveryRadius.sheet)),
    ),
    builder: (BuildContext ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _AddFriendSheet(
        profileApi: profileApi,
        recentUsernames: recentUsernames,
        recentNames: recentNames,
      ),
    ),
  );
}

class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet({
    required this.profileApi,
    required this.recentUsernames,
    required this.recentNames,
  });

  final ProfileApi profileApi;
  final List<String> recentUsernames;
  final Map<String, String> recentNames;

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, String>> _results = const <Map<String, String>>[];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final String q = value.trim();
      if (q.length < 2) {
        setState(() => _results = const <Map<String, String>>[]);
        return;
      }
      setState(() => _searching = true);
      try {
        final List<Map<String, String>> found = await widget.profileApi.search(q);
        if (!mounted) return;
        setState(() {
          _results = found;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final String typed = _search.text.trim();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t.custAddToOrder,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: DeliveryColors.ink,
                      height: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      size: 20, color: DeliveryColors.muted),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: _search,
              onChanged: (String v) {
                _onQuery(v);
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: t.custSearchByUsername,
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
              ),
            ),
            const SizedBox(height: DeliverySpacing.md),
            if (_searching)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(DeliverySpacing.sm),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: DeliveryColors.brand),
                  ),
                ),
              ),
            for (final Map<String, String> user in _results)
              _personRow(
                name: user['name'] ?? user['username'] ?? '',
                username: user['username'],
                action: t.add,
              ),
            // No account matched? The table still has a seat for them: a guest share the rider
            // collects in cash at the door.
            if (typed.length >= 2 && _results.isEmpty && !_searching)
              _guestRow(t, typed),
            if (widget.recentUsernames.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              Text(
                t.custRecentlySplitWith.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DeliveryColors.faint,
                  letterSpacing: 0.6,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: DeliverySpacing.sm),
              for (final String username in widget.recentUsernames.take(4))
                _personRow(
                  name: widget.recentNames[username] ?? username,
                  username: username,
                  action: t.custQuickAdd,
                ),
            ],
            const SizedBox(height: DeliverySpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _personRow({required String name, String? username, required String action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: Row(
        children: <Widget>[
          StoreMonogram(name: name, size: 40, radius: 20),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: DeliveryColors.ink,
                    height: 1.25,
                  ),
                ),
                if (username != null)
                  Text(
                    '@$username',
                    style: const TextStyle(
                        fontSize: 12, color: DeliveryColors.faint, height: 1.25),
                  ),
              ],
            ),
          ),
          YdPillButton(
            label: action,
            expand: false,
            size: YdPillButtonSize.compact,
            onPressed: () => Navigator.of(context)
                .pop(SplitParticipant(username: username, name: name)),
          ),
        ],
      ),
    );
  }

  Widget _guestRow(DeliveryStrings t, String typed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
      child: YdPillButton.secondary(
        label: t.custAddAsGuest(typed),
        onPressed: () =>
            Navigator.of(context).pop(SplitParticipant(username: null, name: typed)),
      ),
    );
  }
}

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'whatsapp_draft_panel.dart';

/// The merchant's WhatsApp inbox.
///
/// Three columns, because the job is three things at once: who is waiting, what they said, and what
/// you are going to send them. A merchant taking an order over chat is holding all three in their
/// head, and a screen that made them navigate between the message and the order would be slower
/// than the pen and paper this replaces.
class WhatsAppScreen extends StatefulWidget {
  const WhatsAppScreen({super.key, required this.api, required this.catalogApi});

  final WhatsAppApi api;
  final CatalogApi catalogApi;

  @override
  State<WhatsAppScreen> createState() => _WhatsAppScreenState();
}

class _WhatsAppScreenState extends State<WhatsAppScreen> {
  late Future<List<WhatsAppConversation>> _inbox = widget.api.inbox();
  bool _archived = false;
  WhatsAppConversation? _selected;

  void _reload({bool keepSelection = true}) {
    setState(() {
      _inbox = widget.api.inbox(archived: _archived);
      if (!keepSelection) _selected = null;
    });
  }

  Future<void> _select(WhatsAppConversation conversation) async {
    setState(() => _selected = conversation);
    if (conversation.unreadCount > 0) {
      // Opening it is reading it. Fire-and-forget: a failed badge clear is not worth interrupting
      // the merchant, who can see the messages regardless.
      try {
        await widget.api.markRead(conversation.id);
        _reload();
      } catch (_) {
        // Deliberately silent — see above.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 300,
          child: _ConversationList(
            inbox: _inbox,
            selectedId: _selected?.id,
            archived: _archived,
            onSelect: _select,
            onToggleArchived: () {
              setState(() => _archived = !_archived);
              _reload(keepSelection: false);
            },
            onManageNumbers: _manageNumbers,
            onRefresh: _reload,
          ),
        ),
        const VerticalDivider(width: 1),
        if (_selected == null)
          Expanded(
            child: _Nothing(
              icon: Icons.chat_bubble_outline,
              title: t.selectAConversation,
              message: t.selectAConversationBlurb,
            ),
          )
        else ...<Widget>[
          Expanded(
            child: _Thread(
              key: ValueKey<String>('thread-${_selected!.id}'),
              api: widget.api,
              conversation: _selected!,
              onArchived: () => _reload(keepSelection: false),
              onReplied: _reload,
            ),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 400,
            child: WhatsAppDraftPanel(
              key: ValueKey<String>('draft-${_selected!.id}'),
              api: widget.api,
              catalogApi: widget.catalogApi,
              conversation: _selected!,
              onPlaced: _reload,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _manageNumbers() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _NumbersDialog(api: widget.api),
    );
    if (mounted) _reload();
  }
}

/// An empty column, with a reason.
///
/// Local rather than in the design system: "nothing here yet" looks different in every product, and
/// promoting the first one to a shared widget tends to fix the wrong shape for everybody else.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- who is waiting

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.inbox,
    required this.selectedId,
    required this.archived,
    required this.onSelect,
    required this.onToggleArchived,
    required this.onManageNumbers,
    required this.onRefresh,
  });

  final Future<List<WhatsAppConversation>> inbox;
  final String? selectedId;
  final bool archived;
  final ValueChanged<WhatsAppConversation> onSelect;
  final VoidCallback onToggleArchived;
  final VoidCallback onManageNumbers;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              DeliverySpacing.md, DeliverySpacing.md, DeliverySpacing.sm, DeliverySpacing.sm),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(archived ? t.archived : t.whatsappInbox,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: t.refresh,
              ),
              IconButton(
                onPressed: onManageNumbers,
                icon: const Icon(Icons.phone_iphone),
                tooltip: t.connectedNumbers,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.md),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onToggleArchived,
              icon: Icon(archived ? Icons.inbox_outlined : Icons.archive_outlined, size: 18),
              label: Text(archived ? t.showActive : t.showArchived),
            ),
          ),
        ),
        const Divider(height: DeliverySpacing.md),
        Expanded(
          child: FutureBuilder<List<WhatsAppConversation>>(
            future: inbox,
            builder: (BuildContext context, AsyncSnapshot<List<WhatsAppConversation>> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
              }
              if (snapshot.hasError) {
                return Center(child: Text(t.thatDidNotWorkWith('${snapshot.error}')));
              }
              final List<WhatsAppConversation> conversations =
                  snapshot.data ?? const <WhatsAppConversation>[];
              if (conversations.isEmpty) {
                return _Nothing(
                  icon: Icons.chat_outlined,
                  title: t.noConversations,
                  message: t.noConversationsBlurb,
                );
              }
              return ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (BuildContext context, int i) {
                  final WhatsAppConversation c = conversations[i];
                  return ListTile(
                    selected: c.id == selectedId,
                    selectedTileColor: DeliveryColors.brandSoft,
                    title: Text(c.customerName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(c.customerWaId,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: c.unreadCount > 0
                        ? Badge(label: Text('${c.unreadCount}'))
                        : null,
                    onTap: () => onSelect(c),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------- what they said

class _Thread extends StatefulWidget {
  const _Thread({
    super.key,
    required this.api,
    required this.conversation,
    required this.onArchived,
    required this.onReplied,
  });

  final WhatsAppApi api;
  final WhatsAppConversation conversation;
  final VoidCallback onArchived;
  final VoidCallback onReplied;

  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  late Future<List<WhatsAppMessage>> _messages = widget.api.thread(widget.conversation.id);
  final TextEditingController _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _messages = widget.api.thread(widget.conversation.id));

  Future<void> _send() async {
    final String body = _reply.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);
    final DeliveryStrings t = DeliveryStrings.of(context);
    try {
      final ReplyResult result = await widget.api.reply(widget.conversation.id, body);
      _reply.clear();
      _reload();
      widget.onReplied();
      if (!mounted) return;
      // Recorded either way, so the merchant is told plainly when it did not go out rather than
      // being left to guess from a thread that looks identical in both cases.
      if (!result.sent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.failureDetail ?? t.replyNotSent)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.thatDidNotWorkWith('$e'))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _archive() async {
    try {
      await widget.api.archive(widget.conversation.id);
      widget.onArchived();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).thatDidNotWorkWith('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.conversation.customerName,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(widget.conversation.customerWaId,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                tooltip: t.refresh,
              ),
              IconButton(
                onPressed: _archive,
                icon: const Icon(Icons.archive_outlined),
                tooltip: t.archive,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<WhatsAppMessage>>(
            future: _messages,
            builder: (BuildContext context, AsyncSnapshot<List<WhatsAppMessage>> snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
              }
              final List<WhatsAppMessage> messages = snapshot.data ?? const <WhatsAppMessage>[];
              return ListView.builder(
                padding: const EdgeInsets.all(DeliverySpacing.md),
                itemCount: messages.length,
                itemBuilder: (BuildContext context, int i) => _Bubble(message: messages[i]),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(DeliverySpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(hintText: t.typeAReply),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: DeliverySpacing.sm),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: Text(t.sendReply),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final WhatsAppMessage message;

  /// What to show when the platform cannot render the message itself.
  ///
  /// A merchant seeing an empty bubble where a voice note arrived concludes the platform lost it and
  /// chases the wrong problem. Naming the kind is the honest answer.
  String _placeholder(DeliveryStrings t) => switch (message.messageType) {
        'AUDIO' => t.voiceNote,
        'IMAGE' => t.photo,
        'DOCUMENT' => t.document,
        'LOCATION' => t.locationPin,
        _ => t.unsupportedMessage,
      };

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    final bool inbound = message.inbound;
    return Align(
      alignment: inbound ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.only(bottom: DeliverySpacing.sm),
          padding: const EdgeInsets.all(DeliverySpacing.sm),
          decoration: BoxDecoration(
            color: inbound ? DeliveryColors.background : DeliveryColors.brandSoft,
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (message.hasBody)
                Text(message.body!)
              else
                Text(_placeholder(t),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic, color: DeliveryColors.muted)),
              const SizedBox(height: 2),
              Text(
                '${message.sentAt.hour.toString().padLeft(2, '0')}:'
                '${message.sentAt.minute.toString().padLeft(2, '0')}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: DeliveryColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- connected numbers

class _NumbersDialog extends StatefulWidget {
  const _NumbersDialog({required this.api});

  final WhatsAppApi api;

  @override
  State<_NumbersDialog> createState() => _NumbersDialogState();
}

class _NumbersDialogState extends State<_NumbersDialog> {
  late Future<List<ConnectedNumber>> _numbers = widget.api.numbers();
  final TextEditingController _id = TextEditingController();
  final TextEditingController _label = TextEditingController();
  final TextEditingController _display = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _label.dispose();
    _display.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _numbers = widget.api.numbers());

  Future<void> _connect() async {
    if (_id.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.connectNumber(
        phoneNumberId: _id.text.trim(),
        label: _label.text.trim().isEmpty ? null : _label.text.trim(),
        displayNumber: _display.text.trim().isEmpty ? null : _display.text.trim(),
      );
      _id.clear();
      _label.clear();
      _display.clear();
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).thatDidNotWorkWith('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(ConnectedNumber number) async {
    try {
      await widget.api.disconnectNumber(number.phoneNumberId);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DeliveryStrings.of(context).thatDidNotWorkWith('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return AlertDialog(
      title: Text(t.connectedNumbers),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FutureBuilder<List<ConnectedNumber>>(
              future: _numbers,
              builder: (BuildContext context, AsyncSnapshot<List<ConnectedNumber>> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(DeliverySpacing.md),
                    child: Center(child: CircularProgressIndicator(color: DeliveryColors.brand)),
                  );
                }
                final List<ConnectedNumber> numbers = snapshot.data ?? const <ConnectedNumber>[];
                if (numbers.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: DeliverySpacing.md),
                    child: Text(t.noNumbersBlurb,
                        style: Theme.of(context).textTheme.bodySmall),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: numbers
                      .map((ConnectedNumber n) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(n.label ?? n.phoneNumberId),
                            subtitle: Text(n.displayNumber ?? n.phoneNumberId),
                            trailing: TextButton(
                              onPressed: () => _disconnect(n),
                              child: Text(t.disconnect),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            const Divider(height: DeliverySpacing.lg),
            TextField(
              controller: _id,
              decoration: InputDecoration(labelText: t.numberId),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: _label,
              decoration: InputDecoration(labelText: t.numberLabel),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            TextField(
              controller: _display,
              decoration: InputDecoration(labelText: t.displayNumber),
            ),
            const SizedBox(height: DeliverySpacing.sm),
            // Stated rather than discovered: a merchant who disconnects a number expecting to lose
            // only the routing would otherwise fear they had deleted their customer history.
            Text(t.disconnectNumberWarning, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(onPressed: _busy ? null : _connect, child: Text(t.connect)),
      ],
    );
  }
}

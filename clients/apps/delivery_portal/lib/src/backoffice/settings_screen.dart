import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'auto_approval_panel.dart';
import 'delivery_rate_panel.dart';

/// Backoffice Settings — the platform's runtime controls, in one place (Section 8).
///
/// Two sections, and they are here together for the same reason: each replaces a thing that used to
/// need a deployment. Automatic approval comes first because it is the one an operator arrives
/// looking for — it was an environment variable and a container restart, which is precisely why
/// nobody could find it — and because the connector list below is long enough to bury it.
///
/// The rest of this comment is about the connectors.
///
/// Connector Settings — the Backoffice's runtime control over the integration layer.
///
/// The screen exists so switching SMS provider is a business decision rather than a release. That
/// also makes it the most consequential page in the Backoffice: a change here redirects real SMS
/// traffic and, from Phase 4, real money. Three things follow from that, and all three are
/// deliberate:
///
///  * **Providers come from the server, never from a list in this file.** The dropdown renders
///    `availableProviders`, so it cannot offer something the connector has no client for. The
///    service re-checks anyway — a dropdown is a UI convention, not an enforcement point.
///  * **There is no field for a credential.** Secrets live in Vault and are not reachable from any
///    API a browser can call. This shows that one exists and when it last changed, nothing more.
///  * **Every change is confirmed and then shown in the history below it.** Reversing a mistaken
///    switch is only possible if the previous value is on screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.rateApi,
    required this.autoApprovalApi,
  });

  final ConnectorSettingsApi api;
  final DeliveryRateApi rateApi;

  /// The three approval gates. Required rather than optional: a build that forgot to wire it would
  /// silently go back to having no control on the page, which is the state this screen exists to
  /// end.
  final AutoApprovalApi autoApprovalApi;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<ConnectorSetting>> _connectors = widget.api.list();

  // A block body, not an arrow. `setState(() => _x = someFuture())` makes the closure RETURN that
  // future, and setState asserts against a Future return - which only fires in debug, because
  // release builds strip asserts. So the arrow form works in production and throws the moment
  // anyone opens the screen in a debug build or a widget test.
  void _reload() {
    setState(() {
      _connectors = widget.api.list();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fills the width the rail shell gives it — see the note in dashboard_screen.dart.
    //
    // The connector load is inside the list rather than around it. It used to wrap the whole page,
    // which meant a gateway that could not answer for the connectors took the approval switches
    // down with it — two unrelated endpoints, one of which an operator may well be on this page to
    // reach because the other is misbehaving.
    return ListView(
      padding: const EdgeInsets.all(DeliverySpacing.lg),
      children: <Widget>[
        Text('Approvals', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          'Who is read by a person before they go live. Changes take effect immediately — no '
          'deploy, no restart.',
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: DeliveryColors.muted),
        ),
        const SizedBox(height: DeliverySpacing.md),
        AutoApprovalPanel(api: widget.autoApprovalApi),
        const SizedBox(height: DeliverySpacing.lg + DeliverySpacing.sm),
        Text('Connectors', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          'Which provider each integration uses right now. Changes take effect within '
          'seconds — no deploy, no restart.',
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: DeliveryColors.muted),
        ),
        const SizedBox(height: DeliverySpacing.lg),
        _connectorList(),
      ],
    );
  }

  Widget _connectorList() {
    return FutureBuilder<List<ConnectorSetting>>(
      future: _connectors,
      builder: (BuildContext context, AsyncSnapshot<List<ConnectorSetting>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: DeliverySpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Could not load connector settings: ${snapshot.error}'));
        }

        final List<ConnectorSetting> connectors = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SectionLabel('Integrations',
                trailing: Text('${connectors.length} connectors',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeliveryColors.muted))),
            for (final ConnectorSetting connector in connectors)
              Padding(
                padding: const EdgeInsets.only(bottom: DeliverySpacing.md),
                child: _ConnectorCard(
                  // Keyed by connector so a reload cannot hand one card's in-flight state to
                  // another if the server ever returns them in a different order.
                  key: ValueKey<String>(connector.connectorType),
                  connector: connector,
                  api: widget.api,
                  rateApi: widget.rateApi,
                  onChanged: _reload,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ConnectorCard extends StatefulWidget {
  const _ConnectorCard({
    super.key,
    required this.connector,
    required this.api,
    required this.rateApi,
    required this.onChanged,
  });

  final ConnectorSetting connector;
  final ConnectorSettingsApi api;
  final DeliveryRateApi rateApi;
  final VoidCallback onChanged;

  @override
  State<_ConnectorCard> createState() => _ConnectorCardState();
}

class _ConnectorCardState extends State<_ConnectorCard> {
  bool _busy = false;

  static const Map<String, IconData> _icons = <String, IconData>{
    'SMS': Icons.sms_outlined,
    'EMAIL': Icons.mail_outline,
    'PUSH': Icons.notifications_outlined,
    'CORE_BANKING': Icons.account_balance_outlined,
  };

  /// Named so a non-engineer can tell what they are choosing between.
  ///
  /// Kept short deliberately — these render inside a half-width dropdown, and a label long enough
  /// to be truncated is a label nobody can read. What each choice actually does goes in
  /// [_providerEffects], under the field where there is room for it.
  static const Map<String, String> _providerLabels = <String, String>{
    'DEV_PASSTHROUGH': 'Dev test inbox',
    'DEV_LOG': 'Dev log only',
    'MONTYMOBILE': 'MontyMobile',
    'TWILIO': 'Twilio',
    'SMTP': 'SMTP relay',
    'FIREBASE': 'Firebase (FCM)',
    'SIMULATOR': 'Simulator',
    'REAL': 'Live bank',
  };

  static const Map<String, String> _providerEffects = <String, String>{
    'DEV_PASSTHROUGH': 'Messages go to the QA inbox. No real SMS is sent.',
    'DEV_LOG': 'Messages are logged only. No real push is sent.',
    'MONTYMOBILE': 'Sends real SMS through MontyMobile. Billed per segment.',
    'TWILIO': 'Sends real SMS through Twilio. Billed per segment.',
    'SMTP': 'Sends real email through the configured relay.',
    'FIREBASE': 'Sends real push to registered devices.',
    'SIMULATOR': 'Posts to the Core Banking simulator. No real money moves.',
    'REAL': 'Posts to the live Core Banking system. Real money moves.',
  };

  static bool _isLive(String provider) =>
      !provider.startsWith('DEV_') && provider != 'SIMULATOR';

  Future<void> _switchTo(String provider) async {
    final bool goingLive = _isLive(provider) && !_isLive(widget.connector.provider);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => _ConfirmSwitchDialog(
        connectorType: widget.connector.connectorType,
        from: widget.connector.provider,
        to: provider,
        // Going from a dev provider to a real vendor is the change worth slowing down: it starts
        // sending to real people and, for SMS, starts costing money.
        goingLive: goingLive,
        label: (String p) => _providerLabels[p] ?? p,
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.api.update(
        widget.connector.connectorType,
        provider: provider,
        config: widget.connector.config,
      );
      widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      // 422 covers both an unsupported provider and a config the service thinks carries a secret.
      // Its detail message is written for a human, so it is shown rather than replaced.
      final String detail = e.response?.statusCode == 422
          ? '${(e.response?.data as Map<String, dynamic>?)?['detail'] ?? 'Rejected'}'
          : 'Could not change the provider';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
    } finally {
      // Cleared on success as well as failure. The parent's reload rebuilds this card but Flutter
      // reuses the State object, so a flag left set on the success path would leave the progress
      // bar spinning over a change that had already completed.
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Starts, changes or stops a canary ramp.
  ///
  /// Goes through the same `update` call as a provider switch, so a ramp is audited exactly like
  /// any other change to where messages go — and passing `null` clears it, which is the rollback.
  Future<void> _setCanary(String? provider, int percentage) async {
    final Map<String, String> config = Map<String, String>.from(widget.connector.config);
    if (provider == null) {
      config.remove('canaryProvider');
      config.remove('canaryPercentage');
    } else {
      config['canaryProvider'] = provider;
      config['canaryPercentage'] = '$percentage';
    }

    setState(() => _busy = true);
    try {
      await widget.api.update(
        widget.connector.connectorType,
        provider: widget.connector.provider,
        config: config,
      );
      widget.onChanged();
    } on DioException catch (e) {
      if (!mounted) return;
      final String detail = e.response?.statusCode == 422
          ? '${(e.response?.data as Map<String, dynamic>?)?['detail'] ?? 'Rejected'}'
          : 'Could not change the ramp';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showHistory() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => _HistoryDialog(
        connectorType: widget.connector.connectorType,
        api: widget.api,
        label: (String p) => _providerLabels[p] ?? p,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ConnectorSetting c = widget.connector;
    final bool live = _isLive(c.provider);

    return SoftCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_icons[c.connectorType] ?? Icons.settings_outlined,
                    color: DeliveryColors.brand),
                const SizedBox(width: DeliverySpacing.sm),
                Text(
                  c.connectorType.replaceAll('_', ' '),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: DeliverySpacing.sm),
                // The single most important thing on this page: whether this connector is
                // currently touching the outside world. Reuses the shared badge rather than a
                // local pill so it reads the same as every other state indicator in the platform.
                DeliveryStatusBadge(
                  status: live ? DeliveryStatusColor.inTransit : DeliveryStatusColor.offline,
                  label: live ? 'Live provider' : 'Dev provider',
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showHistory,
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('History'),
                ),
              ],
            ),
            const SizedBox(height: DeliverySpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: DeliverySpacing.sm),
                          child: LinearProgressIndicator(),
                        )
                      : DropdownButtonFormField<String>(
                          initialValue: c.provider,
                          // Without isExpanded the field sizes to its content and overflows the
                          // column rather than ellipsising - the selected label is then clipped
                          // with no indication that it was.
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Active provider',
                            // What this choice actually does, spelled out under the field. The
                            // label alone cannot carry it and still fit.
                            helperText: _providerEffects[c.provider],
                            helperMaxLines: 2,
                          ),
                          // Disabled rather than hidden when there is only one choice: hiding it
                          // would leave a reader unsure whether a provider is even configured.
                          onChanged: c.isFixedProvider
                              ? null
                              : (String? value) {
                                  if (value != null && value != c.provider) _switchTo(value);
                                },
                          items: <DropdownMenuItem<String>>[
                            for (final String p in c.availableProviders)
                              DropdownMenuItem<String>(
                                value: p,
                                child: Text(_providerLabels[p] ?? p,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                        ),
                ),
                const SizedBox(width: DeliverySpacing.lg),
                Expanded(child: _CredentialStatus(connector: c)),
              ],
            ),
            // Only where there is a real choice of provider. A success rate for SMTP-only email is
            // a number with no question attached, and the ramp control would offer nothing to ramp.
            if (!c.isFixedProvider) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              const Divider(height: 1),
              const SizedBox(height: DeliverySpacing.sm),
              DeliveryRatePanel(channel: c.connectorType, api: widget.rateApi),
              const SizedBox(height: DeliverySpacing.sm),
              _CanaryControl(
                connector: c,
                labels: _providerLabels,
                busy: _busy,
                onRamp: _setCanary,
              ),
            ],
            if (c.config.isNotEmpty) ...<Widget>[
              const SizedBox(height: DeliverySpacing.md),
              const Divider(height: 1),
              const SizedBox(height: DeliverySpacing.sm),
              Text('Configuration',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: DeliveryColors.muted)),
              const SizedBox(height: DeliverySpacing.xs),
              Wrap(
                spacing: DeliverySpacing.sm,
                runSpacing: DeliverySpacing.xs,
                children: <Widget>[
                  for (final MapEntry<String, String> entry in c.config.entries)
                    Chip(
                      label: Text('${entry.key}: ${entry.value}'),
                      backgroundColor: DeliveryColors.background,
                      side: const BorderSide(color: DeliveryColors.border),
                    ),
                ],
              ),
            ],
            if (c.updatedBy != null) ...<Widget>[
              const SizedBox(height: DeliverySpacing.sm),
              Text(
                'Last changed by ${c.updatedBy} ${_ago(c.updatedAt)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: DeliveryColors.muted),
              ),
            ],
          ],
        ),
    );
  }
}

/// The canary ramp: send a slice of traffic to a second provider instead of all of it.
///
/// This is what makes Phase 6's "monitor delivery rates before fully retiring the fallback"
/// possible. An all-or-nothing switch gives one data point — everything worked, or everything is
/// broken and customers found out first.
///
/// **Stop is always available and always one click**, never behind a confirmation. Every other
/// destructive-looking action on this screen asks first; this one does the opposite, because the
/// only reason to press it is that something is already going wrong.
class _CanaryControl extends StatelessWidget {
  const _CanaryControl({
    required this.connector,
    required this.labels,
    required this.busy,
    required this.onRamp,
  });

  final ConnectorSetting connector;
  final Map<String, String> labels;
  final bool busy;
  final void Function(String? provider, int percentage) onRamp;

  String? get _canary {
    final String? value = connector.config['canaryProvider'];
    return value == null || value.isEmpty ? null : value;
  }

  int get _percentage => int.tryParse(connector.config['canaryPercentage'] ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final List<String> candidates = connector.availableProviders
        .where((String p) => p != connector.provider)
        .toList();
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_canary == null) {
      // A Wrap, not a Row. Two candidate providers plus the label overflow the card at its 880px
      // max width, and a connector with three would be worse — this flows onto a second line
      // instead of clipping the button nobody can then press.
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: DeliverySpacing.sm,
        runSpacing: DeliverySpacing.xs,
        children: <Widget>[
          Text('Canary',
              style:
                  Theme.of(context).textTheme.labelLarge?.copyWith(color: DeliveryColors.muted)),
          Text('not running',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted)),
          // Ramps start small. 5% of traffic is enough to see a broken vendor and few enough
          // customers to apologise to.
          for (final String p in candidates)
            OutlinedButton(
              onPressed: busy ? null : () => onRamp(p, 5),
              child: Text('${labels[p] ?? p} 5%'),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Canary',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: DeliveryColors.muted)),
            const SizedBox(width: DeliverySpacing.sm),
            DeliveryStatusBadge(
              status: DeliveryStatusColor.preparing,
              label: '${labels[_canary] ?? _canary} · $_percentage%',
            ),
            const Spacer(),
            // No confirmation dialog, deliberately. See the class comment.
            TextButton.icon(
              onPressed: busy ? null : () => onRamp(null, 0),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('Stop ramp'),
              style: TextButton.styleFrom(foregroundColor: DeliveryColors.brand),
            ),
          ],
        ),
        const SizedBox(height: DeliverySpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DeliverySpacing.xs,
          runSpacing: DeliverySpacing.xs,
          children: <Widget>[
            Text('Move to',
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted)),
            for (final int step in <int>[5, 25, 50, 100])
              OutlinedButton(
                onPressed: busy || step == _percentage ? null : () => onRamp(_canary, step),
                // 100% completes the cutover: at that point every message goes to the canary and
                // the primary is only still named in the config.
                child: Text(step == 100 ? '100% (complete)' : '$step%'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Shows that a credential exists and when it last changed — never the credential.
class _CredentialStatus extends StatelessWidget {
  const _CredentialStatus({required this.connector});

  final ConnectorSetting connector;

  @override
  Widget build(BuildContext context) {
    if (!connector.hasCredential) {
      return const _Field(label: 'Credential', value: 'Not configured');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Field(label: 'Credential', value: connector.maskedSecret!),
        const SizedBox(height: DeliverySpacing.xs),
        Text(
          // The Vault path, not the secret. Useful to whoever has to rotate it.
          '${connector.vaultPath}  ·  '
          '${connector.secretRotatedAt == null ? 'never rotated' : 'rotated ${_ago(connector.secretRotatedAt)}'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: DeliveryColors.muted)),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

class _ConfirmSwitchDialog extends StatelessWidget {
  const _ConfirmSwitchDialog({
    required this.connectorType,
    required this.from,
    required this.to,
    required this.goingLive,
    required this.label,
  });

  final String connectorType;
  final String from;
  final String to;
  final bool goingLive;
  final String Function(String) label;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Switch $connectorType provider?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${label(from)}  →  ${label(to)}',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: DeliverySpacing.md),
          if (goingLive)
            Container(
              padding: const EdgeInsets.all(DeliverySpacing.sm),
              decoration: BoxDecoration(
                color: DeliveryColors.brandSoft,
                border: Border.all(color: DeliveryColors.brandLine),
                borderRadius: BorderRadius.circular(DeliveryRadius.md),
              ),
              child: const Text(
                'This starts sending to real recipients through a paid provider. Make sure its '
                'credentials are in Vault first — without them every message fails.',
              ),
            )
          else
            const Text(
              'This stops sending through the live provider. Messages will go to the dev '
              'destination instead and real recipients will receive nothing.',
            ),
          const SizedBox(height: DeliverySpacing.sm),
          Text(
            'The change is recorded against your account.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeliveryColors.muted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(goingLive ? 'Go live' : 'Switch'),
        ),
      ],
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  const _HistoryDialog({
    required this.connectorType,
    required this.api,
    required this.label,
  });

  final String connectorType;
  final ConnectorSettingsApi api;
  final String Function(String) label;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('$connectorType change history'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<ConnectorAuditEntry>>(
          future: api.history(connectorType),
          builder: (BuildContext context, AsyncSnapshot<List<ConnectorAuditEntry>> snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text('Could not load the history: ${snapshot.error}');
            }

            final List<ConnectorAuditEntry> entries = snapshot.data!;
            if (entries.isEmpty) {
              return const Text('This connector has never been changed.');
            }

            return ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final ConnectorAuditEntry e in entries)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.swap_horiz, size: 18),
                    title: Text(
                        '${label(e.oldProvider ?? '—')}  →  ${label(e.newProvider ?? '—')}'),
                    subtitle: Text('${e.changedBy} · ${_ago(e.changedAt)}'),
                  ),
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Relative time, because "3 minutes ago" answers "did that just happen" and a timestamp does not.
String _ago(DateTime? time) {
  if (time == null) return 'at an unknown time';
  final Duration d = DateTime.now().difference(time);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

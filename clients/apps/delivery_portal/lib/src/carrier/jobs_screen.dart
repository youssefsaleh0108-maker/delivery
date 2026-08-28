import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// Everything this company is carrying, and everything it has delivered.
///
/// The first of the two questions a delivery company actually opens an app to ask. The Riders page
/// could tell them their score and their fleet, but not what those riders were doing right now.
///
/// The 2026-08 Figma set draws no job board for the carrier — its four carrier frames are the
/// dashboard, the fleet, onboarding and settings — so this page is built out of the console's own
/// components rather than from a frame: the same header, the same table card, the same status
/// pills the redesigned screens use, so it reads as one console rather than as the page that was
/// left behind.
///
/// Each row carries what the job is worth to them, because a list of addresses with no money on it
/// is a dispatch board, not a business.
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, required this.api});

  final OrderApi api;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  late Future<Paged<DeliveryOrder>> _jobs = widget.api.forCarrier(size: 50);
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// The design's two-idiom filter: states of one population, not populations. "All" plus the three
  /// stages a carrier's job can be at.
  static const List<String> _filters = <String>['All', 'On the road', 'Delivered', 'Cancelled'];
  int _filter = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _jobs = widget.api.forCarrier(size: 50));

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);

    return FutureBuilder<Paged<DeliveryOrder>>(
      future: _jobs,
      builder: (BuildContext context, AsyncSnapshot<Paged<DeliveryOrder>> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: DeliveryColors.background,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(color: DeliveryColors.brand),
          );
        }
        if (snapshot.hasError) {
          // The likeliest cause by far, and not a fault: this account is not attached to a company
          // yet, which the server answers with a 404.
          return _nothing(t.noCompanyYet, t.askThePlatformToAttachYou);
        }

        final List<DeliveryOrder> jobs =
            snapshot.data?.content ?? const <DeliveryOrder>[];
        return _page(jobs, t);
      },
    );
  }

  Widget _page(List<DeliveryOrder> jobs, DeliveryStrings t) {
    final List<DeliveryOrder> shown = jobs.where(_matchesFilter).where(_matchesQuery).toList();

    return ConsolePage(
      header: ConsoleTopbar(
        title: t.jobsTitle,
        subtitle: t.jobsBlurb,
        actions: <Widget>[
          ConsoleSearchField.global(
            hintText: 'Search jobs...',
            controller: _search,
            onChanged: (String value) => setState(() => _query = value.trim()),
          ),
          ConsoleIconAction(
            icon: Icons.refresh,
            tooltip: t.refresh,
            onPressed: _reload,
          ),
          // FINISH-WAVE NOTE: the console bell's slot. `ConsoleBell` is not exported from
          // `shell/shell.dart` yet, so this keeps the drawn control and compiles against the
          // barrel as it stands.
          const ConsoleIconAction(
            icon: Icons.notifications_none,
            tooltip: 'Notifications',
          ),
        ],
      ),
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: ConsoleFilterPills(
            labels: _filters,
            selectedIndex: _filter,
            onSelected: (int i) => setState(() => _filter = i),
          ),
        ),
        ConsoleTable(
          minWidth: 1040,
          columns: const <ConsoleColumn>[
            ConsoleColumn(label: 'Job', width: 110),
            ConsoleColumn(label: 'Status', width: 150),
            ConsoleColumn(label: 'Pickup', flex: 1),
            ConsoleColumn(label: 'Drop-off', flex: 2),
            ConsoleColumn(label: 'Placed', width: 120),
            ConsoleColumn(label: 'Your fee', width: 120, alignRight: true),
          ],
          empty: Text(
            jobs.isEmpty ? t.noJobsBlurb : 'No job matches that.',
            style: ConsoleText.pageSubtitle,
          ),
          rows: <ConsoleTableRow>[
            for (final DeliveryOrder job in shown)
              ConsoleTableRow(
                cells: <Widget>[
                  Text('#${job.shortId}', style: ConsoleText.cellLink),
                  ConsoleStatusPill.status(_colourOf(job.status), label: job.status.label),
                  Text(
                    job.storeName ?? '—',
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.cellMuted,
                  ),
                  Text(
                    job.deliveryAddress,
                    overflow: TextOverflow.ellipsis,
                    style: ConsoleText.cell,
                  ),
                  Text(_date(job.placedAt), style: ConsoleText.cellMuted),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // What the company earns, not what the customer paid. A carrier reading the
                      // order total would be reading somebody else's number.
                      Text(job.deliveryFee.toStringAsFixed(2), style: ConsoleText.cellStrong),
                      // The waived platform cut, visible to the company receiving it.
                      if (job.carrierFeeWaived)
                        Text(
                          t.savedByOffers,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: DeliveryColors.brand,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
          ],
          footer: Text(
            'Showing ${shown.length} of ${jobs.length} recent jobs.',
            style: ConsoleText.meta,
          ),
        ),
      ],
    );
  }

  bool _matchesFilter(DeliveryOrder job) => switch (_filter) {
        1 => job.status == OrderStatus.pickedUp || job.status == OrderStatus.ready,
        2 => job.status == OrderStatus.delivered,
        3 => job.status == OrderStatus.cancelled,
        _ => true,
      };

  bool _matchesQuery(DeliveryOrder job) {
    if (_query.isEmpty) return true;
    final String needle = _query.toLowerCase();
    return job.shortId.toLowerCase().contains(needle) ||
        job.deliveryAddress.toLowerCase().contains(needle) ||
        (job.storeName ?? '').toLowerCase().contains(needle);
  }

  Widget _nothing(String title, String message) {
    return Container(
      color: DeliveryColors.background,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(DeliverySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.local_shipping_outlined, size: 40, color: DeliveryColors.faint),
            const SizedBox(height: DeliverySpacing.md),
            Text(title, style: ConsoleText.cardTitle),
            const SizedBox(height: DeliverySpacing.xs),
            Text(message, textAlign: TextAlign.center, style: ConsoleText.pageSubtitle),
          ],
        ),
      ),
    );
  }

  /// The lifecycle colour, from the shared enum rather than picked here — "delivered" has to be the
  /// same green in the Backoffice table, this job board and the customer's tracking screen.
  static DeliveryStatusColor _colourOf(OrderStatus status) => switch (status) {
        OrderStatus.placed || OrderStatus.accepted => DeliveryStatusColor.placed,
        OrderStatus.preparing || OrderStatus.ready => DeliveryStatusColor.preparing,
        OrderStatus.pickedUp => DeliveryStatusColor.inTransit,
        OrderStatus.delivered => DeliveryStatusColor.delivered,
        OrderStatus.cancelled => DeliveryStatusColor.offline,
      };

  static String _date(DateTime? at) {
    if (at == null) return '—';
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[at.month - 1]} ${at.day.toString().padLeft(2, '0')}, ${at.year}';
  }
}

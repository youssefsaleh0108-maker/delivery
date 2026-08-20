import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

/// Everything this company is carrying, and everything it has delivered.
///
/// The first of the two questions a delivery company actually opens an app to ask. The company page
/// could tell them their score and their fleet, but not what those riders were doing right now.
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

  void _reload() => setState(() => _jobs = widget.api.forCarrier(size: 50));

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.jobsTitle),
        actions: <Widget>[
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: t.refresh),
        ],
      ),
      body: FutureBuilder<Paged<DeliveryOrder>>(
        future: _jobs,
        builder: (BuildContext context, AsyncSnapshot<Paged<DeliveryOrder>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: DeliveryColors.brand));
          }
          if (snapshot.hasError) {
            // The likeliest cause by far, and not a fault: this account is not attached to a
            // company yet, which the server answers with a 404. The company page has said so
            // plainly since it was written; these two were showing a raw Dio exception instead,
            // which reads as the app being broken rather than the account being unfinished.
            return _Nothing(title: t.noCompanyYet, message: t.askThePlatformToAttachYou);
          }
          final List<DeliveryOrder> jobs = snapshot.data?.content ?? const <DeliveryOrder>[];
          if (jobs.isEmpty) {
            return _Nothing(title: t.noJobsYet, message: t.noJobsBlurb);
          }
          return ListView(
            padding: const EdgeInsets.all(DeliverySpacing.lg),
            children: <Widget>[
              Text(t.jobsBlurb, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: DeliverySpacing.md),
              ...jobs.map((DeliveryOrder job) => Padding(
                    padding: const EdgeInsets.only(bottom: DeliverySpacing.sm),
                    child: _JobCard(job: job),
                  )),
            ],
          );
        },
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});

  final DeliveryOrder job;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              OrderStatusBadge(statusWire: job.status.wire),
              const SizedBox(width: DeliverySpacing.sm),
              Text('#${job.shortId}', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  // What the company earns, not what the customer paid. A carrier reading the
                  // order total would be reading somebody else's number.
                  Text(job.deliveryFee.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(t.yourFeeOnThis, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: DeliverySpacing.xs),
          Row(
            children: <Widget>[
              const Icon(Icons.place_outlined, size: 15, color: DeliveryColors.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(job.deliveryAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
          if (job.storeName != null)
            Row(
              children: <Widget>[
                const Icon(Icons.storefront_outlined, size: 15, color: DeliveryColors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(job.storeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
          // The waived platform cut, finally visible to the company receiving it.
          if (job.carrierFeeWaived) ...<Widget>[
            const SizedBox(height: DeliverySpacing.xs),
            Row(
              children: <Widget>[
                const Icon(Icons.redeem_rounded, size: 15, color: DeliveryColors.brand),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(t.savedByOffersNote,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: DeliveryColors.brand)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing({required this.title, required this.message});

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
            const Icon(Icons.local_shipping_outlined, size: 40, color: DeliveryColors.muted),
            const SizedBox(height: DeliverySpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DeliverySpacing.xs),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

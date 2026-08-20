import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:flutter/material.dart';

import 'applicants_screen.dart';
import 'company_screen.dart';
import 'dashboard_screen.dart';
import 'earnings_screen.dart';
import 'jobs_screen.dart';

/// The delivery company's app.
///
/// Four destinations, in the order a company actually thinks about its day: how are we doing, what
/// are we carrying, what will we be paid for it, and who are we. The company page came first when
/// it was the only page; it goes last now, because a score and a payout account are things you
/// check weekly and a job list is something you check all day.
///
/// The dashboard leads because it is the only page that opens with an answer rather than a list.
class CarrierShell extends StatefulWidget {
  const CarrierShell({
    super.key,
    required this.providerApi,
    required this.orderApi,
    required this.onboardingApi,
    required this.locale,
    required this.onSignOut,
  });

  final DeliveryProviderApi providerApi;
  final OrderApi orderApi;
  final OnboardingApi onboardingApi;
  final LocaleController locale;
  final Future<void> Function() onSignOut;

  @override
  State<CarrierShell> createState() => _CarrierShellState();
}

class _CarrierShellState extends State<CarrierShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final DeliveryStrings t = DeliveryStrings.of(context);
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (int i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            indicatorColor: DeliveryColors.brandSoft,
            destinations: <NavigationRailDestination>[
              NavigationRailDestination(
                icon: const Icon(Icons.insights_outlined),
                selectedIcon: const Icon(Icons.insights, color: DeliveryColors.brand),
                label: Text(t.navDashboard),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.local_shipping_outlined),
                selectedIcon: const Icon(Icons.local_shipping, color: DeliveryColors.brand),
                label: Text(t.navJobs),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.payments_outlined),
                selectedIcon: const Icon(Icons.payments, color: DeliveryColors.brand),
                label: Text(t.navEarnings),
              ),
              // Before Company, after the day-to-day pages. Hiring is occasional and must not be
              // missed: somebody is waiting to be told yes or no on the other end of this list,
              // which is not true of any other page here.
              NavigationRailDestination(
                icon: const Icon(Icons.person_search_outlined),
                selectedIcon: const Icon(Icons.person_search, color: DeliveryColors.brand),
                label: Text(t.navApplicants),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.business_outlined),
                selectedIcon: const Icon(Icons.business, color: DeliveryColors.brand),
                label: Text(t.navCompany),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_index) {
              0 => CarrierDashboardScreen(
                    api: widget.orderApi,
                    onShowJobs: () => setState(() => _index = 1),
                  ),
              1 => JobsScreen(api: widget.orderApi),
              2 => EarningsScreen(api: widget.orderApi),
              3 => ApplicantsScreen(
                    api: widget.onboardingApi,
                    providerApi: widget.providerApi,
                  ),
              _ => CompanyScreen(
                    api: widget.providerApi,
                    locale: widget.locale,
                    onSignOut: widget.onSignOut,
                  ),
            },
          ),
        ],
      ),
    );
  }
}

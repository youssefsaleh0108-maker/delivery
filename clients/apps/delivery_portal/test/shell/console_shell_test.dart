import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_portal/src/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The console chrome, at the widths it has to survive.
///
/// Flutter fails a test on a layout overflow, so rendering at several sizes is the cheapest way to
/// catch the class of bug that has accounted for every UI defect in this project — and the closest
/// available stand-in for the browser check nobody can run here. The design is drawn at 1440; a
/// 1280 laptop and a 1024 window are what it will actually be opened on.
const List<Size> _windows = <Size>[
  Size(1440, 900),
  Size(1280, 800),
  Size(1024, 720),
];

Future<void> _pump(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: DeliveryTheme.light(), home: Scaffold(body: child)),
  );
  await tester.pump();
}

void main() {
  group('ConsoleSidebar', () {
    for (final Size size in _windows) {
      testWidgets('renders the rail at ${size.width.toInt()}px', (WidgetTester tester) async {
        await _pump(
          tester,
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ConsoleSidebar(
                area: const ConsoleArea(
                  wordmark: 'Backoffice',
                  logoIcon: Icons.inventory_2,
                ),
                entries: const <ConsoleNavEntry>[
                  ConsoleNavEntry(icon: Icons.bar_chart, label: 'Dashboard'),
                  ConsoleNavEntry(icon: Icons.store, label: 'Merchants'),
                  ConsoleNavEntry(icon: Icons.settings, label: 'Settings'),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
                userName: 'Alex Mercer',
                userRole: 'Backoffice operator',
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
          size,
        );

        expect(find.text('YouDrop'), findsOneWidget);
        expect(find.text('BACKOFFICE'), findsOneWidget);
        // Initials, not a photograph — nothing in the token carries one.
        expect(find.text('AM'), findsOneWidget);
      });
    }

    testWidgets('turns the wordmark into a switcher when an account holds two consoles',
        (WidgetTester tester) async {
      int? picked;
      await _pump(
        tester,
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConsoleSidebar(
              area: const ConsoleArea(wordmark: 'Carrier Hub', logoIcon: Icons.local_shipping),
              areas: const <ConsoleArea>[
                ConsoleArea(wordmark: 'Carrier Hub', logoIcon: Icons.local_shipping),
                ConsoleArea(wordmark: 'Backoffice', logoIcon: Icons.inventory_2),
              ],
              areaIndex: 0,
              onAreaSelected: (int i) => picked = i,
              entries: const <ConsoleNavEntry>[
                ConsoleNavEntry(icon: Icons.bar_chart, label: 'Dashboard'),
              ],
              selectedIndex: 0,
              onSelected: (_) {},
              userName: 'Sam Ali',
              userRole: 'Carrier partner',
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
        const Size(1440, 900),
      );

      await tester.tap(find.text('CARRIER HUB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backoffice').last);
      await tester.pumpAndSettle();

      expect(picked, 1);
    });
  });

  group('ConsolePage', () {
    for (final Size size in _windows) {
      testWidgets('lays out header, KPIs and a table at ${size.width.toInt()}px',
          (WidgetTester tester) async {
        await _pump(
          tester,
          ConsolePage(
            header: ConsoleTopbar(
              title: 'Operations Dashboard',
              subtitle: 'Real-time control tower overview',
              actions: <Widget>[
                const ConsoleSearchField.global(hintText: 'Search backoffice...'),
                ConsoleIconAction(
                  icon: Icons.notifications_none,
                  tooltip: 'Notifications',
                  onPressed: () {},
                ),
              ],
            ),
            children: <Widget>[
              ConsoleKpiRow(
                cards: <Widget>[
                  for (int i = 0; i < 4; i++)
                    ConsoleKpiCard(
                      label: 'Total Orders',
                      value: '12,847',
                      icon: Icons.shopping_bag_outlined,
                      trend: const ConsoleKpiTrend(
                        delta: '+14.3%',
                        caption: 'vs last week',
                      ),
                    ),
                ],
              ),
              ConsoleFilterTabs(
                tabs: const <ConsoleFilterTab>[
                  ConsoleFilterTab(label: 'All Partners'),
                  ConsoleFilterTab(label: 'Pending Approval', count: 14),
                ],
                selectedIndex: 0,
                onSelected: (_) {},
              ),
              ConsoleTable(
                columns: const <ConsoleColumn>[
                  ConsoleColumn(label: 'Merchant Name', flex: 1),
                  ConsoleColumn(label: 'Category', width: 150),
                  ConsoleColumn(label: 'Status', width: 120),
                  ConsoleColumn(label: 'Actions', width: 120, alignRight: true),
                ],
                rows: <ConsoleTableRow>[
                  ConsoleTableRow(
                    cells: <Widget>[
                      const ConsoleNameCell(name: 'Rose & Crust Pizzeria'),
                      const Text('Pizza & Italian', style: ConsoleText.cellMuted),
                      const ConsoleStatusPill(
                        label: 'Active',
                        accent: DeliveryAccent.positive,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ConsoleRowAction(
                            icon: Icons.edit_outlined,
                            tooltip: 'Edit',
                            onPressed: () {},
                          ),
                          const SizedBox(width: DeliverySpacing.sm),
                          ConsoleRowAction(
                            icon: Icons.block,
                            tooltip: 'Suspend',
                            destructive: true,
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          size,
        );

        expect(find.text('Operations Dashboard'), findsOneWidget);
        expect(find.text('Pending Approval (14)'), findsOneWidget);
        expect(find.text('Rose & Crust Pizzeria'), findsOneWidget);
      });
    }
  });
}

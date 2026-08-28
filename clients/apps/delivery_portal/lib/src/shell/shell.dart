/// The console's own component set — the 2026-08 Figma redesign's web chrome, in Flutter.
///
/// Portal-local on purpose, for now. These are drawn straight off the console frames
/// (`backoffice-dashboard` 3:2487, `carrier-dashboard` 3:3429 and the screens sharing their shell)
/// and nothing outside this app has a use for a 260px dark rail or a 1116px data table. When the
/// merchant portal grows a console of its own they can graduate into `delivery_design_system`
/// unchanged — every colour, radius and spacing step in here already comes from that package's
/// tokens rather than from a literal.
///
/// Import this file, not the parts:
/// ```dart
/// import '../shell/shell.dart';
/// ```
library;

export 'console_bell.dart';
export 'console_chrome.dart';
export 'console_drawer.dart';
export 'external_link.dart';
export 'console_filter_tabs.dart';
export 'console_identity.dart';
export 'console_kpi_card.dart';
export 'console_search_field.dart';
export 'console_select.dart';
export 'console_sidebar.dart';
export 'console_status_pill.dart';
export 'console_table.dart';
export 'console_topbar.dart';

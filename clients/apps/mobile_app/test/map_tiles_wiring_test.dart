import 'package:delivery_core/delivery_core.dart' show mapTileUrlTemplate;
import 'package:delivery_merchant/delivery_merchant.dart' as merchant;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/address_sheet.dart' show OsmBasemap;
import 'package:mobile_app/src/rider_job_card.dart'
    show riderOsmAttribution, riderOsmTileTemplate, riderOsmUserAgent;

/// Every map in the app draws its tiles from one setting.
///
/// OpenStreetMap's tile policy asks apps not to hard-code its tile address, and lets it block a client
/// without notice. A map left holding its own copy of the URL would be the one still calling a server
/// the rest of the app had moved away from. So the customer's address sheet, the rider's job card and
/// the merchant's shop pin are all pinned to [mapTileUrlTemplate], which a build can point elsewhere
/// with `--dart-define=MAP_TILE_URL=...`.
void main() {
  test('the address sheet, the rider job card and the shop pin map all read the one tile setting',
      () {
    expect(OsmBasemap.tileUrlTemplate, mapTileUrlTemplate);
    expect(riderOsmTileTemplate, mapTileUrlTemplate);
    expect(merchant.osmTileUrlTemplate, mapTileUrlTemplate);
  });

  test('unless a build overrides it, that is OpenStreetMap, with one app identity and one credit',
      () {
    const String override = String.fromEnvironment('MAP_TILE_URL');
    expect(
      mapTileUrlTemplate,
      override.isEmpty ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png' : override,
    );

    expect(OsmBasemap.userAgentPackageName, riderOsmUserAgent);
    expect(merchant.osmUserAgentPackageName, riderOsmUserAgent);
    expect(OsmBasemap.attribution, riderOsmAttribution);
    expect(merchant.osmAttribution, riderOsmAttribution);
  });
}

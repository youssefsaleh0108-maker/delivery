/// Where every map in the apps fetches its raster tiles from: one setting, not a URL per map.
///
/// OpenStreetMap's own tile servers by default. They are a volunteer-run courtesy, not a contract:
/// their usage policy asks apps not to hard-code the address, because it may have to change, and it
/// lets a heavy or misbehaving client be blocked without notice. So the template lives here, every
/// map reads it, and a build can move all of them at once:
///
/// ```sh
/// flutter build web --dart-define=MAP_TILE_URL=https://tiles.example.com/{z}/{x}/{y}.png
/// ```
///
/// Moving to a commercial or self-hosted provider before launch is the owner's decision. Whichever
/// server it is, the maps keep identifying the app with the same User-Agent package name and keep
/// showing OpenStreetMap's attribution, which a provider serving OpenStreetMap data still requires;
/// such a provider may ask for its own credit beside it.
const String mapTileUrlTemplate = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

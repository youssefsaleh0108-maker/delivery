// Loads the app from the locally-served CanvasKit rather than the Google CDN.
//
// Flutter ships CanvasKit inside build/web/canvaskit/, but by default the loader still fetches it
// from https://www.gstatic.com/flutter-canvaskit/<hash>/. On a machine that cannot reach gstatic
// quickly that download stalls, and because CanvasKit *is* the renderer the page stays completely
// blank until it resolves — measured here at a 15s timeout against 0.17s for the local copy. It
// looks like a broken app or a slow login; it is neither.
//
// This file is a template: Flutter substitutes the two placeholders at build time. Keeping the
// override here rather than in a --dart-define means it cannot be forgotten on a future build.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // Trailing slash required — the loader appends canvaskit.js to it.
    canvasKitBaseUrl: "canvaskit/",
  },
});

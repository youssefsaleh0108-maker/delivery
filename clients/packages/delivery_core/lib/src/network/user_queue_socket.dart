import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/auth_service.dart';

/// The client half of the platform's one realtime socket: STOMP over WebSocket on
/// `/ws/notifications`, the endpoint App Notification Service already runs.
///
/// The server carries everything live on this single socket — order notifications on
/// `/user/queue/notifications`, chat on `/user/queue/chat` — precisely so no client grows a second
/// connection, a second authentication path and a second thing to fail. This class is that policy
/// on the client side: one socket, any number of `/user/...` subscriptions multiplexed over it.
///
/// **Receive-only.** The server refuses client SEND frames outright; chat messages are posted over
/// REST where the resource server and validation apply. Nothing here has a send method to misuse.
///
/// **Delivery, not the record.** The durable copy of everything on this socket is a row in
/// Postgres. A dropped connection loses nothing — on reconnect the consumer refetches from its
/// cursor (chat's `afterSequence`, the inbox's unread count) and catches up. That is why the
/// reconnect here is plain backoff with no replay protocol: there is nothing to replay.
///
/// The token is validated on the STOMP CONNECT frame, not the HTTP upgrade — a browser WebSocket
/// cannot set headers on the upgrade request, and a token in the query string would sit in access
/// logs. The CONNECT frame carries it as a header on every platform alike.
class UserQueueSocket {
  UserQueueSocket({
    required Uri apiBaseUrl,
    required AuthService auth,
    // The default is the notifications socket this class was born for; the tracking panel opens
    // a second instance on `/ws/tracking` for the live rider line. Same STOMP, same CONNECT
    // auth, different endpoint and topics — the class never needed to know whose frames these are.
    String wsPath = '/ws/notifications/websocket',
  })  : _endpoint = _wsEndpoint(apiBaseUrl, wsPath),
        _auth = auth;

  /// The raw-WebSocket transport of the server's SockJS endpoint. SockJS exists for networks that
  /// block WebSocket upgrades; a native client has no such network stack quirks, so it takes the
  /// direct transport and skips the SockJS protocol entirely.
  static Uri _wsEndpoint(Uri apiBaseUrl, String path) => apiBaseUrl.replace(
        scheme: apiBaseUrl.scheme == 'https' ? 'wss' : 'ws',
        path: path,
      );

  final Uri _endpoint;
  final AuthService _auth;

  final Map<String, StreamController<Map<String, dynamic>>> _subscriptions =
      <String, StreamController<Map<String, dynamic>>>{};
  final Map<String, String> _subscriptionIds = <String, String>{};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketEvents;
  Timer? _reconnect;
  bool _connected = false;
  bool _closed = false;
  int _attempts = 0;
  int _nextSubscriptionId = 0;

  /// True while a CONNECTED frame is in force. A consumer that sees this go false→true should
  /// refetch from its cursor: whatever happened in between was not delivered here.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Frames arriving on one `/user/...` destination, decoded from JSON.
  ///
  /// The stream is broadcast and never errors or closes on network trouble — the socket reconnects
  /// behind it and the stream simply goes quiet in between. Watch [connected] for the gap.
  ///
  /// Subscribing to the first destination opens the socket; the connection then stays up until
  /// [close].
  Stream<Map<String, dynamic>> subscribe(String destination) {
    if (_closed) {
      throw StateError('This socket has been closed');
    }
    final StreamController<Map<String, dynamic>> controller = _subscriptions.putIfAbsent(
      destination,
      () {
        final StreamController<Map<String, dynamic>> created =
            StreamController<Map<String, dynamic>>.broadcast();
        if (_connected) {
          _sendSubscribe(destination);
        }
        return created;
      },
    );
    _ensureConnecting();
    return controller.stream;
  }

  /// Tears the socket down for good. A closed socket cannot be reopened — make a new one.
  Future<void> close() async {
    _closed = true;
    _reconnect?.cancel();
    await _socketEvents?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setConnected(false);
    for (final StreamController<Map<String, dynamic>> c in _subscriptions.values) {
      await c.close();
    }
    _subscriptions.clear();
    connected.dispose();
  }

  // ---------------------------------------------------------------- connection lifecycle

  void _ensureConnecting() {
    if (_closed || _channel != null || _reconnect != null) {
      return;
    }
    unawaited(_connect());
  }

  Future<void> _connect() async {
    String? token;
    try {
      AuthSession? session = _auth.session;
      if (session != null && session.isExpired) {
        session = await _auth.refresh();
      }
      token = session?.accessToken;
    } catch (_) {
      token = null;
    }
    if (_closed) {
      return;
    }
    if (token == null) {
      // Signed out. Nothing on this socket is deliverable to nobody; try again later in case a
      // session appears, on the same backoff a dead network gets.
      _scheduleReconnect();
      return;
    }

    try {
      final WebSocketChannel channel = WebSocketChannel.connect(_endpoint);
      _channel = channel;
      _socketEvents = channel.stream.listen(
        (dynamic data) => _onFrame(data is List<int> ? utf8.decode(data) : data as String),
        onError: (Object _) => _onDisconnected(),
        onDone: _onDisconnected,
        cancelOnError: true,
      );
      _sendFrame('CONNECT', <String, String>{
        'accept-version': '1.2',
        'host': _endpoint.host,
        // No heartbeats in either direction: the consumers refetch on reconnect anyway, and a
        // heartbeat timer is one more thing to run down a phone battery for a socket whose loss
        // is already detected by the next frame failing.
        'heart-beat': '0,0',
        'Authorization': 'Bearer $token',
      });
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onFrame(String raw) {
    // A lone linefeed is a server heartbeat; with 0,0 negotiated it should not occur, but
    // tolerating it costs one line.
    if (raw.isEmpty || raw == '\n' || raw == '\r\n') {
      return;
    }
    final _StompFrame frame = _StompFrame.parse(raw);
    switch (frame.command) {
      case 'CONNECTED':
        _attempts = 0;
        _setConnected(true);
        for (final String destination in _subscriptions.keys) {
          _sendSubscribe(destination);
        }
      case 'MESSAGE':
        final String? destination = frame.headers['destination'];
        final StreamController<Map<String, dynamic>>? controller = _subscriptions[destination];
        if (controller == null || frame.body.isEmpty) {
          return;
        }
        try {
          controller.add(jsonDecode(frame.body) as Map<String, dynamic>);
        } catch (_) {
          // A frame that is not a JSON object is nothing any subscriber can render. Dropped: the
          // durable copy is on the server and arrives on the next fetch.
        }
      case 'ERROR':
        // The server refused something — typically an expired token on CONNECT. The socket is
        // about to close; the reconnect path refreshes the token and tries again.
        break;
      default:
        break;
    }
  }

  void _onDisconnected() {
    _socketEvents = null;
    _channel = null;
    _setConnected(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnect != null || _subscriptions.isEmpty) {
      return;
    }
    // 2s, 4s, 8s... capped at a minute, with jitter so a fleet of phones does not reconnect in
    // lockstep when the service comes back.
    final int seconds = min(60, 2 << min(_attempts, 5));
    _attempts++;
    _reconnect = Timer(
      Duration(milliseconds: seconds * 1000 + Random().nextInt(1000)),
      () {
        _reconnect = null;
        unawaited(_connect());
      },
    );
  }

  void _setConnected(bool value) {
    _connected = value;
    if (!_closed && connected.value != value) {
      connected.value = value;
    }
  }

  // ---------------------------------------------------------------- stomp framing

  void _sendSubscribe(String destination) {
    final String id = _subscriptionIds.putIfAbsent(
        destination, () => 'sub-${_nextSubscriptionId++}');
    _sendFrame('SUBSCRIBE', <String, String>{'id': id, 'destination': destination});
  }

  void _sendFrame(String command, Map<String, String> headers) {
    final StringBuffer frame = StringBuffer()..write(command)..write('\n');
    headers.forEach((String k, String v) => frame.write('$k:$v\n'));
    frame.write('\n\x00');
    _channel?.sink.add(frame.toString());
  }
}

/// One parsed server frame. Command, headers, body — nothing more, because the client only ever
/// reads CONNECTED, MESSAGE and ERROR.
class _StompFrame {
  const _StompFrame(this.command, this.headers, this.body);

  final String command;
  final Map<String, String> headers;
  final String body;

  static _StompFrame parse(String raw) {
    final int headerEnd = raw.indexOf('\n\n');
    final String head = headerEnd < 0 ? raw : raw.substring(0, headerEnd);
    String body = headerEnd < 0 ? '' : raw.substring(headerEnd + 2);
    final int nul = body.indexOf('\x00');
    if (nul >= 0) {
      body = body.substring(0, nul);
    }

    final List<String> lines = head.split('\n');
    final Map<String, String> headers = <String, String>{};
    for (final String line in lines.skip(1)) {
      final int colon = line.indexOf(':');
      if (colon > 0) {
        headers[line.substring(0, colon)] = line.substring(colon + 1).trim();
      }
    }
    return _StompFrame(lines.first.trim(), headers, body);
  }
}

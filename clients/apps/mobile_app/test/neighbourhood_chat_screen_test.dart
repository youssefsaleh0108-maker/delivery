import 'dart:async';

import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/src/delivery_address.dart';
import 'package:mobile_app/src/neighbourhood_chat_screen.dart';

typedef _Answer = ({int status, Object? body});

/// The neighbourhood room (Figma 121:102).
///
/// What is pinned is what a room of strangers has to get right: the customer is placed by the area
/// of their own address and never picks a room; neighbours are names and initials, never accounts;
/// a removed message stays a tombstone; report and block reach the server and a blocked neighbour
/// leaves the screen; a muted neighbour is told until when instead of being handed a composer that
/// fails; a customer with no delivery in the area reads the room with the reason in place of the
/// composer; and a customer with no area is asked for one. Nothing the frame draws that the platform
/// does not have — the AI card, the camera, the shared location, a made-up "active" count — is here.
///
/// And what a live room has to get right on a phone's network: nothing said while the room loads is
/// lost, a removal made while offline shows once back online, and a failed page of older history
/// waits for a tap instead of asking again on every frame.
void main() {
  const MethodChannel storageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
  });

  final DeliveryStrings en = lookupDeliveryStrings(const Locale('en'));
  final DeliveryStrings ar = lookupDeliveryStrings(const Locale('ar'));

  const DeliveryAddress home = DeliveryAddress(
    line: 'Armenia Street',
    zoneId: 'z-mar-mikhael',
    zoneName: 'Mar Mikhael',
  );

  Map<String, dynamic> room({String name = 'Mar Mikhael', String? mutedUntil, String posting = 'OPEN'}) =>
      <String, dynamic>{
        'id': 'r1',
        'zoneId': 'z-mar-mikhael',
        'name': name,
        'memberCount': 12,
        'lastSequence': 4,
        'yourHandle': 'h-me',
        'yourName': 'Maya R.',
        'mutedUntil': mutedUntil,
        'posting': posting,
      };

  Map<String, dynamic> said(int sequence, String handle, String? name, String? text,
          {bool mine = false, bool hidden = false}) =>
      <String, dynamic>{
        'id': 'm$sequence',
        'roomId': 'r1',
        'sequence': sequence,
        'authorHandle': handle,
        'authorName': name,
        'mine': mine,
        'kind': hidden ? 'HIDDEN' : 'TEXT',
        'text': text,
        'sentAt': '2026-09-13T07:0$sequence:00Z',
      };

  const String knefeh = 'Anyone know where to find good knefeh nearby?';
  const String hallab = 'Hallab through the app, their knefeh arrives warm';
  const String mine = 'Try the place by the stairs';

  final List<Map<String, dynamic>> thread = <Map<String, dynamic>>[
    said(1, 'h-tania', 'Tania K.', knefeh),
    said(2, 'h-spam', null, null, hidden: true),
    said(3, 'h-me', 'Maya R.', mine, mine: true),
    said(4, 'h-hadi', 'Hadi S.', hallab),
  ];

  late List<RequestOptions> requests;

  Dio serve(_Answer Function(RequestOptions request) route) {
    requests = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        requests.add(options);
        final _Answer answer = route(options);
        final Response<dynamic> response =
            Response<dynamic>(requestOptions: options, statusCode: answer.status, data: answer.body);
        if (answer.status >= 400) {
          handler.reject(DioException(
              requestOptions: options, type: DioExceptionType.badResponse, response: response));
        } else {
          handler.resolve(response);
        }
      },
    ));
    return dio;
  }

  /// The room with [messages], and 204s for reports, blocks and unblocks.
  _Answer Function(RequestOptions) roomServer({
    Map<String, dynamic>? place,
    List<Map<String, dynamic>>? messages,
    _Answer Function(RequestOptions request)? post,
  }) {
    return (RequestOptions r) {
      if (r.method == 'GET' && r.path == '/api/chat/rooms/mine') {
        return (status: 200, body: place ?? room());
      }
      if (r.method == 'GET' && r.path == '/api/chat/rooms/r1/messages') {
        return (status: 200, body: <String, dynamic>{'messages': messages ?? thread, 'more': false});
      }
      if (r.method == 'GET' && r.path == '/api/chat/rooms/blocks') {
        return (
          status: 200,
          body: <dynamic>[
            <String, dynamic>{'id': 'b1', 'name': 'Hadi S.', 'blockedAt': '2026-09-12T10:00:00Z'}
          ]
        );
      }
      if (r.method == 'POST' && r.path.endsWith('/block-author')) {
        return (status: 201, body: <String, dynamic>{'id': 'b1', 'name': 'Hadi S.'});
      }
      if (r.method == 'POST' && r.path == '/api/chat/rooms/r1/messages' && post != null) {
        return post(r);
      }
      return (status: 204, body: null);
    };
  }

  Iterable<RequestOptions> asked(String method, String path) =>
      requests.where((RequestOptions r) => r.method == method && r.path == path);

  Future<DeliveryAddressStore> addressBook(DeliveryAddress? address) async {
    final DeliveryAddressStore store = DeliveryAddressStore(ownerId: 'customer-1');
    if (address != null) await store.select(address);
    return store;
  }

  Future<void> pumpRoom(
    WidgetTester tester,
    Dio dio, {
    DeliveryAddressStore? addresses,
    Future<void> Function(BuildContext context)? onChooseArea,
    Locale locale = const Locale('en'),
    UserQueueSocket? socket,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: DeliveryTheme.light(),
      locale: locale,
      localizationsDelegates: DeliveryStrings.localizationsDelegates,
      supportedLocales: DeliveryStrings.supportedLocales,
      home: NeighbourhoodChatScreen(
        api: NeighbourhoodChatApi(dio),
        addresses: addresses ?? await addressBook(home),
        onChooseArea: onChooseArea,
        socket: socket,
      ),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets(
      "places the customer by their address's area and draws neighbours, a removal and their own words",
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer()));

    expect(asked('GET', '/api/chat/rooms/mine').single.queryParameters,
        <String, dynamic>{'zoneId': 'z-mar-mikhael'},
        reason: 'The app says which area its address is in — never which room to join.');
    expect(find.text(en.chatRoomTitle('Mar Mikhael')), findsOneWidget);
    expect(find.text(en.chatRoomMembers(12)), findsOneWidget);
    expect(find.text('Tania K.'), findsOneWidget);
    expect(find.text(knefeh), findsOneWidget);
    expect(find.text(en.chatRoomHidden), findsOneWidget);
    expect(find.text(en.chatRoomLive), findsNothing,
        reason: 'LIVE is the socket being connected, and this screen has no socket.');
    expect(tester.getTopLeft(find.text(mine)).dx, greaterThan(tester.getTopLeft(find.text(knefeh)).dx),
        reason: "The customer's own words sit against the end, a neighbour's against the start.");
  });

  testWidgets("reports a neighbour's message with the reason chosen", (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer()));

    await tester.longPress(find.text(knefeh));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chatRoomReport));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chatRoomReasonPersonalInfo));
    await tester.pumpAndSettle();

    expect((asked('POST', '/api/chat/rooms/messages/m1/report').single.data
            as Map<String, dynamic>)['reason'],
        'PERSONAL_INFO');
    expect(find.text(en.chatRoomReportSent), findsOneWidget);
  });

  testWidgets('blocks a neighbour, and everything they said leaves the screen',
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer()));

    await tester.longPress(find.text(hallab));
    await tester.pumpAndSettle();
    await tester.tap(find.text(en.chatRoomBlock));
    await tester.pumpAndSettle();
    expect(find.text(en.chatRoomBlockTitle('Hadi S.')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, en.chatRoomBlock));
    await tester.pumpAndSettle();

    expect(asked('POST', '/api/chat/rooms/messages/m4/block-author'), hasLength(1));
    expect(find.text(hallab), findsNothing);
    expect(find.text(knefeh), findsOneWidget);
    expect(find.text(en.chatRoomBlockedToast), findsOneWidget);
  });

  testWidgets("offers only Copy on the customer's own message — nobody reports or blocks themselves",
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer()));

    await tester.longPress(find.text(mine));
    await tester.pumpAndSettle();

    expect(find.text(en.chatRoomCopy), findsOneWidget);
    expect(find.text(en.chatRoomReport), findsNothing);
    expect(find.text(en.chatRoomBlock), findsNothing);
  });

  testWidgets('a muted neighbour is told until when, and has no composer to fail with',
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer(place: room(mutedUntil: '2099-01-01T10:00:00Z'))));

    final String before = en.chatRoomMuted(' ').split(' ').first;
    expect(find.textContaining(before), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a post refused by a mute that just landed swaps the composer for the explanation',
      (WidgetTester tester) async {
    await pumpRoom(
        tester,
        serve(roomServer(
            post: (RequestOptions r) => (
                  status: 403,
                  body: <String, dynamic>{'title': 'Muted', 'mutedUntil': '2099-01-01T10:00:00Z'}
                ))));

    await tester.enterText(find.byType(TextField), 'hello neighbours');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    final Map<String, dynamic> body =
        asked('POST', '/api/chat/rooms/r1/messages').single.data as Map<String, dynamic>;
    expect(body['text'], 'hello neighbours');
    expect(body['clientMessageId'], isNotNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining(en.chatRoomMuted(' ').split(' ').first), findsOneWidget);
  });

  testWidgets('a sent message joins the thread against the end', (WidgetTester tester) async {
    await pumpRoom(
        tester,
        serve(roomServer(
            post: (RequestOptions r) => (
                  status: 201,
                  body: said(5, 'h-me', 'Maya R.', (r.data as Map<String, dynamic>)['text'] as String,
                      mine: true)
                ))));

    await tester.enterText(find.byType(TextField), 'See you at the bakery');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('See you at the bakery'), findsOneWidget);
    expect(tester.getTopLeft(find.text('See you at the bakery')).dx,
        greaterThan(tester.getTopLeft(find.text(hallab)).dx));
  });

  testWidgets('with no area on the address, asks for one, and joins once one is chosen',
      (WidgetTester tester) async {
    final DeliveryAddressStore addresses =
        await addressBook(const DeliveryAddress(line: 'Somewhere typed by hand'));
    int placed = 0;
    int chosen = 0;
    final Dio dio = serve((RequestOptions r) {
      if (r.path == '/api/chat/rooms/mine') {
        placed++;
        return r.queryParameters['zoneId'] == null
            ? (status: 404, body: <String, dynamic>{'title': 'No neighbourhood', 'reason': 'NO_ZONE'})
            : (status: 200, body: room());
      }
      return roomServer(messages: const <Map<String, dynamic>>[])(r);
    });

    await pumpRoom(tester, dio, addresses: addresses, onChooseArea: (BuildContext context) async {
      chosen++;
      await addresses.select(home);
    });

    expect(find.text(en.chatRoomPickAreaTitle), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(en.chatRoomChooseArea));
    await tester.pumpAndSettle();

    expect(chosen, 1);
    expect(placed, 2);
    expect(find.text(en.chatRoomTitle('Mar Mikhael')), findsOneWidget);
    expect(find.text(en.chatRoomEmpty), findsOneWidget,
        reason: 'An empty room invites the first hello rather than showing nothing.');
  });

  testWidgets('the Community tag shows the rules, and lifting a block reloads the room',
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer()));

    await tester.tap(find.text(en.chatRoomCommunity));
    await tester.pumpAndSettle();
    expect(find.text(en.chatRoomRulesTitle), findsOneWidget);
    expect(find.text('Hadi S.'), findsWidgets);

    await tester.tap(find.text(en.chatRoomUnblock));
    await tester.pumpAndSettle();
    expect(asked('DELETE', '/api/chat/rooms/blocks/b1'), hasLength(1));
    expect(find.text(en.chatRoomNoBlocks), findsOneWidget,
        reason: 'The only person blocked was unblocked, so the list says nobody is.');

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(asked('GET', '/api/chat/rooms/mine'), hasLength(2),
        reason: "Somebody unblocked has messages that belong back in the room.");
  });

  testWidgets('loads older history when the start of the thread comes into view',
      (WidgetTester tester) async {
    final Dio dio = serve((RequestOptions r) {
      if (r.path == '/api/chat/rooms/r1/messages') {
        final Object? before = r.queryParameters['beforeSequence'];
        return before == null
            ? (status: 200, body: <String, dynamic>{'messages': thread, 'more': true})
            : (
                status: 200,
                body: <String, dynamic>{
                  'messages': <dynamic>[said(0, 'h-tania', 'Tania K.', 'Good morning everyone')],
                  'more': false,
                }
              );
      }
      return roomServer()(r);
    });

    await pumpRoom(tester, dio);

    expect(asked('GET', '/api/chat/rooms/r1/messages')
        .where((RequestOptions r) => r.queryParameters['beforeSequence'] == 1), hasLength(1));
    expect(find.text('Good morning everyone'), findsOneWidget);
  });

  testWidgets("in Arabic the room reads Arabic and the customer's own words sit on the left",
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer(place: room(name: 'مار مخايل'))),
        locale: const Locale('ar'));

    expect(find.text(ar.chatRoomTitle('مار مخايل')), findsOneWidget);
    expect(find.text(ar.chatRoomHidden), findsOneWidget);
    expect(tester.getTopLeft(find.text(mine)).dx, lessThan(tester.getTopLeft(find.text(knefeh)).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no delivery in the area yet, reads the room and says what would let them post',
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer(place: room(posting: 'NEEDS_DELIVERY'))));

    expect(find.text(knefeh), findsOneWidget, reason: 'Reading needs no delivery.');
    expect(find.text(en.chatRoomPostAfterDelivery), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: 'A composer whose every send the server refuses is a control that cannot work.');
  });

  testWidgets('a post refused for want of a delivery swaps the composer for the reason',
      (WidgetTester tester) async {
    await pumpRoom(
        tester,
        serve(roomServer(
            post: (RequestOptions r) => (
                  status: 403,
                  body: <String, dynamic>{'title': 'Posting locked', 'reason': 'NEEDS_DELIVERY'}
                ))));

    await tester.enterText(find.byType(TextField), 'hello neighbours');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text(en.chatRoomPostAfterDelivery), findsOneWidget);
    expect(find.text(en.chatCouldNotSend), findsNothing,
        reason: 'It is a reason to explain, not a failure to retry.');
  });

  testWidgets('while deliveries cannot be checked, says posting is paused and offers to ask again',
      (WidgetTester tester) async {
    await pumpRoom(tester, serve(roomServer(place: room(posting: 'UNVERIFIED'))));

    expect(find.text(knefeh), findsOneWidget);
    expect(find.text(en.chatRoomPostingUnavailable), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text(en.tryAgain));
    await tester.pumpAndSettle();

    expect(asked('GET', '/api/chat/rooms/mine'), hasLength(2));
  });

  testWidgets('older history that fails to load waits for a tap instead of asking again every frame',
      (WidgetTester tester) async {
    final Dio dio = serve((RequestOptions r) {
      if (r.path == '/api/chat/rooms/r1/messages') {
        return r.queryParameters['beforeSequence'] == null
            ? (status: 200, body: <String, dynamic>{'messages': thread, 'more': true})
            : (status: 503, body: null);
      }
      return roomServer()(r);
    });
    Iterable<RequestOptions> older() => asked('GET', '/api/chat/rooms/r1/messages')
        .where((RequestOptions r) => r.queryParameters['beforeSequence'] != null);

    // Settling at all is part of the proof: a loader that re-asks on every rebuild never settles.
    await pumpRoom(tester, dio);
    await tester.pump(const Duration(seconds: 5));

    expect(older(), hasLength(1), reason: 'One failure is one request, not one per frame.');
    expect(find.text(en.chatRoomOlderFailed), findsOneWidget);

    await tester.tap(find.text(en.chatRoomOlderFailed));
    await tester.pumpAndSettle();

    expect(older(), hasLength(2), reason: 'A tap asks once more.');
  });

  testWidgets('a message said while the room is still loading is kept, not lost between page and feed',
      (WidgetTester tester) async {
    final _FakeSocket socket = _FakeSocket();
    final Completer<void> history = Completer<void>();
    requests = <RequestOptions>[];
    final Dio dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:1'));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) async {
        requests.add(options);
        if (options.path == '/api/chat/rooms/r1/messages') await history.future;
        final _Answer answer = roomServer()(options);
        handler.resolve(
            Response<dynamic>(requestOptions: options, statusCode: answer.status, data: answer.body));
      },
    ));

    await pumpRoom(tester, dio, socket: socket, settle: false);
    for (int i = 0; i < 20 && asked('GET', '/api/chat/rooms/r1/messages').isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(asked('GET', '/api/chat/rooms/r1/messages'), hasLength(1),
        reason: 'The room is placed and its newest page is on the way.');

    // A neighbour speaks after the page was asked for and before it arrives.
    socket.frame('${NeighbourhoodChatApi.liveDestinationPrefix}r1',
        said(5, 'h-hadi', 'Hadi S.', 'Fresh manakish at the corner bakery'));
    history.complete();
    await tester.pumpAndSettle();

    expect(find.text('Fresh manakish at the corner bakery'), findsOneWidget,
        reason: 'Listening began before the page was read, so the frame had somewhere to land.');
    expect(find.text(knefeh), findsOneWidget);
  });

  testWidgets('a message removed while the socket was down reads as removed once it reconnects',
      (WidgetTester tester) async {
    final _FakeSocket socket = _FakeSocket();
    bool removedMeanwhile = false;
    final Dio dio = serve((RequestOptions r) {
      if (r.path == '/api/chat/rooms/r1/messages') {
        if (r.queryParameters['afterSequence'] != null) {
          // Nothing new was said while offline.
          return (status: 200, body: <String, dynamic>{'messages': <dynamic>[], 'more': false});
        }
        return (
          status: 200,
          body: <String, dynamic>{
            'messages': removedMeanwhile
                ? <dynamic>[said(1, 'h-tania', null, null, hidden: true), ...thread.skip(1)]
                : thread,
            'more': false,
          }
        );
      }
      return roomServer()(r);
    });

    await pumpRoom(tester, dio, socket: socket);
    expect(find.text(knefeh), findsOneWidget);

    socket.connected.value = false;
    await tester.pump();
    removedMeanwhile = true;
    socket.connected.value = true;
    await tester.pumpAndSettle();

    expect(find.text(knefeh), findsNothing,
        reason: 'The removed words must not stay on screen for as long as the socket stays up.');
    expect(find.text(en.chatRoomHidden), findsNWidgets(2));
  });
}

/// The app's socket without the network. Frames are pushed by the test and, as with the real one, a
/// frame for a destination nobody is subscribed to reaches nobody.
class _FakeSocket implements UserQueueSocket {
  final Map<String, StreamController<Map<String, dynamic>>> _feeds =
      <String, StreamController<Map<String, dynamic>>>{};

  @override
  final ValueNotifier<bool> connected = ValueNotifier<bool>(true);

  @override
  Stream<Map<String, dynamic>> subscribe(String destination) => _feeds
      .putIfAbsent(destination, () => StreamController<Map<String, dynamic>>.broadcast())
      .stream;

  void frame(String destination, Map<String, dynamic> body) => _feeds[destination]?.add(body);

  @override
  Future<void> close() async {}
}

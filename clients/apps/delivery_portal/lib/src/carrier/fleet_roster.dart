import 'package:delivery_core/delivery_core.dart';
import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:delivery_l10n/delivery_l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../shell/shell.dart';

/// Everything the platform knows about one delivery company's riders, joined once and shared by
/// the Riders HR directory (Figma 112:413) and the rider profile (112:740).
///
/// A rider is only a Keycloak subject to the order service — the fleet list is a list of strings —
/// so every human fact on these pages is joined in from somewhere else:
///
/// * **Name, reference, region, vehicle, start date** come from the rider's own application to
///   this company. The region is the free text they typed; nothing on the platform assigns a rider
///   to a coverage zone, and the directory says so rather than calling it an assignment.
/// * **Presence** is the tracking roster: on duty, signal lost, or off duty. There is no "on break"
///   state anywhere in the platform, and signal lost is never relabelled as one. A rider missing
///   from the roster is one the tracking service has not linked to this company yet, which says
///   nothing about their duty — see [CarrierFleet.bucketOf].
/// * **Suspension** is the onboarding service's standing, carried on this company's own
///   applications listing — see [CarrierFleet.suspensionOf].
/// * **Rating** is the order service's aggregate, for the whole fleet at once. Unrated is "New",
///   never a zero.
/// * **Delivered today** is the carrier-scoped delivered-today list, where absence means zero.
///
/// **Seven requests, however large the fleet.** The page used to follow the fleet list with a rating
/// request and a standing request for every rider — 6 + 2×N, more than eighty for forty riders on
/// every load — and an office behind one address ran into the gateway's per-address rate limit,
/// which the page then drew as nobody suspended and nobody rated. Every per-rider fact now arrives
/// in a fleet-wide read, and nothing here is asked once per rider.
///
/// The first two reads (company, fleet list) are the page; every other source may fail on its own,
/// and a failed source is null here — which the screens draw as a dash — rather than an empty map
/// that would read as "nobody is on duty" or "nobody delivered anything".
class CarrierFleet {
  const CarrierFleet({
    required this.company,
    required this.riders,
    required this.jobs,
    required this.applications,
    required this.waiting,
    required this.applicationsLoaded,
    required this.roster,
    required this.deliveredToday,
    required this.ratings,
  });

  /// The page of work "On a job" is read from when presence cannot be. Small on purpose: it is a
  /// fallback for one badge, not a count anything is summed from.
  static const int jobsWindow = 100;

  final DeliveryProviderInfo company;
  final List<String> riders;

  /// Null when the job board could not be read.
  final List<DeliveryOrder>? jobs;

  /// The rider's own application to this company, by Keycloak subject. Empty when the onboarding
  /// service was unreachable, and missing for a rider the platform attached directly.
  final Map<String, OnboardingApplication> applications;

  /// Undecided rider applications addressed to this company — who "Add Rider" can approve.
  final List<OnboardingApplication> waiting;

  /// Whether the applications call succeeded at all. An empty list and a failed call are different
  /// states, and only one of them means "nobody is waiting".
  final bool applicationsLoaded;

  /// Presence by rider. Null when the tracking service could not be read; a rider missing from a
  /// loaded roster has never declared duty.
  final Map<String, RiderPresence>? roster;

  /// Deliveries today by rider. Absent riders delivered nothing; null means the call failed.
  final Map<String, int>? deliveredToday;

  /// Rating aggregates from the fleet-wide read, which names every rider on the fleet. Empty when
  /// that read failed; a rider missing from it is one whose rating could not be read — never an
  /// unrated rider.
  final Map<String, RiderStanding> ratings;

  /// Loads and joins the fleet. Throws only when the company itself cannot be read — for a user
  /// attached to no company that is the server's 404, and the screens say so.
  static Future<CarrierFleet> load({
    required DeliveryProviderApi provider,
    required OrderApi order,
    required OnboardingApi onboarding,
    required TrackingApi tracking,
    required RiderPerformanceApi performance,
  }) async {
    final List<Object> base = await Future.wait(<Future<Object>>[
      provider.myCompany(),
      provider.myRiders(),
    ]);
    final DeliveryProviderInfo company = base[0] as DeliveryProviderInfo;
    final List<String> riders = base[1] as List<String>;

    // Together: none of these depends on another, and each may fail on its own. Every one is
    // fleet-wide; nothing is asked once per rider.
    final List<Object?> extra = await Future.wait(<Future<Object?>>[
      _tryLoad(() async => (await order.forCarrier(size: jobsWindow)).content),
      // Carries each rider's standing, so a suspension costs no request of its own.
      _tryLoad(() => onboarding.forCompany(company.id, all: true)),
      // Everyone, not just the on-duty half: this is a staff list, and a rider who is off duty has
      // to appear in it as off duty rather than vanish.
      _tryLoad(() => tracking.roster(onDutyOnly: false)),
      _tryLoad(performance.deliveredToday),
      _tryLoad(provider.myRiderRatings),
    ]);
    final List<OnboardingApplication>? applications = extra[1] as List<OnboardingApplication>?;
    final List<RiderPresence>? roster = extra[2] as List<RiderPresence>?;
    final List<RiderDeliveredToday>? today = extra[3] as List<RiderDeliveredToday>?;
    final List<RiderStanding>? ratings = extra[4] as List<RiderStanding>?;

    final Map<String, OnboardingApplication> byRider = <String, OnboardingApplication>{
      if (applications != null)
        for (final OnboardingApplication a in applications)
          if (a.kind == OnboardingKind.rider && a.provisionedUserRef != null)
            a.provisionedUserRef!: a,
    };

    return CarrierFleet(
      company: company,
      riders: riders,
      jobs: extra[0] as List<DeliveryOrder>?,
      applications: byRider,
      waiting: applications
              ?.where((OnboardingApplication a) =>
                  a.kind == OnboardingKind.rider && !a.status.isDecided)
              .toList() ??
          const <OnboardingApplication>[],
      applicationsLoaded: applications != null,
      roster: roster == null
          ? null
          : <String, RiderPresence>{for (final RiderPresence p in roster) p.riderId: p},
      deliveredToday: today == null
          ? null
          : <String, int>{for (final RiderDeliveredToday d in today) d.riderId: d.delivered},
      ratings: <String, RiderStanding>{
        if (ratings != null)
          for (final RiderStanding standing in ratings) standing.riderId: standing,
      },
    );
  }

  static Future<T?> _tryLoad<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ one rider

  String nameOf(String rider) => applications[rider]?.contactName ?? shortRiderRef(rider);

  /// The code on the card's corner: the application's own reference, which is what the company
  /// and the rider already quote to each other. A rider with no application gets the short
  /// subject instead. The platform has no badge numbers, and none is invented here.
  String referenceOf(String rider) => applications[rider]?.reference ?? shortRiderRef(rider);

  /// Where the rider works, from their own application: the region of the company they applied to,
  /// or where they said they work. Null when neither is there — never guessed at from anything else.
  String? regionOf(String rider) {
    final Map<String, String> details = applications[rider]?.details ?? const <String, String>{};
    for (final String key in regionKeys) {
      final String? value = details[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// The same answer as [regionOf], one region at a time: what the zone filter offers and matches.
  ///
  /// A company rider's region is a list — "Achrafieh, Hamra" on the card — and offered whole it made
  /// one filter entry that matched only riders with exactly that list, never a rider working in
  /// Hamra alone. The list's own entries are read ([OnboardingApplication.detailLists]) rather than
  /// the line split at its commas, because a zone's name is the company's own and can hold one.
  /// Empty when [regionOf] is null.
  List<String> regionsOf(String rider) {
    final OnboardingApplication? application = applications[rider];
    if (application == null) return const <String>[];
    for (final String key in regionKeys) {
      final List<String>? entries = application.detailLists[key];
      if (entries != null) return entries;
      final String? value = application.details[key];
      if (value != null && value.trim().isNotEmpty) return <String>[value.trim()];
    }
    return const <String>[];
  }

  /// The application keys a rider's region has been written under, first match wins.
  ///
  /// `companyRegions` comes first: a rider who applies to a company does not choose an area, and the
  /// server records the company's region instead — its zones, or the regions it registered with —
  /// which reads as "Achrafieh, Hamra". `preferredArea` is what the rider wizard writes for a rider
  /// riding for YouDrop, and what every rider wrote before; it was missing from the old table's list,
  /// which left every rider who applied from the app without a region. The rest are older shapes of
  /// the same answer.
  static const List<String> regionKeys = <String>[
    'companyRegions',
    'preferredArea',
    'workRegion',
    'region',
    'city',
    'area',
  ];

  /// The vehicle wire the rider's application carries (`MOTORCYCLE`, `CAR`...), or null.
  String? vehicleOf(String rider) {
    final String? value = applications[rider]?.details[vehicleKey];
    if (value == null || value.trim().isEmpty) return null;
    return value.trim().toUpperCase();
  }

  static const String vehicleKey = 'vehicleType';

  /// The day this company approved them. Null when no decision date is recorded — never the day
  /// they applied, which is a different fact the profile shows under its own label.
  DateTime? joinedOn(String rider) => applications[rider]?.decidedAt;

  bool isOnAJob(String rider) => (jobs ?? const <DeliveryOrder>[])
      .any((DeliveryOrder j) => j.riderId == rider && !j.status.isTerminal);

  /// Null when the delivered-today list could not be read; zero when the rider is absent from it.
  int? deliveredTodayBy(String rider) =>
      deliveredToday == null ? null : deliveredToday![rider] ?? 0;

  /// Whether this rider is suspended, as far as this page can say.
  ///
  /// [RiderSuspension.unknown] is an answer of its own and never folded into "active": when the
  /// applications could not be read, or the listing did not carry a standing, a suspended rider
  /// would otherwise wear a presence badge — "Offline", "Signal lost" — and be offered "Suspend". A
  /// rider the platform attached directly has no application to be suspended through at all.
  RiderSuspension suspensionOf(String rider) {
    if (!applicationsLoaded) return RiderSuspension.unknown;
    final OnboardingApplication? application = applications[rider];
    if (application == null) return RiderSuspension.noApplication;
    return switch (application.suspended) {
      true => RiderSuspension.suspended,
      false => RiderSuspension.active,
      null => RiderSuspension.unknown,
    };
  }

  /// Which stat card the rider counts towards. Null when presence could not be read at all, and
  /// null for a rider the loaded roster says nothing about.
  ///
  /// Missing from the roster is not "offline". The tracking service links a rider to a company when
  /// it hears they joined, or from the orders they carry for it, so a rider it has not linked yet is
  /// absent from the roster whether they are on duty or not. The one thing that does say such a
  /// rider is out working is holding one of this company's unfinished jobs, which counts as on duty
  /// — "available or on a job", as that card says.
  PresenceBucket? bucketOf(String rider) {
    if (roster == null) return null;
    final RiderPresence? presence = roster![rider];
    if (presence == null) return isOnAJob(rider) ? PresenceBucket.onDuty : null;
    return switch (presence.state) {
      PresenceState.onDuty => PresenceBucket.onDuty,
      PresenceState.stale => PresenceBucket.signalLost,
      PresenceState.offDuty => PresenceBucket.offline,
    };
  }

  /// How many riders sit in [bucket]. Null when presence could not be read — a failed roster must
  /// not become "everyone offline".
  int? countIn(PresenceBucket bucket) =>
      roster == null ? null : riders.where((String r) => bucketOf(r) == bucket).length;

  /// Riders whose presence this company cannot see, for the reason on [bucketOf]. They are counted
  /// in no presence card, and the page says how many. Null when the roster could not be read.
  int? get withoutPresence =>
      roster == null ? null : riders.where((String r) => bucketOf(r) == null).length;

  /// The badge, in the precedence the old table used and the design keeps: a suspension beats
  /// presence, and so does a standing that could not be read — a presence badge on a rider who may
  /// be suspended is a guess in the reassuring direction. Presence beats the job board, and with
  /// nothing to go on the badge is left off rather than guessed — which includes a rider missing
  /// from the roster, for the reason on [bucketOf].
  RiderStatus statusOf(String rider) {
    switch (suspensionOf(rider)) {
      case RiderSuspension.suspended:
        return RiderStatus.suspended;
      case RiderSuspension.unknown:
        return RiderStatus.standingUnknown;
      case RiderSuspension.active:
      case RiderSuspension.noApplication:
        break;
    }
    final RiderPresence? presence = roster?[rider];
    if (presence != null) {
      return switch (presence.state) {
        PresenceState.onDuty => RiderStatus.active,
        PresenceState.stale => RiderStatus.signalLost,
        PresenceState.offDuty => RiderStatus.offline,
      };
    }
    if (isOnAJob(rider)) return RiderStatus.onAJob;
    return RiderStatus.unknown;
  }
}

/// The directory's three presence cards.
enum PresenceBucket { onDuty, signalLost, offline }

/// Whether a rider is suspended, as far as the page can say — see [CarrierFleet.suspensionOf].
enum RiderSuspension { active, suspended, unknown, noApplication }

/// One rider's badge. There is deliberately no "on break": the platform has no such state.
enum RiderStatus { suspended, standingUnknown, active, signalLost, offline, onAJob, unknown }

/// Riders are Keycloak subjects; the whole uuid is noise on a card, and it is only shown at all
/// where the platform has no reference or name to put in its place.
String shortRiderRef(String ref) => ref.length <= 8 ? ref : ref.substring(0, 8).toUpperCase();

/// A code — a reference, a masked number — isolated so it reads left to right inside a sentence in
/// either language. Without it an Arabic page's bidi rules carry the code's "#" and hyphens to the
/// wrong ends: "YK-884#".
String ltrIsolate(String code) => '$_leftToRightIsolate$code$_popDirectionalIsolate';

/// U+2066 LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE, built from their code points
/// so that no invisible character sits in the source where a reader cannot see it.
final String _leftToRightIsolate = String.fromCharCode(0x2066);
final String _popDirectionalIsolate = String.fromCharCode(0x2069);

/// A code on a line of its own, laid out left to right whatever the page's direction, yet still at
/// the page's start edge — right on an Arabic page, left on an English one.
class FleetCode extends StatelessWidget {
  const FleetCode(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        textAlign: rtl ? TextAlign.right : TextAlign.left,
        style: style,
      ),
    );
  }
}

/// A national ID as a company sees it on a profile: the last three characters, the rest withheld.
///
/// Enough to tell two riders apart or to match a paper in hand. The number in full is on the
/// verified ID document in the documents card, one deliberate click away, rather than sitting in
/// plain text on a page that stays open on an office screen.
String maskedNationalId(String raw) {
  final String compact = raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  if (compact.length <= 3) return '•••';
  return '•••${compact.substring(compact.length - 3)}';
}

/// "Sep 1, 2026" in the reader's own language, off the Material localizations the portal already
/// loads rather than a second date library.
String consoleDate(BuildContext context, DateTime at) {
  final MaterialLocalizations l = MaterialLocalizations.of(context);
  return '${l.formatShortMonthDay(at)}, ${l.formatYear(at)}';
}

/// A vehicle wire as the reader's own word for it. A wire this build does not know is shown as it
/// arrived rather than guessed at.
String vehicleLabel(DeliveryStrings t, String wire) => switch (wire) {
      'MOTORCYCLE' => t.carrRidersVehicleMotorcycle,
      'CAR' => t.carrRidersVehicleCar,
      'BICYCLE' => t.carrRidersVehicleBicycle,
      'VAN' => t.carrRidersVehicleVan,
      'TRUCK' => t.carrRidersVehicleTruck,
      _ => wire,
    };

/// The server's own sentence where it has one — it is the side that knows why — and a plain
/// "that did not work" where it does not.
String serverMessage(Object error, DeliveryStrings t) {
  if (error is DioException) {
    final dynamic body = error.response?.data;
    if (body is Map) {
      if (body['message'] is String) return body['message'] as String;
      if (body['detail'] is String) return body['detail'] as String;
    }
  }
  return t.thatDidNotWork;
}

/// The badge for [status], or null when there is nothing honest to draw.
Widget? riderStatusPill(DeliveryStrings t, RiderStatus status) => switch (status) {
      RiderStatus.suspended =>
        ConsoleStatusPill(label: t.carrRidersStatusSuspended, accent: DeliveryAccent.critical),
      // Caution, not the quiet slate of "Offline": this badge is a warning that the page cannot
      // vouch for the rider, not the absence of a state.
      RiderStatus.standingUnknown => ConsoleStatusPill(
          label: t.carrRidersStatusStandingUnknown, accent: DeliveryAccent.caution),
      RiderStatus.active =>
        ConsoleStatusPill(label: t.carrRidersStatusActive, accent: DeliveryAccent.positive),
      RiderStatus.signalLost =>
        ConsoleStatusPill(label: t.carrRidersStatusSignalLost, accent: DeliveryAccent.caution),
      // Slate, not the accent palette's violet "neutral": offline is the absence of a state, and
      // a coloured badge would give it a weight it does not have.
      RiderStatus.offline => ConsoleStatusPill.quiet(label: t.carrRidersStatusOffline),
      RiderStatus.onAJob =>
        ConsoleStatusPill(label: t.carrRidersStatusOnAJob, accent: DeliveryAccent.info),
      RiderStatus.unknown => null,
    };

/// A value the platform does not have. Faint, and the same glyph everywhere, so a reader learns
/// in one place that a dash means "not known" rather than "zero".
class FleetUnknown extends StatelessWidget {
  const FleetUnknown({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('—', style: TextStyle(fontSize: 14, color: DeliveryColors.faint));
  }
}

/// Build-time feature flags — for capability differences between the
/// shipped App Store build and the developer's own personal build, not
/// for A/B testing or remote config (this app is zero-backend by design).
library;

/// Whether "Let friends and family know" appears on the round detail
/// screen, adding selected [FamilyMember]s as Optional calendar attendees
/// on the round's event.
///
/// OFF by default — pulled from the general product. Adding family as
/// calendar attendees to a shared event clutters every attendee's
/// calendar with a near-duplicate entry and hands them the full player
/// roster, which doesn't scale to every user's every round. The
/// share-sheet-based replacement that briefly stood in for it wasn't
/// good enough either, so for now the feature is off entirely for
/// everyone except a personal build.
///
/// Enable for a personal build with:
///   flutter build ios --dart-define=ENABLE_FAMILY_CALENDAR_INVITE=true
const bool kEnableFamilyCalendarInvite = bool.fromEnvironment(
  'ENABLE_FAMILY_CALENDAR_INVITE',
);

/// Whether a lapsed or absent subscription blocks scanning a new booking.
///
/// OFF during beta, deliberately. The AED 99/year subscription does not exist
/// in either store yet, so a store check returns "no active purchase" for
/// EVERYONE — turning enforcement on before the product exists would lock out
/// every tester on their next launch.
///
/// Turn this on with --dart-define=ENFORCE_SUBSCRIPTION=true once the
/// subscription is live in App Store Connect and Play Console, and confirmed
/// purchasable on a real device.
const bool kEnforceSubscription = bool.fromEnvironment(
  'ENFORCE_SUBSCRIPTION',
);

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
/// The reason this was off no longer holds: teed_up_full_access (AED 99/year)
/// and teed_up_lifetime_access now exist in BOTH stores — Active on Play,
/// created and priced on Apple — so a store check can return a real answer
/// instead of "no active purchase" for everyone.
///
/// It still ships OFF and is turned on per-build with
/// --dart-define=ENFORCE_SUBSCRIPTION=true, because flipping the default
/// would lock every current tester out of scanning the moment they updated,
/// before any of them has a code to redeem. Apple cannot mint promo codes
/// until the app has an approved App Store version, so the codes do not yet
/// exist to hand out.
///
/// Enforcement blocks CREATING a round only. It never locks anyone out of
/// rounds they already organised — doing so would punish their playing
/// partners for someone else's lapsed card.
const bool kEnforceSubscription = bool.fromEnvironment(
  'ENFORCE_SUBSCRIPTION',
);

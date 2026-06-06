/// Player diff model for the Teed Up golf booking app.
///
/// Computes and represents the difference between two player lists,
/// used to show what changed between consecutive OCR scans or
/// calendar syncs.
library;

import 'player.dart';

/// The difference between an old and new player list.
///
/// Use the [PlayerDiff.compare] factory to compute diffs:
///
/// ```dart
/// final diff = PlayerDiff.compare(
///   oldPlayers: previousScan,
///   newPlayers: latestScan,
/// );
/// print('Added: ${diff.added.length}');
/// ```
class PlayerDiff {
  /// Creates a [PlayerDiff] with pre-computed lists.
  const PlayerDiff({
    required this.added,
    required this.removed,
    required this.unchanged,
  });

  /// Players present in the new list but not in the old list.
  final List<Player> added;

  /// Players present in the old list but not in the new list.
  final List<Player> removed;

  /// Players present in both lists (matched by name, case-insensitive).
  final List<Player> unchanged;

  /// Whether any change was detected.
  bool get hasChanges => added.isNotEmpty || removed.isNotEmpty;

  /// Total player count in the new list (`added + unchanged`).
  int get newTotal => added.length + unchanged.length;

  /// Total player count in the old list (`removed + unchanged`).
  int get oldTotal => removed.length + unchanged.length;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Computes the diff between [oldPlayers] and [newPlayers].
  ///
  /// Matching is done by normalised name (lowercased, trimmed).
  /// Players in [newPlayers] that have no name-match in [oldPlayers]
  /// are considered **added**; the reverse are **removed**.
  factory PlayerDiff.compare({
    required List<Player> oldPlayers,
    required List<Player> newPlayers,
  }) {
    final oldNames = {
      for (final p in oldPlayers) p.name.trim().toLowerCase(): p,
    };
    final newNames = {
      for (final p in newPlayers) p.name.trim().toLowerCase(): p,
    };

    final added = <Player>[];
    final unchanged = <Player>[];

    for (final entry in newNames.entries) {
      if (oldNames.containsKey(entry.key)) {
        unchanged.add(entry.value);
      } else {
        added.add(entry.value.copyWith(isNewlyAdded: true));
      }
    }

    final removed = <Player>[
      for (final entry in oldNames.entries)
        if (!newNames.containsKey(entry.key)) entry.value,
    ];

    return PlayerDiff(
      added: List.unmodifiable(added),
      removed: List.unmodifiable(removed),
      unchanged: List.unmodifiable(unchanged),
    );
  }

  // ---------------------------------------------------------------------------
  // toString
  // ---------------------------------------------------------------------------

  @override
  String toString() =>
      'PlayerDiff(added: ${added.length}, removed: ${removed.length}, '
      'unchanged: ${unchanged.length})';
}

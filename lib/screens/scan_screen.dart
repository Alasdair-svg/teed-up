/// Scan screen — capture or upload a golf booking screenshot.
///
/// ## Flow (spec A6–A9)
///
/// **Upload-first design:**
/// 1. Dashed drop/upload zone — "Drop or upload your booking screenshot"
/// 2. Primary: "Choose a screenshot" (gallery/file picker)
/// 3. Secondary: "Take a photo instead" (camera fallback)
/// 4. Processing state: spinner + "Squinting at the tee sheet…"
///
/// **Review:**
/// 5. Booking-match detection (A7) — if same course+date+time found,
///    shows update banner with player diff (green adds / red removes)
/// 6. Player list (A8) — name-only editable, no manual adds, TBC placeholders
/// 7. Family notify chips (A9) — defaults all selected
/// 8. Confirm button → save/update round → navigate to detail
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/contacts_service.dart';
import '../services/scan_service.dart';
import '../theme/app_theme.dart';
import '../widgets/golf_ball_logo.dart';
import 'round_detail_screen.dart';

/// Scan screen.
class ScanScreen extends StatefulWidget {
  /// Creates a [ScanScreen].
  const ScanScreen({super.key, this.sharedImagePath});

  /// Route name for navigation.
  static const String routeName = '/scan';

  /// Pre-supplied image path (from share-sheet intent, A6).
  final String? sharedImagePath;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

// =============================================================================
// State
// =============================================================================

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _picker = ImagePicker();

  // ── Flow phase ────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.upload;
  bool _isProcessing = false;
  String? _processingImagePath;

  // ── Review state ──────────────────────────────────────────────────────────
  GolfRound? _matchedRound;          // Existing round from A7 match detection
  List<Player> _reviewPlayers = [];  // Editable player list (A8)
  Set<int> _selectedFamilyIndices = {}; // Family chips (A9)
  String _courseReview = '';
  DateTime? _dateReview;
  DateTime? _timeReview;
  String? _bookingRefReview;
  String? _shareSource; // e.g. "Shared from Photos"

  @override
  void initState() {
    super.initState();
    if (widget.sharedImagePath != null) {
      // Came from share-sheet — skip upload phase and go straight to processing
      _shareSource = 'Shared from Photos';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processImage(widget.sharedImagePath!);
      });
    }
  }

  @override
  void dispose() {
    _deleteTempImage(_processingImagePath);
    super.dispose();
  }

  Future<void> _deleteTempImage(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('[ScanScreen] Could not delete temp image: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Image capture
  // ---------------------------------------------------------------------------

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xFile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (xFile == null || !mounted) return;
      if (source == ImageSource.gallery) {
        _shareSource = null; // User picked themselves — no source tag
      } else {
        _shareSource = 'Camera';
      }
      await _processImage(xFile.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open image: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // OCR + match detection
  // ---------------------------------------------------------------------------

  Future<void> _processImage(String imagePath) async {
    _processingImagePath = imagePath;
    setState(() {
      _phase = _Phase.processing;
      _isProcessing = true;
    });

    try {
      final scanService = ScanService();
      GolfRound? parsed;
      try {
        parsed = await scanService.parseScreenshotFromFile(imagePath);
      } on ScanException catch (e) {
        debugPrint('[ScanScreen] OCR failed: $e');
      } finally {
        await scanService.dispose();
        await _deleteTempImage(imagePath);
        _processingImagePath = null;
      }

      if (!mounted) return;

      if (parsed == null) {
        setState(() => _phase = _Phase.upload);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't read the booking — try a clearer photo."),
          backgroundColor: AppColors.error,
        ));
        return;
      }

      // ── Auto-resolve emails from contacts ───────────────────────────
      List<Player> players = parsed.players;
      try {
        final resolved = await ContactsService.instance
            .resolvePlayerEmails(players.map((p) => p.name).toList());
        if (resolved.isNotEmpty) {
          players = players.map((p) {
            final email = resolved[p.name];
            if (email != null) {
              return p.copyWith(
                email: email,
                contactSource: ContactSource.iCloud,
              );
            }
            return p;
          }).toList();
        }
      } catch (e) {
        debugPrint('[ScanScreen] Contact resolution failed: $e');
      }

      // ── A7: Booking match detection ─────────────────────────────────
      final appState = context.read<AppState>();
      final matched = appState.findMatchingRound(
        course: parsed.courseName,
        date: parsed.date,
        teeTime: parsed.teeTime,
      );

      // ── A9: Pre-select all family members ───────────────────────────
      final familyCount = appState.familyMembers.length;

      setState(() {
        _matchedRound = matched;
        _reviewPlayers = players;
        _courseReview = parsed!.courseName;
        _dateReview = parsed.date;
        _timeReview = parsed.teeTime;
        _bookingRefReview = parsed.bookingRef;
        _selectedFamilyIndices =
            Set.from(List.generate(familyCount, (i) => i));
        _phase = _Phase.review;
        _isProcessing = false;
      });
    } catch (e, st) {
      debugPrint('[ScanScreen] processImage error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.upload;
        _isProcessing = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Confirm & save
  // ---------------------------------------------------------------------------

  Future<void> _confirm() async {
    final appState = context.read<AppState>();
    final now = DateTime.now();

    // Build the new round
    final round = GolfRound(
      id: _matchedRound?.id ??
          'round_${now.millisecondsSinceEpoch}',
      courseName: _courseReview,
      date: _dateReview ?? now,
      teeTime: _timeReview ?? now,
      players: _reviewPlayers,
      bookingRef: _bookingRefReview,
      familyNotified: _selectedFamilyIndices.isNotEmpty,
    );

    // Selected family members for notify
    final selectedFamily = _selectedFamilyIndices
        .map((i) => appState.familyMembers[i])
        .toList();

    if (_matchedRound != null) {
      await appState.updateRound(round, selectedFamily: selectedFamily);
    } else {
      await appState.saveRound(round, selectedFamily: selectedFamily);
    }

    if (!mounted) return;

    final action = _matchedRound != null ? 'Round updated' : 'Round saved';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(action),
      backgroundColor: AppColors.success,
    ));

    // Navigate to round detail (from-scan mode = shows Done button)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RoundDetailScreen(
          roundId: round.id,
          fromScan: true,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Scan booking'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: switch (_phase) {
        _Phase.upload    => _UploadPhase(onPick: _pickImage),
        _Phase.processing => _ProcessingPhase(),
        _Phase.review    => _buildReview(context),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Review phase
  // ---------------------------------------------------------------------------

  Widget _buildReview(BuildContext context) {
    final appState = context.read<AppState>();
    final isUpdate = _matchedRound != null;

    // Player diff for update banner (A7)
    final addedNames = isUpdate
        ? _reviewPlayers
            .where((p) =>
                !_matchedRound!.players.any((o) =>
                    o.name.toLowerCase() == p.name.toLowerCase()))
            .toList()
        : <Player>[];
    final removedPlayers = isUpdate
        ? _matchedRound!.players
            .where((o) =>
                !_reviewPlayers.any((p) =>
                    p.name.toLowerCase() == o.name.toLowerCase()))
            .toList()
        : <Player>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Share source tag (A6) ─────────────────────────────────
          if (_shareSource != null) ...[
            _SourceTag(source: _shareSource!),
            const SizedBox(height: 12),
          ],

          // ── Update banner (A7) ────────────────────────────────────
          if (isUpdate) ...[
            _UpdateBanner(
              courseName: _courseReview,
              added: addedNames,
              removed: removedPlayers,
              onSaveAsNew: () => setState(() => _matchedRound = null),
            ),
            const SizedBox(height: 16),
          ],

          // ── Booking details (read-only summary) ───────────────────
          _BookingSummaryCard(
            course: _courseReview,
            date: _dateReview,
            teeTime: _timeReview,
          ),
          const SizedBox(height: 20),

          // ── Player list (A8) ──────────────────────────────────────
          _SectionHeader(
            title: 'Who\'s playing? Booking says ${_reviewPlayers.length}',
          ),
          const SizedBox(height: 12),
          ..._reviewPlayers.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return _PlayerReviewRow(
              player: p,
              onNameChanged: (name) {
                setState(() {
                  _reviewPlayers[i] =
                      _reviewPlayers[i].copyWith(name: name);
                });
              },
              isNew: addedNames.any(
                  (a) => a.name.toLowerCase() == p.name.toLowerCase()),
            );
          }),

          const SizedBox(height: 20),

          // ── Family notify (A9) ────────────────────────────────────
          _FamilyNotifySection(
            members: appState.familyMembers,
            selected: _selectedFamilyIndices,
            onToggle: (i) => setState(() {
              if (_selectedFamilyIndices.contains(i)) {
                _selectedFamilyIndices.remove(i);
              } else {
                _selectedFamilyIndices.add(i);
              }
            }),
          ),
          const SizedBox(height: 28),

          // ── Confirm ───────────────────────────────────────────────
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _confirm,
              child: Text(
                isUpdate ? 'Confirm & update round' : 'Looks good — save it',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Phase enum
// =============================================================================

enum _Phase { upload, processing, review }

// =============================================================================
// Upload phase (A6)
// =============================================================================

class _UploadPhase extends StatelessWidget {
  const _UploadPhase({required this.onPick});
  final Future<void> Function(ImageSource) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Dashed upload zone ─────────────────────────────────────
          GestureDetector(
            onTap: () => onPick(ImageSource.gallery),
            child: _DashedZone(),
          ),
          const SizedBox(height: 24),

          // ── Primary: Choose screenshot ─────────────────────────────
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => onPick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose a screenshot'),
            ),
          ),
          const SizedBox(height: 12),

          // ── Secondary: Camera fallback ─────────────────────────────
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => onPick(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined, size: 20),
              label: const Text('Take a photo instead'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedZone extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.palePurple.withValues(alpha: 0.4),
        borderRadius: AppRadius.cardBorder,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
          width: 1.5,
          // Dashed effect via custom painter below
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.upload_file_outlined,
              size: 44, color: AppColors.primary),
          SizedBox(height: 14),
          Text(
            'Drop or upload your booking screenshot',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 15,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'or tap below to choose from your library',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Processing phase
// =============================================================================

class _ProcessingPhase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GolfBallLogo(size: 100, animate: true, showTee: false, showGlow: true),
          SizedBox(height: 24),
          Text(
            'Squinting at the tee sheet…',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 16,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Review components
// =============================================================================

// ── Source tag ───────────────────────────────────────────────────────────────

class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryPale,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.share_outlined,
                size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              source,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Update banner (A7) ───────────────────────────────────────────────────────

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.courseName,
    required this.added,
    required this.removed,
    required this.onSaveAsNew,
  });

  final String courseName;
  final List<Player> added;
  final List<Player> removed;
  final VoidCallback onSaveAsNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.update_rounded,
                  size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This looks like an update to your existing round at $courseName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                ),
              ),
            ],
          ),
          if (added.isNotEmpty || removed.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final p in added)
                _DiffChip(name: p.name, isAdd: true),
              for (final p in removed)
                _DiffChip(name: p.name, isAdd: false),
            ]),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onSaveAsNew,
            child: Text(
              'Not the same round? Save as new instead',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffChip extends StatelessWidget {
  const _DiffChip({required this.name, required this.isAdd});
  final String name;
  final bool isAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isAdd
            ? AppColors.successLight
            : AppColors.errorLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAdd ? Icons.add_rounded : Icons.remove_rounded,
              size: 13,
              color: isAdd ? AppColors.success : AppColors.error),
          const SizedBox(width: 3),
          Text(
            name,
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              color: isAdd ? AppColors.success : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Booking summary ──────────────────────────────────────────────────────────

class _BookingSummaryCard extends StatelessWidget {
  const _BookingSummaryCard({
    required this.course,
    required this.date,
    required this.teeTime,
  });
  final String course;
  final DateTime? date;
  final DateTime? teeTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(course,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.textDark)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                date != null
                    ? DateFormat('EEE, d MMM yyyy').format(date!)
                    : '—',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              const Icon(Icons.access_time_rounded,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                teeTime != null
                    ? DateFormat('HH:mm').format(teeTime!)
                    : '—',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Player row (A8) — name-correction only ───────────────────────────────────

class _PlayerReviewRow extends StatefulWidget {
  const _PlayerReviewRow({
    required this.player,
    required this.onNameChanged,
    this.isNew = false,
  });
  final Player player;
  final ValueChanged<String> onNameChanged;
  final bool isNew;

  @override
  State<_PlayerReviewRow> createState() => _PlayerReviewRowState();
}

class _PlayerReviewRowState extends State<_PlayerReviewRow> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final isTbcPlaceholder = widget.player.name.trim().isEmpty || widget.player.name.trim().toLowerCase() == 'tbc';
    _ctrl = TextEditingController(
      text: isTbcPlaceholder ? '' : widget.player.name,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTbc = widget.player.name.trim().isEmpty ||
        widget.player.name.trim().toLowerCase() == 'tbc' ||
        widget.player.name.toLowerCase() == 'player tbc';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isNew
              ? AppColors.successLight
              : AppColors.offWhite,
          borderRadius: AppRadius.cardBorder,
          border: Border.all(
            color: widget.isNew
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.grey,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 18,
              backgroundColor: isTbc
                  ? AppColors.greyLight
                  : AppColors.primaryPale,
              child: Text(
                isTbc ? '?' : (widget.player.name.isNotEmpty
                    ? widget.player.name[0].toUpperCase()
                    : '?'),
                style: TextStyle(
                  color: isTbc ? AppColors.textMuted : AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isTbc)
                    // TBC slot — shows placeholder, not editable
                    Text(
                      'Player TBC',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                    )
                  else
                    // Name-only inline edit
                    TextField(
                      controller: _ctrl,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: 'Player name',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      onChanged: widget.onNameChanged,
                    ),
                  if (widget.player.email != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.player.email!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.isNew)
              const Icon(Icons.fiber_new_rounded,
                  size: 18, color: AppColors.success),
          ],
        ),
      ),
    );
  }
}

// ── Family notify (A9) ───────────────────────────────────────────────────────

class _FamilyNotifySection extends StatelessWidget {
  const _FamilyNotifySection({
    required this.members,
    required this.selected,
    required this.onToggle,
  });
  final List<FamilyMember> members;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.offWhite,
          borderRadius: AppRadius.cardBorder,
          border: Border.all(color: AppColors.grey),
        ),
        child: Text(
          'No friends or family added yet — add them in Settings.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Let friends & family know'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: members.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            final isOn = selected.contains(i);
            return FilterChip(
              label: Text(m.name),
              selected: isOn,
              onSelected: (_) => onToggle(i),
              avatar: CircleAvatar(
                radius: 12,
                backgroundColor: isOn
                    ? AppColors.primary
                    : AppColors.primaryPale,
                child: Text(
                  m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isOn ? AppColors.white : AppColors.primary,
                  ),
                ),
              ),
              selectedColor: AppColors.primaryPale,
              checkmarkColor: AppColors.primary,
              labelStyle: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: isOn ? AppColors.primary : AppColors.textBody,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Shared section header ────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

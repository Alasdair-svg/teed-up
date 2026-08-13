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

import 'dart:async';
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
  String? _processingImagePath;

  // ── Processing step indicator (spec C4) ─────────────────────────────────
  static const List<String> _processingSteps = [
    'Reading screenshot image…',
    'Extracting course, date & tee time…',
    'Matching playing partners…',
  ];
  int _processingStep = 0;
  bool _canCancelToManual = false;
  Timer? _stepTimer;
  Timer? _cancelRevealTimer;
  // Set when the user bails to manual entry mid-scan — the in-flight OCR
  // future is left to finish in the background but its result is ignored.
  bool _abandonedProcessing = false;

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
    _stepTimer?.cancel();
    _cancelRevealTimer?.cancel();
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
    _abandonedProcessing = false;
    setState(() {
      _phase = _Phase.processing;
      _processingStep = 0;
      _canCancelToManual = false;
    });

    // Advance the 3-step status list every ~1.3s — the underlying OCR call
    // is a single opaque Future, not actually phased, so this is an honest
    // approximation of progress rather than a literal per-phase callback.
    _stepTimer?.cancel();
    _stepTimer = Timer.periodic(const Duration(milliseconds: 1300), (_) {
      if (!mounted || _abandonedProcessing) return;
      if (_processingStep < _processingSteps.length - 1) {
        setState(() => _processingStep++);
      }
    });

    // After 5s, reveal the "Cancel & enter manually" escape hatch (spec C4).
    _cancelRevealTimer?.cancel();
    _cancelRevealTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _abandonedProcessing) return;
      setState(() => _canCancelToManual = true);
    });

    try {
      final scanService = ScanService();
      GolfRound? parsed;
      String? failureMessage;
      try {
        parsed = await scanService.parseScreenshotFromFile(imagePath);
      } on ScanException catch (e) {
        debugPrint('[ScanScreen] OCR failed: $e');
        failureMessage = e.message;
      } finally {
        await scanService.dispose();
        await _deleteTempImage(imagePath);
        _processingImagePath = null;
      }

      _stepTimer?.cancel();
      _cancelRevealTimer?.cancel();

      if (!mounted || _abandonedProcessing) return;

      if (parsed == null) {
        setState(() => _phase = _Phase.upload);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            failureMessage ?? "Couldn't read the booking — try a clearer photo.",
          ),
          backgroundColor: AppColors.error,
        ));
        return;
      }

      // ── Low-confidence parse: OCR found text, but none of it matched a
      // known booking format (no course, no players). Previously this fell
      // through to a review screen with everything defaulted/empty and no
      // way to add players — a silent, confusing dead end. Route to Manual
      // Entry instead, which supports adding players from scratch.
      final lowConfidence =
          parsed.courseName == 'Unknown Course' && parsed.players.isEmpty;
      if (lowConfidence) {
        if (!mounted) return;
        setState(() => _phase = _Phase.manual);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            "Couldn't confidently read the course, time, or players from "
            "that screenshot — enter the details manually instead.",
          ),
          backgroundColor: AppColors.warning,
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

      if (!mounted || _abandonedProcessing) return;

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
      });
    } catch (e, st) {
      debugPrint('[ScanScreen] processImage error: $e\n$st');
      _stepTimer?.cancel();
      _cancelRevealTimer?.cancel();
      if (!mounted || _abandonedProcessing) return;
      setState(() => _phase = _Phase.upload);
    }
  }

  /// Bails out of the processing phase into manual entry (spec C4's 5s
  /// "Cancel & enter manually" escape hatch). The in-flight OCR future is
  /// left to run to completion in the background — its result is simply
  /// ignored via [_abandonedProcessing] once it resolves.
  void _cancelToManual() {
    _abandonedProcessing = true;
    _stepTimer?.cancel();
    _cancelRevealTimer?.cancel();
    setState(() => _phase = _Phase.manual);
  }

  /// Runs the manually-entered booking through the same A7 match-detection
  /// logic as an OCR'd scan, then lands on the normal review screen.
  void _finishManualEntry({
    required String course,
    required DateTime date,
    required DateTime teeTime,
    required List<Player> players,
  }) {
    final appState = context.read<AppState>();
    final matched = appState.findMatchingRound(
      course: course,
      date: date,
      teeTime: teeTime,
    );
    final familyCount = appState.familyMembers.length;

    setState(() {
      _matchedRound = matched;
      _reviewPlayers = players;
      _courseReview = course;
      _dateReview = date;
      _timeReview = teeTime;
      _bookingRefReview = null;
      _selectedFamilyIndices = Set.from(List.generate(familyCount, (i) => i));
      _phase = _Phase.review;
    });
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
        _Phase.upload => _UploadPhase(onPick: _pickImage),
        _Phase.processing => _ProcessingPhase(
            currentStep: _processingStep,
            steps: _processingSteps,
            showCancel: _canCancelToManual,
            onCancel: _cancelToManual,
          ),
        _Phase.manual => _ManualEntryPhase(onContinue: _finishManualEntry),
        _Phase.review => _buildReview(context),
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

enum _Phase { upload, processing, manual, review }

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
  const _ProcessingPhase({
    required this.currentStep,
    required this.steps,
    required this.showCancel,
    required this.onCancel,
  });

  final int currentStep;
  final List<String> steps;
  final bool showCancel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GolfBallLogo(
                size: 100, animate: true, showTee: false, showGlow: true),
            const SizedBox(height: 28),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _ProcessingStepRow(
                  label: steps[i],
                  state: i < currentStep
                      ? _StepState.done
                      : i == currentStep
                          ? _StepState.active
                          : _StepState.pending,
                ),
              ),
            if (showCancel) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('Cancel & enter manually'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _StepState { pending, active, done }

class _ProcessingStepRow extends StatelessWidget {
  const _ProcessingStepRow({required this.label, required this.state});
  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (state) {
      _StepState.done => AppColors.success,
      _StepState.active => AppColors.primary,
      _StepState.pending => AppColors.grey,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: switch (state) {
            _StepState.done => const Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.success),
            _StepState.active => const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            _StepState.pending => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.grey,
                  shape: BoxShape.circle,
                ),
              ),
          },
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight:
                state == _StepState.active ? FontWeight.w600 : FontWeight.w400,
            fontSize: 14,
            color: state == _StepState.pending
                ? AppColors.textMuted
                : dotColor == AppColors.primary
                    ? AppColors.textDark
                    : dotColor,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Manual entry phase (spec C4) — course/date/time + name+email player form.
// Feeds the same A7 match/diff pipeline as an OCR'd scan.
// =============================================================================

class _ManualEntryPhase extends StatefulWidget {
  const _ManualEntryPhase({required this.onContinue});

  final void Function({
    required String course,
    required DateTime date,
    required DateTime teeTime,
    required List<Player> players,
  }) onContinue;

  @override
  State<_ManualEntryPhase> createState() => _ManualEntryPhaseState();
}

class _ManualEntryPhaseState extends State<_ManualEntryPhase> {
  final _courseController = TextEditingController();
  final _playerNameController = TextEditingController();
  final _playerEmailController = TextEditingController();
  DateTime? _date;
  DateTime? _time;
  final List<Player> _players = [];

  @override
  void dispose() {
    _courseController.dispose();
    _playerNameController.dispose();
    _playerEmailController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _courseController.text.trim().isNotEmpty && _date != null && _time != null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time != null
          ? TimeOfDay(hour: _time!.hour, minute: _time!.minute)
          : TimeOfDay.now(),
    );
    if (picked != null) {
      final base = _date ?? DateTime.now();
      setState(() => _time =
          DateTime(base.year, base.month, base.day, picked.hour, picked.minute));
    }
  }

  void _addPlayer() {
    final name = _playerNameController.text.trim();
    if (name.isEmpty) return;
    final email = _playerEmailController.text.trim();
    setState(() {
      _players.add(Player(
        id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        email: email.isEmpty ? null : email,
      ));
      _playerNameController.clear();
      _playerEmailController.clear();
    });
  }

  void _removePlayer(int index) => setState(() => _players.removeAt(index));

  void _continue() {
    if (!_canContinue) return;
    final base = _date!;
    final teeTime = _time ?? base;
    widget.onContinue(
      course: _courseController.text.trim(),
      date: DateTime(base.year, base.month, base.day),
      teeTime: teeTime,
      players: _players,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter booking details',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'No worries — you can add everything by hand instead.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _courseController,
            decoration: const InputDecoration(
              labelText: 'Course',
              prefixIcon: Icon(Icons.golf_course_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(
                    _date != null
                        ? DateFormat('EEE, d MMM').format(_date!)
                        : 'Date',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(
                    _time != null ? DateFormat('HH:mm').format(_time!) : 'Time',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Players',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _players.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: AppRadius.cardBorder,
                border: Border.all(color: AppColors.grey),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_players[i].name,
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    )),
                        if (_players[i].email != null)
                          Text(_players[i].email!,
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textMuted,
                    onPressed: () => _removePlayer(i),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _playerNameController,
            decoration: const InputDecoration(
              labelText: 'Player name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _playerEmailController,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _addPlayer,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add player'),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 56,
            child: Opacity(
              opacity: _canContinue ? 1.0 : 0.4,
              child: ElevatedButton(
                onPressed: _canContinue ? _continue : null,
                child: const Text('Continue to review'),
              ),
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

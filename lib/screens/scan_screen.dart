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
import 'verify_emails_screen.dart';

/// Scan screen for capturing or selecting a booking confirmation image.
///
/// Allows the user to:
/// 1. Take a photo or pick from gallery
/// 2. View the scanned image
/// 3. Edit all parsed fields (course, date, time, players, ref)
/// 4. See amendment diffs if an existing booking is found
/// 5. Continue to email verification or cancel
class ScanScreen extends StatefulWidget {
  /// Creates a [ScanScreen].
  const ScanScreen({super.key});

  /// Route name for navigation.
  static const String routeName = '/scan';

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _courseController = TextEditingController();
  final TextEditingController _refController = TextEditingController();
  final TextEditingController _newPlayerController = TextEditingController();

  bool _hasImage = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Pre-populate fields from scan state if available
    final state = context.read<AppState>();
    _courseController.text = state.scannedCourseName ?? '';
    _refController.text = state.scannedBookingRef ?? '';
    if (state.scannedImagePath != null) {
      _hasImage = true;
    }
  }

  @override
  void dispose() {
    _courseController.dispose();
    _refController.dispose();
    _newPlayerController.dispose();
    // Clean up any residual temp image (e.g. if user backs out mid-scan).
    final residualPath = context.read<AppState>().scannedImagePath;
    _deleteTempImage(residualPath);
    super.dispose();
  }

  /// Deletes a temporary image file after OCR processing.
  ///
  /// Called after every scan attempt — success, failure, or cancellation —
  /// so booking confirmation images are never left on disk.
  Future<void> _deleteTempImage(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      // Non-critical — log and continue. The sandbox protects the file anyway.
      debugPrint('[ScanScreen] Failed to delete temp image: $e');
    }
  }

  Future<void> _captureImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );

      if (image == null || !mounted) return;

      setState(() {
        _hasImage = true;
        _isProcessing = true;
      });

      final state = context.read<AppState>();
      state.setScannedImage(image.path);

      // Run OCR via ML Kit on-device text recognition.
      final scanService = ScanService();
      try {
        final round = await scanService.parseScreenshotFromFile(image.path);

        if (!mounted) return;

        // Feed parsed OCR results into app state.
        state.updateScanResults(
          courseName: round.courseName,
          date: round.date,
          teeTime: round.teeTime,
          bookingRef: round.bookingRef,
          players: round.players,
        );

        // Update text controllers with parsed values.
        _courseController.text = round.courseName;
        _refController.text = round.bookingRef ?? '';

        // Auto-resolve player emails from device contacts.
        final playerNames = round.players.map((p) => p.name).toList();
        if (playerNames.isNotEmpty) {
          try {
            final contactsService = ContactsService();
            final resolved = await contactsService.resolvePlayerEmails(playerNames);
            if (resolved.isNotEmpty && mounted) {
              final updatedPlayers = state.scannedPlayers.map((p) {
                final email = resolved[p.name];
                if (email != null) {
                  return p.copyWith(
                    email: email,
                    contactSource: ContactSource.iCloud,
                  );
                }
                return p;
              }).toList();
              state.updateScanResults(players: updatedPlayers);
            }
          } catch (contactErr) {
            debugPrint('Contact resolution failed: $contactErr');
            // Non-fatal — user can enter emails manually.
          }
        }
      } on ScanException catch (scanErr) {
        debugPrint('OCR scan failed: $scanErr');
        // OCR returned no text — user can fill fields manually.
      } finally {
        await scanService.dispose();
        // Always delete the temp capture — image has been processed.
        await _deleteTempImage(image.path);
      }

      if (!mounted) return;

      setState(() => _isProcessing = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture image: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _pickDate(AppState state) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: state.scannedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                onPrimary: AppColors.white,
              ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      state.updateScanResults(date: picked);
    }
  }

  Future<void> _pickTime(AppState state) async {
    final initial = state.scannedTeeTime != null
        ? TimeOfDay.fromDateTime(state.scannedTeeTime!)
        : TimeOfDay.now();

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                onPrimary: AppColors.white,
              ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      final now = DateTime.now();
      state.updateScanResults(
        teeTime: DateTime(now.year, now.month, now.day, picked.hour, picked.minute),
      );
    }
  }

  void _removePlayer(AppState state, int index) {
    final players = List<Player>.from(state.scannedPlayers);
    players.removeAt(index);
    state.updateScanResults(players: players);
  }

  void _addPlayer(AppState state) {
    final name = _newPlayerController.text.trim();
    if (name.isEmpty) return;

    final players = List<Player>.from(state.scannedPlayers);
    players.add(Player(
      id: 'player_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      contactSource: ContactSource.manual,
    ));
    state.updateScanResults(players: players);
    _newPlayerController.clear();
  }

  void _continueToVerify() {
    final state = context.read<AppState>();
    // Update course name & ref from text fields
    state.updateScanResults(
      courseName: _courseController.text.trim(),
      bookingRef: _refController.text.trim(),
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const VerifyEmailsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: const Text('Scan Booking'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            context.read<AppState>().clearScanState();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Image Preview ──────────────────────────────
                _ImagePreview(
                  imagePath: state.scannedImagePath,
                  hasImage: _hasImage,
                  isProcessing: _isProcessing,
                ),
                const SizedBox(height: 16),

                // ── Capture Buttons ────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _captureImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_rounded, size: 20),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _captureImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded, size: 20),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Parsed Result Card ─────────────────────────
                if (_hasImage && !_isProcessing) ...[
                  _SectionHeader(title: 'Booking Details'),
                  const SizedBox(height: 12),

                  // Course name
                  TextField(
                    controller: _courseController,
                    decoration: const InputDecoration(
                      labelText: 'Course Name',
                      prefixIcon: Icon(Icons.golf_course_rounded),
                    ),
                    onChanged: (v) =>
                        state.updateScanResults(courseName: v.trim()),
                  ),
                  const SizedBox(height: 16),

                  // Date picker
                  _TapField(
                    label: 'Date',
                    value: state.scannedDate != null
                        ? DateFormat('EEE, d MMM yyyy')
                            .format(state.scannedDate!)
                        : 'Tap to select',
                    icon: Icons.calendar_today_rounded,
                    onTap: () => _pickDate(state),
                  ),
                  const SizedBox(height: 16),

                  // Time picker
                  _TapField(
                    label: 'Tee Time',
                    value: state.scannedTeeTime != null
                        ? DateFormat('HH:mm').format(state.scannedTeeTime!)
                        : 'Tap to select',
                    icon: Icons.access_time_rounded,
                    onTap: () => _pickTime(state),
                  ),
                  const SizedBox(height: 16),

                  // Booking ref
                  TextField(
                    controller: _refController,
                    decoration: const InputDecoration(
                      labelText: 'Booking Reference',
                      prefixIcon: Icon(Icons.confirmation_number_rounded),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Players section
                  _SectionHeader(title: 'Players'),
                  const SizedBox(height: 12),
                  _PlayersEditor(
                    players: state.scannedPlayers,
                    newPlayerController: _newPlayerController,
                    onRemove: (i) => _removePlayer(state, i),
                    onAdd: () => _addPlayer(state),
                  ),
                  const SizedBox(height: 24),

                  // ── Amendment Banner ───────────────────────────
                  if (state.isExistingBooking) ...[
                    _AmendmentBanner(
                      added: state.addedPlayers,
                      removed: state.removedPlayers,
                      unchanged: state.unchangedPlayers,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Action Buttons ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _continueToVerify,
                      child: const Text('Continue to Email Verification'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        context.read<AppState>().clearScanState();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Image preview area at the top of the scan screen.
class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.imagePath,
    required this.hasImage,
    required this.isProcessing,
  });

  final String? imagePath;
  final bool hasImage;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.greyLight,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.grey),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isProcessing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Processing image…',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (hasImage && imagePath != null) {
      return Image.file(
        File(imagePath!),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.document_scanner_rounded,
            size: 48,
            color: AppColors.textMuted,
          ),
          SizedBox(height: 12),
          Text(
            'Capture or select a booking image',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header with Outfit semi-bold styling.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

/// A tappable field that looks like a text input but opens a picker.
class _TapField extends StatelessWidget {
  const _TapField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.chevron_right_rounded),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            color: value.startsWith('Tap')
                ? AppColors.textMuted
                : AppColors.textBody,
          ),
        ),
      ),
    );
  }
}

/// Editable player list with chips and add button.
class _PlayersEditor extends StatelessWidget {
  const _PlayersEditor({
    required this.players,
    required this.newPlayerController,
    required this.onRemove,
    required this.onAdd,
  });

  final List<Player> players;
  final TextEditingController newPlayerController;
  final void Function(int index) onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current players as chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < players.length; i++)
              Chip(
                label: Text(players[i].name),
                deleteIcon: const Icon(Icons.close_rounded, size: 16),
                onDeleted: () => onRemove(i),
                backgroundColor: AppColors.primaryPale,
                deleteIconColor: AppColors.primary,
                labelStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Add new player row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: newPlayerController,
                decoration: const InputDecoration(
                  hintText: 'Add player name',
                  prefixIcon: Icon(Icons.person_add_rounded),
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Amber banner showing booking amendment diffs.
class _AmendmentBanner extends StatelessWidget {
  const _AmendmentBanner({
    required this.added,
    required this.removed,
    required this.unchanged,
  });

  final List<Player> added;
  final List<Player> removed;
  final List<Player> unchanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: AppRadius.cardBorder,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
              SizedBox(width: 8),
              Text(
                'Existing booking found',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Added players
          if (added.isNotEmpty)
            ...added.map((p) => _DiffRow(
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  prefix: 'Adding:',
                  name: p.name,
                )),

          // Removed players
          if (removed.isNotEmpty)
            ...removed.map((p) => _DiffRow(
                  icon: Icons.cancel_rounded,
                  color: AppColors.error,
                  prefix: 'Removing:',
                  name: p.name,
                )),

          // Unchanged players
          if (unchanged.isNotEmpty)
            ...unchanged.map((p) => _DiffRow(
                  icon: Icons.swap_horiz_rounded,
                  color: AppColors.textMuted,
                  prefix: 'Unchanged:',
                  name: p.name,
                )),
        ],
      ),
    );
  }
}

/// A single row in the amendment diff.
class _DiffRow extends StatelessWidget {
  const _DiffRow({
    required this.icon,
    required this.color,
    required this.prefix,
    required this.name,
  });

  final IconData icon;
  final Color color;
  final String prefix;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$prefix ',
            style: TextStyle(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: color,
            ),
          ),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

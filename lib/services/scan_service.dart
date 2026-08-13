/// OCR scan service for the Teed Up golf booking app.
///
/// Uses Google ML Kit's on-device text recognition to extract text from
/// booking confirmation screenshots, then delegates to [BookingParser]
/// for structured field extraction.
///
/// All processing runs on-device — no cloud calls, no API keys required.
library;

import 'dart:async' show TimeoutException;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show Size;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/golf_round.dart';
import '../models/player.dart';
import 'booking_parser.dart';

/// Service that converts a booking screenshot into a [GolfRound].
///
/// Wraps ML Kit text recognition and the [BookingParser] into a single
/// entry-point method. Designed to be used with [Provider] for state
/// management.
///
/// Two input modes are supported:
/// - [parseScreenshotFromFile] — preferred; ML Kit auto-detects metadata.
/// - [parseScreenshotFromBytes] — fallback for in-memory images (gallery).
///
/// ```dart
/// final scanService = ScanService();
/// final round = await scanService.parseScreenshotFromFile(pickedPath);
/// // round.course, round.teeTime, etc. are populated.
/// await scanService.dispose();
/// ```
class ScanService {
  /// Creates a [ScanService].
  ///
  /// Optionally accepts a [TextRecognizer] for dependency injection in
  /// tests. If not provided, a Latin-script recogniser is created.
  ScanService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer();

  final TextRecognizer _recognizer;

  /// Whether the service has been disposed.
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // Public API — file path (preferred)
  // ---------------------------------------------------------------------------

  /// Extracts a [GolfRound] from a booking screenshot at [filePath].
  ///
  /// This is the **preferred** entry point because ML Kit automatically
  /// reads image dimensions and format from the file — no metadata
  /// guessing required.
  ///
  /// [filePath] should be an absolute path to a JPEG or PNG on disk
  /// (e.g. from `image_picker` or `camera`).
  ///
  /// Returns a [GolfRound] with best-effort field extraction. Fields that
  /// could not be parsed are set to safe defaults (see [BookingParser]):
  /// - `courseName` → `"Unknown Course"`
  /// - `teeTime` → round date at midnight
  /// - `date` → `DateTime.now()`
  /// - `id` → `"pending_<timestamp>"`
  ///
  /// Throws [ScanException] if OCR fails completely.
  Future<GolfRound> parseScreenshotFromFile(String filePath) async {
    _ensureNotDisposed();

    final rawText = await _recogniseFromFile(filePath);
    if (rawText.trim().isEmpty) {
      throw const ScanException('No text detected in image');
    }
    return _withTbcSlots(BookingParser.parseBookingText(rawText), rawText);
  }

  // ---------------------------------------------------------------------------
  // Public API — byte array (fallback)
  // ---------------------------------------------------------------------------

  /// Extracts a [GolfRound] from raw image bytes.
  ///
  /// Use this when you only have in-memory bytes (e.g. from a gallery
  /// picker that returns `Uint8List`). You **must** supply accurate
  /// [imageWidth] and [imageHeight] for ML Kit to process the frame.
  ///
  /// Throws [ScanException] if OCR fails completely.
  Future<GolfRound> parseScreenshotFromBytes(
    List<int> imageBytes, {
    required int imageWidth,
    required int imageHeight,
    InputImageRotation rotation = InputImageRotation.rotation0deg,
    InputImageFormat format = InputImageFormat.nv21,
  }) async {
    _ensureNotDisposed();

    final rawText = await _recogniseFromBytes(
      imageBytes,
      width: imageWidth,
      height: imageHeight,
      rotation: rotation,
      format: format,
    );
    if (rawText.trim().isEmpty) {
      throw const ScanException('No text detected in image');
    }
    return _withTbcSlots(BookingParser.parseBookingText(rawText), rawText);
  }

  // ---------------------------------------------------------------------------
  // Public API — raw text (debugging)
  // ---------------------------------------------------------------------------

  /// Returns the raw OCR text from [filePath] without parsing.
  ///
  /// Useful for debugging or showing the user what was detected.
  Future<String> extractRawTextFromFile(String filePath) async {
    _ensureNotDisposed();
    return _recogniseFromFile(filePath);
  }

  /// Releases the underlying ML Kit recogniser resources.
  ///
  /// Call this when the service is no longer needed (e.g. in a
  /// Provider's `dispose` callback).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _recognizer.close();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Runs OCR on a file and returns concatenated text.
  Future<String> _recogniseFromFile(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      return _processImage(inputImage);
    } catch (e, stack) {
      throw ScanException(
        'OCR text recognition failed',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Runs OCR on raw bytes and returns concatenated text.
  Future<String> _recogniseFromBytes(
    List<int> bytes, {
    required int width,
    required int height,
    required InputImageRotation rotation,
    required InputImageFormat format,
  }) async {
    try {
      final metadata = InputImageMetadata(
        size: Size(width.toDouble(), height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: width,
      );
      final inputImage = InputImage.fromBytes(
        bytes: Uint8List.fromList(bytes),
        metadata: metadata,
      );
      return _processImage(inputImage);
    } catch (e, stack) {
      throw ScanException(
        'OCR text recognition failed',
        cause: e,
        stackTrace: stack,
      );
    }
  }

  /// Maximum time to wait for on-device text recognition before giving up
  /// (spec: OCR must never hang the scan flow indefinitely).
  static const Duration _ocrTimeout = Duration(seconds: 8);

  /// Processes an [InputImage] through the recogniser and returns the
  /// concatenated text, preserving line breaks between text blocks.
  ///
  /// Throws [ScanException] if recognition doesn't complete within
  /// [_ocrTimeout] — callers should treat this the same as any other OCR
  /// failure (fall back to the upload screen with a clear error).
  Future<String> _processImage(InputImage inputImage) async {
    final RecognizedText recognised;
    try {
      recognised = await _recognizer.processImage(inputImage).timeout(_ocrTimeout);
    } on TimeoutException {
      throw const ScanException(
        "Couldn't auto-detect booking details — that took too long.",
      );
    }

    final buffer = StringBuffer();
    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        buffer.writeln(line.text);
      }
      // Extra newline between blocks to separate sections.
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Appends "Player TBC" placeholder slots (spec A8) when the raw OCR
  /// [rawText] indicates the booking has more players than were named.
  ///
  /// Kept separate from [BookingParser.parseBookingText] so that parser's
  /// unit tests (which assert exact named-player counts) stay unaffected.
  GolfRound _withTbcSlots(GolfRound round, String rawText) {
    final openSlots = BookingParser.extractOpenSlots(
      rawText,
      round.players.length,
    );
    if (openSlots <= 0) return round;

    final now = DateTime.now();
    final tbcPlayers = List.generate(
      openSlots,
      (i) => Player(
        id: 'tbc_${now.microsecondsSinceEpoch}_$i',
        name: 'Player TBC',
        rsvpStatus: RsvpStatus.tbc,
      ),
    );
    return round.copyWith(players: [...round.players, ...tbcPlayers]);
  }

  /// Throws a [StateError] if the service has already been disposed.
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ScanService has been disposed');
    }
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception thrown when OCR scanning fails.
///
/// Contains the original [cause] and [stackTrace] for debugging.
class ScanException implements Exception {
  /// Creates a [ScanException] with a human-readable [message].
  const ScanException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  /// A human-readable description of what went wrong.
  final String message;

  /// The original exception that caused this error, if any.
  final Object? cause;

  /// The stack trace from the original exception, if any.
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('ScanException: $message');
    if (cause != null) buffer.write(' (caused by: $cause)');
    return buffer.toString();
  }
}

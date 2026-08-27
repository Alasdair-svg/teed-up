/// Puts every incoming image through one pipeline before OCR sees it.
///
/// A booking screenshot shared straight into the app found only 3 of 4
/// players; the same screenshot picked from the gallery found all 4. The
/// two intake paths were feeding ML Kit different pixels:
///
///   gallery  -> image_picker with maxWidth/maxHeight 2048, imageQuality 90,
///               which downscales, applies EXIF orientation and re-encodes
///   share    -> the raw file, at whatever size and orientation it arrived
///
/// OCR accuracy is sensitive to both, so recognition depended on how the
/// user happened to hand over the image. This normalises the share path to
/// match, so the result is the same either way.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Matches image_picker's constraints in [ScanScreen._pickImage].
const int kMaxImageEdge = 2048;

/// Matches image_picker's `imageQuality: 90`.
const int kJpegQuality = 90;

/// Dimensions of the most recently decoded image, for on-screen diagnosis.
/// A truncated share-sheet read shows up here as an unexpected height.
String? lastDecodedSize;

/// Byte length of the most recently read source image.
int? lastSourceBytes;

/// Polls until [file]'s length stops changing, or [limit] elapses.
///
/// Cheap insurance: a few short sleeps cost nothing next to an OCR pass, and
/// reading a half-written screenshot silently loses data.
Future<void> _awaitStableFile(
  File file, {
  Duration limit = const Duration(seconds: 3),
}) async {
  const step = Duration(milliseconds: 120);
  var elapsed = Duration.zero;
  var last = -1;
  var stableFor = 0;
  while (elapsed < limit) {
    final size = await file.length();
    if (size > 0 && size == last) {
      stableFor++;
      // Two consecutive identical readings: treat as finished writing.
      if (stableFor >= 2) return;
    } else {
      stableFor = 0;
    }
    last = size;
    await Future<void>.delayed(step);
    elapsed += step;
  }
  debugPrint('[ImageNormaliser] file size never settled within $limit');
}

/// Normalises the image at [path] and returns a path to feed OCR.
///
/// Returns the ORIGINAL path unchanged if anything goes wrong: a failure to
/// normalise must never stop a scan, since the unmodified image is still
/// usually readable.
Future<String> normaliseForOcr(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return path;

    // Wait for the file to stop growing before reading it.
    //
    // Sharing a screenshot the instant it is taken can hand the app a file
    // the system is still writing. PNG decoders succeed on truncated data,
    // returning an image whose BOTTOM ROWS ARE MISSING — so the last entry
    // in a list silently disappears. That matches the report exactly: the
    // same player missing every time via the share sheet, all four found
    // when the identical screenshot was picked from the gallery moments
    // later, by which point the file was complete.
    await _awaitStableFile(file);

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return path;
    lastDecodedSize = '${decoded.width}x${decoded.height}';
    lastSourceBytes = bytes.length;

    // Apply EXIF orientation. A share-sheet image can carry a rotation flag
    // that the picker path resolves and the raw path does not, which alone
    // is enough to change what the recogniser reads.
    var out = img.bakeOrientation(decoded);

    if (out.width > kMaxImageEdge || out.height > kMaxImageEdge) {
      out = out.width >= out.height
          ? img.copyResize(out, width: kMaxImageEdge)
          : img.copyResize(out, height: kMaxImageEdge);
    }

    final target = File(
      '${file.parent.path}/atu_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await target.writeAsBytes(img.encodeJpg(out, quality: kJpegQuality));
    debugPrint(
      '[ImageNormaliser] ${decoded.width}x${decoded.height} -> '
      '${out.width}x${out.height} at ${target.path}',
    );
    return target.path;
  } catch (e, st) {
    debugPrint('[ImageNormaliser] failed, using original: $e\n$st');
    return path;
  }
}

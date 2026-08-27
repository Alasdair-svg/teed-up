// Both intake paths must hand OCR the same pixels.
//
// A screenshot shared into the app found 3 of 4 players; the same image
// picked from the gallery found all 4, because image_picker downscales,
// bakes EXIF orientation and re-encodes while the share path did none of it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:all_teed_up/services/image_normaliser.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('atu_norm'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, img.Image image) {
    final f = File('${dir.path}/$name')..writeAsBytesSync(img.encodePng(image));
    return f.path;
  }

  test('downscales an oversized image to the picker\'s limit', () async {
    final big = img.Image(width: 3000, height: 4000);
    final out = await normaliseForOcr(write('big.png', big));

    expect(out, isNot(equals('${dir.path}/big.png')));
    final result = img.decodeImage(File(out).readAsBytesSync())!;
    expect(result.height, kMaxImageEdge);
    expect(result.width, 1536); // 3000/4000 ratio preserved
  });

  test('leaves an already-small image at its own size', () async {
    final small = img.Image(width: 800, height: 600);
    final out = await normaliseForOcr(write('small.png', small));
    final result = img.decodeImage(File(out).readAsBytesSync())!;
    expect(result.width, 800);
    expect(result.height, 600);
  });

  test('a phone screenshot is scaled on its long edge', () async {
    // 1080x2400 is a common handset screenshot — taller than the limit.
    final shot = img.Image(width: 1080, height: 2400);
    final out = await normaliseForOcr(write('shot.png', shot));
    final result = img.decodeImage(File(out).readAsBytesSync())!;
    expect(result.height, kMaxImageEdge);
    expect(result.width, lessThan(1080));
  });

  test('returns the original path when the file is missing', () async {
    const missing = '/nonexistent/nope.png';
    expect(await normaliseForOcr(missing), missing);
  });

  test('returns the original path when the bytes are not an image', () async {
    final f = File('${dir.path}/junk.png')..writeAsStringSync('not an image');
    expect(await normaliseForOcr(f.path), f.path);
  });
}

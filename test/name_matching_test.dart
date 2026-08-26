// Regression tests built from names that actually failed on the user's
// device: "Sidi-Mohammed Saaf" and "Zachary Drury" both resolved to no email
// despite being in the address book.

import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/contacts_service.dart';

void main() {
  group('normalizeName', () {
    test('folds punctuation and case', () {
      expect(normalizeName('Sidi-Mohammed Saaf'), 'sidi mohammed saaf');
      expect(normalizeName("O'Brien, Sean"), 'o brien sean');
      expect(normalizeName('  Guy   Parsonage '), 'guy parsonage');
    });
    test('folds accents', () {
      expect(normalizeName('José Muñoz'), 'jose munoz');
    });
  });

  group('namesMatch — the reported failures', () {
    test('hyphenated compound vs spaced compound', () {
      expect(namesMatch('Sidi-Mohammed Saaf', 'Sidi Mohammed Saaf'), isTrue);
      expect(namesMatch('Sidi Mohammed Saaf', 'Sidi-Mohammed Saaf'), isTrue);
    });
    test('shortened forename', () {
      expect(namesMatch('Zachary Drury', 'Zach Drury'), isTrue);
      expect(namesMatch('Zach Drury', 'Zachary Drury'), isTrue);
    });
    test('exact match still works', () {
      expect(namesMatch('Guy Parsonage', 'Guy Parsonage'), isTrue);
    });
  });

  group('namesMatch — must NOT over-match', () {
    test('different surname is never a match', () {
      expect(namesMatch('Zachary Drury', 'Zachary Smith'), isFalse);
      expect(namesMatch('Guy Parsonage', 'Guy Ritchie'), isFalse);
    });
    test('same surname, unrelated forename', () {
      expect(namesMatch('Zachary Drury', 'Michael Drury'), isFalse);
    });
    test('empty input', () {
      expect(namesMatch('', 'Zach Drury'), isFalse);
      expect(namesMatch('Zach Drury', ''), isFalse);
    });
  });

  group('namesMatch — initial-only forenames', () {
    test('initial matches full forename', () {
      expect(namesMatch('Z Drury', 'Zachary Drury'), isTrue);
    });
    test('surname alone matches anyone with it', () {
      expect(namesMatch('Drury', 'Zachary Drury'), isTrue);
    });
  });
}

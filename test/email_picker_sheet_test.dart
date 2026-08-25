// Covers the recovery path for a player whose email couldn't be resolved.
//
// The bug this guards against was silent: a scanned player with no address
// rendered with no affordance and the invite went out without them. These
// tests assert the sheet can always produce an address — from contacts under
// a different spelling, or typed directly when the person isn't in contacts
// at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:all_teed_up/services/contacts_service.dart';
import 'package:all_teed_up/widgets/email_picker_sheet.dart';

class _FakeContactsService extends ContactsService {
  _FakeContactsService(this.results);
  final List<ContactSuggestion> results;
  List<String> queries = [];

  @override
  Future<List<ContactSuggestion>> searchByName(
    String query, {
    List<String> exclude = const [],
  }) async {
    queries.add(query);
    return results;
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FakeContactsService svc, {
    String name = 'Guy Parsonage',
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmailPickerSheet(playerName: name, service: svc),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('searches on the OCR name immediately', (tester) async {
    final svc = _FakeContactsService([
      const ContactSuggestion(
        name: 'Guy Parsonage',
        email: 'guy@example.com',
        allEmails: ['guy@example.com'],
      ),
    ]);
    await pump(tester, svc);
    expect(svc.queries.first, 'Guy Parsonage');
    expect(find.text('guy@example.com'), findsOneWidget);
  });

  testWidgets('a contact with two addresses offers both separately',
      (tester) async {
    final svc = _FakeContactsService([
      const ContactSuggestion(
        name: 'Guy Parsonage',
        email: 'guy@work.com',
        allEmails: ['guy@work.com', 'guy@personal.com'],
      ),
    ]);
    await pump(tester, svc);
    expect(find.text('guy@work.com'), findsOneWidget);
    expect(find.text('guy@personal.com'), findsOneWidget);
  });

  testWidgets('contacts with no address are not offered', (tester) async {
    final svc = _FakeContactsService([
      const ContactSuggestion(name: 'Guy Parsonage'),
    ]);
    await pump(tester, svc);
    expect(find.text('Guy Parsonage'), findsOneWidget); // the title only
    expect(find.textContaining('No contacts matched'), findsOneWidget);
  });

  testWidgets('a typed address can be used when contacts have nothing',
      (tester) async {
    final svc = _FakeContactsService(const []);
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showEmailPickerSheet(
                context,
                playerName: 'Guy Parsonage',
                service: svc,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'guy@parsonage.com');
    await tester.pumpAndSettle();
    expect(find.text('Use this address'), findsOneWidget);

    await tester.tap(find.text('Use this address'));
    await tester.pumpAndSettle();
    expect(picked, 'guy@parsonage.com');
  });

  testWidgets('an incomplete address is not offered as usable', (tester) async {
    final svc = _FakeContactsService(const []);
    await pump(tester, svc);
    await tester.enterText(find.byType(TextField), 'guy@');
    await tester.pumpAndSettle();
    expect(find.text('Use this address'), findsNothing);
  });

  testWidgets('picking a contact returns that exact address', (tester) async {
    final svc = _FakeContactsService([
      const ContactSuggestion(
        name: 'Guy Parsonage',
        email: 'guy@work.com',
        allEmails: ['guy@work.com', 'guy@personal.com'],
      ),
    ]);
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              picked = await showEmailPickerSheet(
                context,
                playerName: 'Guy Parsonage',
                service: svc,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('guy@personal.com'));
    await tester.pumpAndSettle();
    expect(picked, 'guy@personal.com');
  });
}

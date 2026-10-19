import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/services/StudentApi.dart';
import 'package:folk_app/utils/StudentNameGuard.dart';

// A student's name is the key of five collections, so it never carries a leading or trailing
// space: "Dhiraj Kumar " and "Dhiraj Kumar" would be two different folders.

void main() {
  tearDown(() => StudentApi.useForTests(null));

  group('normalizeStudentName', () {
    test('"  Ram Das  " is saved as "Ram Das"', () {
      expect(normalizeStudentName('  Ram Das  '), 'Ram Das');
    });
    test('a trailing or a leading space alone is removed', () {
      expect(normalizeStudentName('Ram Das '), 'Ram Das');
      expect(normalizeStudentName(' Ram Das'), 'Ram Das');
    });
    test('tabs and new lines at the ends are removed too', () {
      expect(normalizeStudentName('\tRam Das\n'), 'Ram Das');
    });
    test('an already clean name, and its capitalisation, are untouched', () {
      expect(normalizeStudentName('Ram Das'), 'Ram Das');
      expect(normalizeStudentName('ram DAS'), 'ram DAS');
    });
    test('only spaces becomes empty (so the form says the name is required)', () {
      expect(normalizeStudentName('    '), '');
    });
  });

  group('the name-taken check sends the trimmed name', () {
    Future<List<Map<String, dynamic>>> run(String typed, {required bool available}) async {
      final sent = <Map<String, dynamic>>[];
      StudentApi.useForTests((name, data) async {
        expect(name, 'checkNameAvailable');
        sent.add(Map<String, dynamic>.from(data as Map));
        return {'available': available};
      });
      final taken = await isStudentNameTaken(typed);
      expect(taken, !available);
      return sent;
    }

    test('"Ram Das " is checked as "Ram Das" (so it collides with the existing "Ram Das")', () async {
      final sent = await run('Ram Das ', available: false);
      expect(sent.single['name'], 'Ram Das');
    });
    test('"  Ram Das  " is checked as "Ram Das"', () async {
      final sent = await run('  Ram Das  ', available: true);
      expect(sent.single['name'], 'Ram Das');
    });
    test('nothing typed is not sent at all', () async {
      final sent = await run('   ', available: true).catchError((_) => <Map<String, dynamic>>[]);
      expect(sent, isEmpty);
    });
  });

  group('source guarantee: registration never saves the raw field text', () {
    final source = File('lib/pages/CompleteProfile.dart').readAsStringSync();
    test('the saved users.name is the normalised value', () {
      expect(source.contains("'name': normalizeStudentName(nameController.text)"), isTrue);
      expect(RegExp(r"'name':\s*nameController\.text").hasMatch(source), isFalse,
          reason: 'saving nameController.text directly would keep spaces');
    });
    test('the name is normalised before the name-taken check', () {
      final normalise = source.indexOf('normalizeStudentName(nameController.text)');
      final taken = source.indexOf('isStudentNameTaken(normalizedName)');
      expect(normalise, greaterThan(-1));
      expect(taken, greaterThan(normalise));
    });
    test('the field shows the trimmed name when the student leaves it', () {
      expect(source.contains('onEditingComplete: _trimNameField'), isTrue);
      expect(source.contains('onTapOutside: (_) => _trimNameField()'), isTrue);
    });
  });
}

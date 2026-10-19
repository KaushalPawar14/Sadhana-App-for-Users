import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/utils/CallableMessage.dart';

// Release guards: source-level rules that must hold for the whole app.
List<File> dartFiles(String dir) => [
      for (final f in Directory(dir).listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
    ];

void main() {
  test('no LayoutBuilder anywhere in lib/ (it caused three crashes; the width comes from the screen instead)', () {
    final hits = <String>[];
    for (final f in dartFiles('lib')) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (RegExp(r'\bLayoutBuilder\s*[(<]').hasMatch(code)) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });

  test('user-facing text (Text, snackbars, error screens) never interpolates a raw exception', () {
    final hits = <String>[];
    final pattern = RegExp(r'(showSnackbar|SnackBar|Text|FolkErrorRetry)\s*\([^;]*(\$e\b|\$\{e\}|\$error\b|\be\.toString\(\)|\berror\.toString\(\))');
    for (final f in dartFiles('lib')) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (code.contains('print(')) continue;
        if (pattern.hasMatch(code)) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty, reason: 'raw error text must not reach the user');
  });

  group('callableMessage: the server\'s sentences pass, bare codes never do', () {
    FirebaseFunctionsException ex(String code, String? message) => FirebaseFunctionsException(code: code, message: message ?? '');

    test('a sentence written for people is shown', () {
      expect(callableMessage(ex('failed-precondition', 'This request is no longer pending.'), 'fallback'), 'This request is no longer pending.');
      expect(callableMessage(ex('resource-exhausted', "You've reached today's limit."), 'fallback'), "You've reached today's limit.");
    });

    test('a bare status code, a technical code, an empty message or an exception name give the fallback', () {
      expect(callableMessage(ex('internal', 'INTERNAL'), 'fallback'), 'fallback');
      expect(callableMessage(ex('unavailable', 'The service is currently unavailable.'), 'fallback'), 'fallback');
      expect(callableMessage(ex('failed-precondition', 'FAILED_PRECONDITION'), 'fallback'), 'fallback');
      expect(callableMessage(ex('not-found', null), 'fallback'), 'fallback');
      expect(callableMessage(ex('not-found', '   '), 'fallback'), 'fallback');
      expect(callableMessage(ex('unknown', 'StateError: bad'), 'fallback'), 'fallback');
      expect(callableMessage(ex('invalid-argument', '[cloud_functions/invalid-argument] x'), 'fallback'), 'fallback');
    });
  });
}

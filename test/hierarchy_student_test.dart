import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/pages/NonPlayInstallScreen.dart';
import 'package:folk_app/services/StudentApi.dart';
import 'package:folk_app/utils/InstallSource.dart';
import 'package:folk_app/utils/ManualEntryMatch.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/utils/StudentNameGuard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  Map<String, dynamic> answer = {};

  setUp(() {
    calls.clear();
    StudentApi.useForTests((name, data) async {
      calls.add('$name ${data.toString()}');
      return answer;
    });
    GenderDirectory.reset();
  });
  tearDown(() => StudentApi.useForTests(null));

  group('StudentApi', () {
    test('checkNameAvailable', () async {
      answer = {'available': false};
      expect(await StudentApi.instance.checkNameAvailable('Asha'), isFalse);
      answer = {'available': true};
      expect(await StudentApi.instance.checkNameAvailable('Asha'), isTrue);
      answer = {'available': 'maybe'};
      expect(() => StudentApi.instance.checkNameAvailable('Asha'), throwsStateError);
    });

    test('isStudentNameTaken uses the callable and fails loudly', () async {
      answer = {'available': false};
      expect(await isStudentNameTaken('  Asha   Devi '), isTrue);
      expect(calls.single, contains('checkNameAvailable'));
      expect(calls.single, contains('Asha Devi'), reason: 'normalised before sending');
      answer = {'available': true};
      expect(await isStudentNameTaken('Asha'), isFalse);
      expect(await isStudentNameTaken('   '), isFalse, reason: 'blank never asks the server');
      StudentApi.useForTests((n, d) async => throw Exception('offline'));
      expect(() => isStudentNameTaken('Asha'), throwsException);
    });

    test('findMatchingManualEntries keeps its shape (count, role only when unique)', () async {
      answer = {'count': 1, 'role': 'Stay at Hostel'};
      var m = await findMatchingManualEntries('9111111111');
      expect(m.length, 1);
      expect(m.first['role'], 'Stay at Hostel');
      answer = {'count': 2, 'role': ''};
      m = await findMatchingManualEntries('9222222222');
      expect(m.length, 2);
      expect(m.first['role'], '');
      answer = {'count': 0, 'role': ''};
      expect(await findMatchingManualEntries('9333333333'), isEmpty);
      expect(await findMatchingManualEntries(''), isEmpty);
    });

    test('getMyGuide / getGenderDirectory / searchStudents / acceptFriendRequest', () async {
      answer = {'displayName': 'Amit Prabhu', 'role': 'GUIDE'};
      final g = await StudentApi.instance.getMyGuide();
      expect(g.displayName, 'Amit Prabhu');
      expect(g.role, 'GUIDE');
      answer = {'mine': 'female', 'femaleNames': ['Asha'], 'femaleUids': ['u1']};
      final d = await StudentApi.instance.getGenderDirectory();
      expect(d.mine, 'female');
      expect(d.femaleNames, {'Asha'});
      answer = {
        'results': [
          {'uid': 'u2', 'name': 'Bina'}
        ]
      };
      expect((await StudentApi.instance.searchStudents('bi')).single['uid'], 'u2');
      answer = {'accepted': true};
      await StudentApi.instance.acceptFriendRequest('r1');
      expect(calls.last, contains('acceptFriendRequest'));
    });

    test('GenderDirectory is built from the callable, not from reading users', () async {
      answer = {'mine': 'male', 'femaleNames': ['Asha'], 'femaleUids': ['u1']};
      final dir = await GenderDirectory.forCurrentUserForTestsViaApi();
      expect(dir.iAmFemale, isFalse);
      expect(dir.sameByName('Asha'), isFalse);
      expect(dir.sameByName('Arjun'), isTrue);
      expect(dir.sameByUid('u1'), isFalse);
    });
  });

  group('install source', () {
    test('only the Play Store installer counts', () {
      expect(isPlayStoreInstaller('com.android.vending'), isTrue);
      expect(isPlayStoreInstaller(null), isFalse);
      expect(isPlayStoreInstaller('com.google.android.packageinstaller'), isFalse);
      expect(isPlayStoreInstaller('com.sec.android.app.samsungapps'), isFalse);
    });

    Future<bool> blocked(Object? installer, {bool release = true}) async {
      const channel = MethodChannel('folk/install_source');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => installer);
      return installedOutsidePlayStore(channel: channel, releaseMode: release);
    }

    test('a release build from a file or another store is blocked; Play and debug are not', () async {
      expect(await blocked(null), isTrue, reason: 'adb / file install');
      expect(await blocked('com.google.android.packageinstaller'), isTrue);
      expect(await blocked('com.android.vending'), isFalse);
      expect(await blocked(null, release: false), isFalse, reason: 'debug builds are never blocked');
    });

    test('an unreadable installer (no channel) does not lock anyone out', () async {
      const channel = MethodChannel('folk/none');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await installedOutsidePlayStore(channel: channel, releaseMode: true), isFalse);
    });

    testWidgets('the blocking screen says what to do and offers the Play Store', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NonPlayInstallScreen()));
      expect(
          find.text('This copy was installed outside the Play Store. Please uninstall it and install FOLK Students from the Play Store.'),
          findsOneWidget);
      expect(find.text('Open the Play Store'), findsOneWidget);
      expect(NonPlayInstallScreen.packageId, 'org.folksurat.students');
    });
  });

  group('source guarantees for the strict rules', () {
    String read(String p) => File(p).readAsStringSync();
    final libFiles = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
    ];

    test('no student code reads every users document or queries other users', () {
      for (final f in libFiles) {
        final src = f.readAsStringSync();
        expect(RegExp(r"collection\('users'\)\s*\.get\(\)").hasMatch(src), isFalse,
            reason: '${f.path}: whole users read');
        expect(src.contains(".where('mobileNumber'"), isFalse, reason: '${f.path}: mobile query');
        expect(src.contains("collection('adminUsers')"), isFalse, reason: '${f.path}: adminUsers read');
      }
    });

    test('no client-side competition finalisation is left', () {
      for (final f in libFiles) {
        final src = f.readAsStringSync();
        expect(src.contains('checkAndRunWeeklyLazyTrigger'), isFalse, reason: f.path);
        expect(src.contains('checkAndRunMonthlyLazyTrigger'), isFalse, reason: f.path);
        expect(src.contains("'weekly-winner'"), isFalse, reason: f.path);
      }
    });

    test('name-keyed competition / scorecard / contribution reads are gender-filtered', () {
      expect(read('lib/scores/WeeklyResults.dart'), contains("where('gender', isEqualTo: directory.mine)"));
      expect(read('lib/scores/MonthlyResults.dart'), contains("where('gender', isEqualTo: directory.mine)"));
      expect(read('lib/utils/SameGender.dart'), contains(".where('gender', isEqualTo: directory.mine)"));
      expect(read('lib/pages/ChantingCompetition.dart'), contains("where('gender', isEqualTo:"));
    });

    test('registration creates the user document unassigned, and the play_store push opens the store', () {
      expect(read('lib/services/PostAuthRouter.dart'), contains("'guideId': ''"));
      expect(read('lib/utils/NotificationRouter.dart'), contains("case 'play_store':"));
    });
  });
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Calendar.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/InsightsData.dart';
import 'package:folk_app/utils/SadhanaReportSource.dart';
import 'package:folk_app/utils/SadhanaStats.dart';
import 'package:folk_app/widgets/InsightsGraphCarousel.dart';
import 'package:folk_app/widgets/SadhanaStatTile.dart';
import 'package:table_calendar/table_calendar.dart';

import 'save_path_test.dart' show FakeSnapshot;
import 'text_scale_test.dart' show loadAppFonts;

// Reports are CATEGORY-SEPARATED: a student's data is read only from the collection of his CURRENT category
// (FOLK -> sadhana-reports; Hostel / Localite -> hostel-sadhana), live, with no restart. Nothing is deleted:
// switching back shows the earlier category's saved reports again.
void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget host(Widget home) => MaterialApp(
      theme: FolkTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: home,
    );

final now = DateTime.now();
final today = DateTime(now.year, now.month, now.day);
DateTime day(int back) => today.subtract(Duration(days: back));
String key(DateTime d) => sadhanaDateKey(d);

/// A live "dates" stream over two fake collections, switched by ReportCategory like the app's own.
class TwoCollections {
  final folk = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  final hostel = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  Stream<Set<String>> stream() =>
      availableDatesStream('Asha', snapshotsFor: (c) => (c == kFolkReports ? folk : hostel).stream);

  void emit(String collection, Iterable<String> ids) => (collection == kFolkReports ? folk : hostel).add(FakeSnapshot(ids.toList()));

  Future<void> close() async {
    await folk.close();
    await hostel.close();
  }
}

String submittedTile(WidgetTester tester) {
  // "N" over "of M" on the days-submitted tile
  final tile = find.ancestor(of: find.text('days submitted'), matching: find.byType(SadhanaStatTile)).first;
  final texts = tester.widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text))).map((t) => t.data).whereType<String>().toList();
  return texts.firstWhere((t) => RegExp(r'^\d+$').hasMatch(t));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  tearDown(() => ReportCategory.instance.debugReset());

  test('which collection a role means', () {
    expect(reportCollectionForRole('Stay at FOLK'), kFolkReports);
    expect(reportCollectionForRole('Stay at Hostel'), kHostelReports);
    expect(reportCollectionForRole('Stay at Localite'), kHostelReports);
    expect(reportCollectionForRole(''), kFolkReports);
    expect(reportCollectionForRole(null), kFolkReports);
  });

  testWidgets('Calendar: FOLK -> Hostel makes every day red and the tiles zero; new reports count; back to FOLK the old days return (live)', (tester) async {
    phone(tester);
    ReportCategory.instance.debugSetRole('Stay at FOLK');
    final src = TwoCollections();
    addTearDown(src.close);
    await tester.pumpWidget(host(CalendarPage(username: 'Asha', role: 'Stay at FOLK', datesStream: src.stream())));
    src.emit(kFolkReports, [key(day(1)), key(day(2)), key(day(3))]);
    await tester.pumpAndSettle();
    expect(submittedTile(tester), '3', reason: 'three FOLK days');

    // a guide moves him to Hostel: no restart
    ReportCategory.instance.debugSetRole('Stay at Hostel');
    await tester.pump();
    src.emit(kHostelReports, <String>[]);
    await tester.pumpAndSettle();
    expect(submittedTile(tester), '0', reason: 'the FOLK days are not his Hostel reports: all red, zero');

    // he files a Hostel report: it counts
    src.emit(kHostelReports, [key(day(1))]);
    await tester.pumpAndSettle();
    expect(submittedTile(tester), '1');

    // and back to FOLK: his saved FOLK reports return
    ReportCategory.instance.debugSetRole('Stay at FOLK');
    await tester.pump();
    src.emit(kFolkReports, [key(day(1)), key(day(2)), key(day(3))]);
    await tester.pumpAndSettle();
    expect(submittedTile(tester), '3');
  });

  testWidgets('Calendar: tapping a red day opens the form of the CURRENT category, even if the page was built with the old role', (tester) async {
    phone(tester);
    ReportCategory.instance.debugSetRole('Stay at FOLK');
    final src = TwoCollections();
    addTearDown(src.close);
    await tester.pumpWidget(host(CalendarPage(username: 'Asha', role: 'Stay at FOLK', datesStream: src.stream())));
    src.emit(kFolkReports, [key(day(2))]);
    await tester.pumpAndSettle();
    // the missed day: 4 days back (on the current month's page unless it is the first days of a month)
    final missed = day(4);
    if (missed.month != today.month) {
      await tester.tap(find.byIcon(Icons.chevron_left).first);
      await tester.pumpAndSettle();
    }
    ReportCategory.instance.debugSetRole('Stay at Localite');
    await tester.pump();
    src.emit(kHostelReports, <String>[]);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(TableCalendar<dynamic>), matching: find.text('${missed.day}')).first);
    await tester.pumpAndSettle();
    expect(find.byType(SadhanaPage), findsOneWidget, reason: 'the Hostel / Localite form');
    expect(find.byType(QuestionsPage), findsNothing);
  });

  testWidgets('Insights: the graphs follow the category live; the other category\'s reports stop counting and come back', (tester) async {
    phone(tester);
    ReportCategory.instance.debugSetRole('Stay at FOLK');
    final reads = <String>[];
    Future<Reports> load(String name) async {
      reads.add(ReportCategory.instance.collection);
      return ReportCategory.instance.collection == kFolkReports
          ? {for (var i = 1; i <= 3; i++) key(day(i)): {'chantRounds': 16, 'bookReading': 30, 'classHearing': 2, 'dailyServices': 2, 'templeEntry': '05:30', 'finishTiming': '21:00'}}
          : <String, Map<String, dynamic>>{};
    }

    await tester.pumpWidget(host(CompetitionPage(role: 'Stay at FOLK', username: 'Asha', loadReports: load)));
    await tester.pumpAndSettle();
    expect(reads, [kFolkReports]);
    final folkGraphs = applicableGraphs({for (var i = 1; i <= 3; i++) key(day(i)): <String, dynamic>{}}, 'Stay at FOLK');
    expect(folkGraphs.length, 8);

    // FOLK -> Hostel, live: a new read from the Hostel side only, with no FOLK data in it
    ReportCategory.instance.debugSetRole('Stay at Hostel');
    await tester.pumpAndSettle();
    expect(reads, [kFolkReports, kHostelReports], reason: 'it read again, from the current category');
    expect(applicableGraphs(<String, Map<String, dynamic>>{}, ReportCategory.instance.role!).map((g) => g.id), ['chanting', 'reading', 'hearing', 'finish', 'hearingPie'],
        reason: 'no Services, Services split or Temple entry');
    expect(find.byType(InsightsGraphCarousel), findsOneWidget);

    // Hostel -> FOLK: the FOLK reports are back
    ReportCategory.instance.debugSetRole('Stay at FOLK');
    await tester.pumpAndSettle();
    expect(reads, [kFolkReports, kHostelReports, kFolkReports]);
  });

  test('the graph set is decided by the category alone', () {
    final mixed = {key(day(1)): <String, dynamic>{'wakeUpTime': '05:00'}, key(day(2)): <String, dynamic>{'templeEntry': '05:00', 'dailyServices': 2}};
    expect(applicableGraphs(mixed, 'Stay at FOLK').length, 8);
    expect(applicableGraphs(mixed, 'Stay at Hostel').length, 5);
    expect(applicableGraphs(mixed, 'Stay at Localite').length, 5);
  });

  test('changing between Hostel and Localite is not a category change (no reload)', () {
    var calls = 0;
    ReportCategory.instance.debugSetRole('Stay at Hostel');
    void l() => calls++;
    ReportCategory.instance.addListener(l);
    ReportCategory.instance.debugSetRole('Stay at Localite');
    expect(calls, 0);
    ReportCategory.instance.debugSetRole('Stay at FOLK');
    expect(calls, 1);
    ReportCategory.instance.removeListener(l);
  });
}

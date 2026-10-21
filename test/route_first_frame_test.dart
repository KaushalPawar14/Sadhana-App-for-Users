import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

// ignore_for_file: depend_on_referenced_packages
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/AssistantHistoryScreen.dart';
import 'package:folk_app/pages/BookReaderPage.dart';
import 'package:folk_app/pages/BooksHistoryPage.dart';
import 'package:folk_app/pages/BooksNotesPage.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/theme/FolkColors.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/BookHighlights.dart';
import 'package:folk_app/utils/BookLoader.dart';
import 'package:folk_app/utils/BookNotes.dart';
import 'package:folk_app/utils/Commitments.dart';
import 'package:folk_app/utils/ResultsDots.dart';
import 'package:folk_app/utils/SameGender.dart';

import 'text_scale_test.dart' show loadAppFonts;

// The first frames of a screen opened by navigation (the History clock of the AI assistant first, then
// every other pushed screen): the colour behind the page is the theme's own page colour at every moment
// of the transition - never the white scrim Flutter paints from `ColorScheme.surface`, which is white
// in dark mode here (see FolkTheme). Real pixels, light and dark.
void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Map<String, Map<String, dynamic>> docs() => {
      'Asha': {'weekly.total_score': 10, 'weekly.pts_chanting': 10},
    };

class _Page {
  const _Page(this.name, this.build, {this.ownBackground});
  final String name;
  final Widget Function() build;

  /// A page with its own colour (the reader's reading mode): checked for "not white" only.
  final bool? ownBackground;
}

NoteBook book() => const NoteBook(bookId: 'level-1__b', title: 'A Book', entries: [
      NoteEntry(id: 'n1', level: 'level-1', bookKey: 'b', bookTitle: 'A Book', category: HighlightCategory.good, text: 'Passage', note: '', chapter: 0, paragraph: 1, offset: 0, truncated: false),
    ]);

final pages = <_Page>[
  _Page('AI assistant History (the clock icon)', () => AssistantHistoryListPage(uid: 'u1', firestore: FakeFirebaseFirestore())),
  _Page('Books History', () => BooksHistoryPage(uid: 'u1', firestore: FakeFirebaseFirestore())),
  _Page('Books Notes', () => BooksNotesPage(uid: 'u1', firestore: FakeFirebaseFirestore())),
  _Page('Notes cards', () => NotesCardsPage(category: HighlightCategory.good, book: book())),
  _Page('Leaderboard', () => LeaderboardPage(username: 'Asha', docsStream: Stream.value(docs()), changesLoader: (_) async => {}, resultsDots: ResultsDots(FakeFirebaseFirestore(), 'u1'))),
  _Page('Leaderboard (Scores tab)', () => LeaderboardPage(username: 'Asha', docsStream: Stream.value(docs()), changesLoader: (_) async => {}, initialTab: LeaderboardTab.scores, resultsDots: ResultsDots(FakeFirebaseFirestore(), 'u1'))),
  _Page('Submit Sadhana (FOLK form)', () => QuestionsPage(loadCommitments: () async => const Commitments(readingMinutes: 0))),
  _Page('Submit Sadhana (Hostel & Localite form)', () => SadhanaPage(loadCommitments: () async => const Commitments(readingMinutes: 0))),
  _Page(
    'Book reader (opening)',
    () => BookReaderPage(
      dropboxUrl: 'https://example.invalid/book.docx?dl=0',
      bookTitle: 'Test Book',
      bookKey: 'book_1',
      level: 'level-1',
      uid: 'u1',
      loader: (u, t) => StreamController<BookLoadUpdate>().stream,
      extras: () async => <Object?>[null, <String, Object?>{}, false],
    ),
    ownBackground: true,
  ),
];

Future<ByteData> pixels(WidgetTester tester, GlobalKey key) async {
  late ByteData data;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return data;
}

int pixelAt(ByteData d, int x, int y, {int width = 360}) {
  final i = (y * width + x) * 4;
  return (0xFF << 24) | (d.getUint8(i) << 16) | (d.getUint8(i + 1) << 8) | d.getUint8(i + 2);
}

/// The empty left margin at several heights.
List<int> strips(ByteData f) => [for (final y in [220, 320, 420, 520, 620, 720]) pixelAt(f, 3, y)];

double whiteShare(ByteData d) {
  var white = 0;
  final n = d.lengthInBytes ~/ 4;
  for (var i = 0; i < n; i++) {
    // near-white: the SDK's scrim is ColorScheme.surface, 0xFFFEF7FF
    if (d.getUint8(i * 4) >= 235 && d.getUint8(i * 4 + 1) >= 235 && d.getUint8(i * 4 + 2) >= 235) white++;
  }
  return white / n;
}

bool near(int a, int b, [int tol = 3]) =>
    ((a >> 16 & 255) - (b >> 16 & 255)).abs() <= tol && ((a >> 8 & 255) - (b >> 8 & 255)).abs() <= tol && ((a & 255) - (b & 255)).abs() <= tol;

/// Opens [page] over a home page in [theme] and looks at the screen at several moments of the transition.
Future<List<ByteData>> openAndSample(WidgetTester tester, ThemeData theme, Widget Function() page, {required Color homeColor}) async {
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: homeColor,
          body: Center(child: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page())), child: const Text('open'))),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  final frames = <ByteData>[];
  var elapsed = 0;
  for (final at in [0, 40, 120, 250, 450, 700, 1000]) {
    await tester.pump(Duration(milliseconds: at - elapsed));
    elapsed = at;
    frames.add(await pixels(tester, key));
  }
  return frames;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });
  setUp(() => GenderDirectory.useForTests(() async => const GenderDirectory(mine: 'male', femaleNames: {}, femaleUids: {})));

  test('the transition scrim of both themes is the page colour (Android and desktop builders)', () {
    for (final (theme, colors) in [(FolkTheme.light, FolkColors.light), (FolkTheme.dark, FolkColors.dark)]) {
      final android = theme.pageTransitionsTheme.builders[TargetPlatform.android]! as PredictiveBackPageTransitionsBuilder;
      expect(android.fallbackColor, colors.pageBackground);
      for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
        expect((theme.pageTransitionsTheme.builders[p]! as ZoomPageTransitionsBuilder).backgroundColor, colors.pageBackground);
      }
    }
  });

  testWidgets('control: WITHOUT the fix, a dark app shows white while a page opens (the reported bug)', (tester) async {
    phone(tester);
    final old = ThemeData(fontFamily: 'Satoshi', extensions: const <ThemeExtension<dynamic>>[FolkColors.dark]);
    final frames = await openAndSample(tester, old, () => const Scaffold(backgroundColor: Color(0xFF111111)), homeColor: FolkColors.dark.pageBackground);
    final want = FolkColors.dark.pageBackground.toARGB32();
    final off = [for (final f in frames) strips(f).any((p) => !near(p, want, 14))];
    // ignore: avoid_print
    print('control (old theme): the margin is off the page colour in frames $off; strip at 120 ms ${strips(frames[2]).map((p) => p.toRadixString(16)).toList()}');
    expect(off.any((x) => x), isTrue, reason: 'the old theme paints a different colour behind the page at some moment: $off');
  });

  for (final dark in [false, true]) {
    final theme = dark ? FolkTheme.dark : FolkTheme.light;
    final colors = dark ? FolkColors.dark : FolkColors.light;
    for (final page in pages) {
      testWidgets('${dark ? 'dark' : 'light'}: ${page.name} - no white frame while it opens', (tester) async {
        phone(tester);
        final frames = await openAndSample(tester, theme, page.build, homeColor: colors.pageBackground);
        for (var i = 0; i < frames.length; i++) {
          final f = frames[i];
          // the empty margin at the left edge, at several heights: the page colour at every moment
          // (a reading-mode page has its own colour: it must simply not be white in dark mode)
          for (final p in strips(f)) {
            if (page.ownBackground == true) {
              if (dark) expect(near(p, 0xFFFEF7FF, 6), isFalse, reason: 'frame $i: the SDK white scrim shows (${p.toRadixString(16)})');
            } else {
              expect(near(p, colors.pageBackground.toARGB32(), 14), isTrue, reason: 'frame $i: the margin is ${p.toRadixString(16)}, expected the page colour ${colors.pageBackground.toARGB32().toRadixString(16)}');
            }
          }
        }
        // let any timers of the page run out
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}

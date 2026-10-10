import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:table_calendar/table_calendar.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/MinHeightBox.dart' show ghostHeight;
import '../widgets/FloatingPillNavBar.dart';
import '../widgets/PrimaryButton.dart';
import '../widgets/SadhanaDayCell.dart';
import '../widgets/SadhanaDayDialog.dart';
import '../utils/SadhanaReportSource.dart';
import '../utils/SadhanaStats.dart';
import '../widgets/SadhanaStatTile.dart';

class CalendarPage extends StatefulWidget {
  final String username, role;

  // Tests hand in their own dates stream and day read; the app never sets them.
  @visibleForTesting
  final Stream<Set<String>>? datesStream;
  @visibleForTesting
  final Future<Map<String, dynamic>?> Function(String name, String dateId)?
      dayReader;

  CalendarPage(
      {required this.username,
      required this.role,
      this.datesStream,
      this.dayReader});

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime now = DateTime.now();
  late final Map<DateTime, Color> _selectedDayColors;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;
  late Set<String> _availableDates;
  bool showWeekDot = false;
  late AnimationController _dotController; // for in/out animation
  late Stream<Set<String>> _datesStream;

  @override
  void initState() {
    super.initState();

    _selectedDayColors = {};
    _availableDates = {};

    // Master Task 2026-09-11 — merged across both residence collections so
    // history filed before a residence switch still shows here. See
    // utils/SadhanaReportSource.dart's own header for the one-per-date rule.
    _datesStream =
        widget.datesStream ?? mergedAvailableDatesStream(widget.username);
  }

  // A submitted day's details, in a dialog: the SAME read as before, the merged
  // report for that date across both residence collections.
  Future<void> _openDay(DateTime day) async {
    final dateId = _getFormattedDate(day);
    await SadhanaDayDialog.show(
      context,
      date: day,
      load: () =>
          (widget.dayReader ?? fetchMergedDateReport)(widget.username, dateId),
    );
    // Closed: let go of the day, so the Submit button is back.
    if (mounted && isSameDay(_selectedDay, day)) {
      setState(() => _selectedDay = null);
    }
  }

  String _getFormattedDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  Color _getDayColor(DateTime day) {
    String formattedDate = _getFormattedDate(day);
    if (day.isAfter(DateTime.now())) return Colors.transparent;
    if (_availableDates.contains(formattedDate)) return Colors.green;
    return Colors.red;
  }

  /// Which of the five looks a day gets. The submitted / missed / future
  /// decision is still made by [_getDayColor] — the existing "after now" test
  /// and date-set membership, untouched — and only translated here from its
  /// old colour into a state. Today is told apart first, by the same
  /// `isSameDay(DateTime.now(), day)` test the old day tile used, and is
  /// "submitted" by the same `_availableDates.contains(...)` membership test.
  SadhanaDayState _dayState(DateTime day) {
    if (isSameDay(DateTime.now(), day)) {
      return _availableDates.contains(_getFormattedDate(day))
          ? SadhanaDayState.todaySubmitted
          : SadhanaDayState.today;
    }
    final statusColor = _getDayColor(day);
    if (statusColor == Colors.transparent) return SadhanaDayState.future;
    if (statusColor == Colors.green) return SadhanaDayState.submitted;
    return SadhanaDayState.missed;
  }

  /// The two tiles above the calendar, worked out from the same set of
  /// submitted dates the calendar colours its days from: "N of M — days
  /// submitted" for the month on show, and the current streak. Nothing is read
  /// or stored for them.
  Widget _statTiles() {
    final today = DateTime.now();
    final tally =
        monthTally(dates: _availableDates, month: _focusedDay, today: today);
    final streak = currentStreak(dates: _availableDates, today: today);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SadhanaStatTile(
              style: FolkGradientStyle.saffron,
              value: tally.submitted,
              suffix: 'of ${tally.counted}',
              caption: tally.isEmpty ? 'a fresh month begins' : 'days submitted',
              friendly: tally.isEmpty ? 'Fresh start' : null,
              semanticLabel: tally.isEmpty
                  ? 'Nothing to count yet this month'
                  : '${tally.submitted} of ${tally.counted} days submitted',
            ),
          ),
          const SizedBox(width: FolkSpace.cardGap),
          Expanded(
            child: SadhanaStatTile(
              style: FolkGradientStyle.green,
              value: streak,
              suffix: streak == 1 ? 'day' : 'days',
              caption: 'current streak',
              semanticLabel: 'Current streak: $streak '
                  '${streak == 1 ? 'day' : 'days'}',
            ),
          ),
        ],
      ),
    );
  }

  /// A 44 dp frosted round button for the month arrows.
  Widget _chevron(IconData icon) {
    final colors = context.folk;
    return Container(
      width: FolkShape.iconButtonSize,
      height: FolkShape.iconButtonSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceSecondary,
      ),
      child: Icon(icon, size: 22, color: colors.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    const chevronPadding = EdgeInsets.all(2); // 44 dp button in a 48 dp target

    return Scaffold(
      // The tab host paints the page background (with the top fade).
      backgroundColor: Colors.transparent,
      body: StreamBuilder<Set<String>>(
          stream: _datesStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _swap('ghost', _ghostBody());
            }

            if (snapshot.hasError) {
              return _swap(
                  'error',
                  Center(
                      child:
                          Text("Error: ${snapshot.error}", style: text.body)));
            }

            // 🔥 UPDATE AVAILABLE DATES FROM STREAM
            if (snapshot.hasData) {
              _availableDates = snapshot.data!;
            }

            return _swap('real', SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              // Bottom leaves room for the floating pill navigation.
              padding: EdgeInsets.fromLTRB(
                  FolkSpace.pagePadding,
                  FolkSpace.sm,
                  FolkSpace.pagePadding,
                  // At least 24 dp clear of the pill, in the worst case (small
                  // phone, large text) once scrolled to the end.
                  FolkSpace.xxl + FloatingPillNavBar.reservedHeight(context)),
              child: Column(
                children: [
                  EntryAnimation(index: 0, child: _statTiles()),
                  const SizedBox(height: FolkSpace.cardGap),
                  EntryAnimation(
                    index: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(FolkShape.cardRadius),
                        color: colors.surface,
                        boxShadow: colors.cardShadows,
                      ),
                      padding: EdgeInsets.all(FolkSpace.lg),
                      child: Column(
                        children: [
                          TableCalendar(
                            focusedDay: _focusedDay,
                            selectedDayPredicate: (day) =>
                                isSameDay(_selectedDay, day),

                            // The month on show drives "N of M".
                            onPageChanged: (focused) =>
                                setState(() => _focusedDay = focused),

                            onDaySelected: (selectedDay, focusedDay) {
                              // A submitted day opens its details every time it
                              // is tapped; any other day is just selected, as
                              // before.
                              final submitted = _availableDates
                                  .contains(_getFormattedDate(selectedDay));
                              if (submitted ||
                                  !isSameDay(_selectedDay, selectedDay)) {
                                setState(() {
                                  _selectedDay = selectedDay;
                                  _focusedDay = focusedDay;
                                });
                              }
                              if (submitted) _openDay(selectedDay);
                            },

                            firstDay: DateTime(now.year, now.month - 1, 1),
                            lastDay: DateTime.now(),

                            rowHeight: MediaQuery.of(context).size.width * 0.12,
                            // responsive

                            daysOfWeekHeight: 30,

                            // Months already slide sideways: table_calendar pages
                            // them in a horizontal PageView (swipe or arrows,
                            // 300 ms ease-out). Only "reduce animations" switches
                            // that off.
                            pageAnimationEnabled: !FolkMotion.reduced(context),

                            // Every day is drawn by the builder below.
                            calendarStyle: CalendarStyle(
                              outsideDaysVisible: false,
                            ),

                            daysOfWeekStyle: DaysOfWeekStyle(
                              dowTextFormatter: (date, locale) =>
                                  DateFormat.E(locale).format(date)[0],
                              weekdayStyle: text.caption.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              weekendStyle: text.caption.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            headerStyle: HeaderStyle(
                              titleCentered: true,
                              formatButtonVisible: false,
                              headerPadding:
                                  EdgeInsets.only(bottom: FolkSpace.md),
                              titleTextStyle:
                                  text.topBarTitle.copyWith(fontSize: 19),
                              leftChevronIcon: _chevron(Icons.chevron_left),
                              rightChevronIcon: _chevron(Icons.chevron_right),
                              leftChevronPadding: chevronPadding,
                              rightChevronPadding: chevronPadding,
                              leftChevronMargin: EdgeInsets.zero,
                              rightChevronMargin: EdgeInsets.zero,
                            ),
                            // availableGestures: AvailableGestures.none,

                            calendarBuilders: CalendarBuilders(
                              prioritizedBuilder: (context, date, _) {
                                return SadhanaDayCell(
                                  day: date.day,
                                  state: _dayState(date),
                                  selected: isSameDay(_selectedDay, date),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: SadhanaCalendarGhost.legendGap),
                          const SadhanaLegend(),
                        ],
                      ),
                    ),
                  ),
                  // Normal card spacing, then the button: directly under the
                  // calendar, at the content width, scrolling with the page. A
                  // submitted day's details open in a dialog, so nothing grows
                  // here.
                  const SizedBox(height: FolkSpace.lg),
                  if (_selectedDay == null ||
                      !_availableDates
                          .contains(_getFormattedDate(_selectedDay!)))
                    Padding(
                      padding: EdgeInsets.zero,
                      // Was an endless up-and-down bob; now it arrives once
                      // (fade and rise) and gives press feedback. It keeps its
                      // size and the strongest colour on the page.
                      child: EntryAnimation(
                        index: 2,
                        child: SizedBox(
                          width: double.infinity,
                          child: PrimaryButton(
                            // Violet in both modes; the text is always the ink
                            // colour.
                            gradient: FolkGradients.submitSadhana,
                            label: "📿 Submit Sadhana",
                            onPressed: () async {
                              // Localites (Master Task, 2026-09-03) fill
                              // the same hostel form, since their reports
                              // go to the same hostel-sadhana collection.
                              if (widget.role == 'Stay at Hostel' ||
                                  widget.role == 'Stay at Localite') {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => SadhanaPage()),
                                );
                              } else {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          QuestionsPage()),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ));
          }),
    );
  }

  /// Cross-fades between the ghost, an error and the calendar. All three fill
  /// the same body, so nothing moves.
  Widget _swap(String key, Widget child) {
    return AnimatedSwitcher(
      duration: FolkMotion.of(context, FolkMotion.ghostCrossFade),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey<String>(key), child: child),
    );
  }

  /// Until the report dates have arrived: the calendar card and the submit
  /// button as ghosts, at the exact size and place of the real ones (same
  /// padding, same gaps). The stream that decides when this ends is unchanged.
  Widget _ghostBody() {
    final rowHeight = MediaQuery.of(context).size.width * 0.12;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          FolkSpace.pagePadding,
          FolkSpace.sm,
          FolkSpace.pagePadding,
          FolkSpace.xxl + FloatingPillNavBar.reservedHeight(context)),
      child: GhostScope(
        child: Column(
          children: [
            // The two stat tiles, as ghosts of the same height.
            SizedBox(
              height: 28 +
                  ghostHeight(context, 28 * 1.1) +
                  2 +
                  ghostHeight(context, 12 * 1.43),
              child: const Row(
                children: [
                  Expanded(
                      child: GhostPlaceholder(
                          height: double.infinity,
                          radius: 24,
                          showBars: false)),
                  SizedBox(width: FolkSpace.cardGap),
                  Expanded(
                      child: GhostPlaceholder(
                          height: double.infinity,
                          radius: 24,
                          showBars: false)),
                ],
              ),
            ),
            const SizedBox(height: FolkSpace.cardGap),
            SadhanaCalendarGhost(month: _focusedDay, rowHeight: rowHeight),
            const SizedBox(height: FolkSpace.lg),
            const GhostPlaceholder(
              width: double.infinity,
              height: FolkShape.buttonHeight,
              radius: FolkShape.buttonRadius,
              showBars: false,
            ),
          ],
        ),
      ),
    );
  }
}

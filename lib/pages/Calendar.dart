import 'package:flutter/material.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/utils/MalaLoading.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ColorProvider.dart';

class CalendarPage extends StatefulWidget {
  final String username, role;
  CalendarPage({required this.username, required this.role});

  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with SingleTickerProviderStateMixin {
  DateTime now = DateTime.now();
  late final Map<DateTime, Color> _selectedDayColors;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isLoading = true;
  late Set<String> _availableDates;
  bool showWeekDot = false;
  late AnimationController _dotController; // for in/out animation
  late Stream<QuerySnapshot> _datesStream;

  // Floating button animation
  late AnimationController _buttonController;
  late Animation<double> _buttonAnimation;
  Map<String, dynamic>? _selectedDayData;
  bool _loadingDayData = false;
  bool _datePressed = false;

  @override
  void initState() {
    super.initState();

    _selectedDayColors = {};
    _availableDates = {};

    _datesStream = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(widget.username)
        .collection('dates')
        .snapshots();

    _buttonController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    );

    _buttonAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );

    _buttonController.repeat(reverse: true);
  }
  @override
  void dispose() {
    _buttonController.dispose();
    super.dispose();
  }

  String get collectionName {
    return widget.role == 'Stay at Hostel'
        ? 'hostel-sadhana'
        : 'sadhana-reports';
  }

  Future<void> _fetchSelectedDayData(DateTime selectedDay) async {
    setState(() {
      _loadingDayData = true;
      _selectedDayData = null;
      _datePressed = true;
    });

    try {
      String formattedDate = _getFormattedDate(selectedDay);
      var doc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(widget.username)
          .collection('dates')
          .doc(formattedDate)
          .get();

      setState(() {
        _selectedDayData = doc.exists ? doc.data() : {};
        _loadingDayData = false;
      });
    } catch (e) {
      print('Error fetching day data: $e');
      setState(() {
        _selectedDayData = {};
        _loadingDayData = false;
      });
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

  Widget _selectedDayInfo() {

    final colorProvider = Provider.of<ColorProvider>(context, listen: false);
    if (!_datePressed) return SizedBox.shrink();

    if (_loadingDayData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedDayData == null || _selectedDayData!.isEmpty) {
      return Center(
        child: Text(
          'No data found ❌',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      );
    }

    Map<String, dynamic> data = _selectedDayData!;
    final stats = <Map<String, dynamic>>[
      if (data.containsKey('chantRounds'))
        {
          'label': '📿 Chanting Rounds',
          'value': data['chantRounds'],
          'icon': Icons.bubble_chart
        },

      if (data.containsKey('bookReading'))
        {
          'label': '📚 Book Reading',
          'value': data['bookReading'],
          'icon': Icons.menu_book
        },

      if (data.containsKey('classHearing'))
        {
          'label': '🎧 Class Hearing',
          'value': data['classHearing'],
          'icon': Icons.headphones
        },

      if (data.containsKey('dailyServices'))
        {
          'label': '🛕 Daily Services',
          'value': data['dailyServices'],
          'icon': Icons.volunteer_activism
        },

      if (data.containsKey('templeEntry'))
        {
          'label': '🏛️ Temple Entry',
          'value': data['templeEntry'],
          'icon': Icons.temple_hindu
        },

      if (data.containsKey('finishTiming'))
        {
          'label': '⏰ Finish Timing',
          'value': data['finishTiming'],
          'icon': Icons.access_time
        },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorProvider.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: colorProvider.secondColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sadhana Stats',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorProvider.secondColor,
            ),
          ),
          SizedBox(height: 12),
          ...stats.map((stat) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorProvider.secondColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    stat['icon'],
                    color: colorProvider.secondColor,
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    stat['label'],
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorProvider.secondColor,
                    ),
                  ),
                ),
                Text(
                  stat['value'].toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorProvider.secondColor,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          body: StreamBuilder<QuerySnapshot>(
              stream: _datesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CustomLoader();
                }

                if (snapshot.hasError) {
                  return Center(child: Text("Error: ${snapshot.error}"));
                }

                // 🔥 UPDATE AVAILABLE DATES FROM STREAM
                if (snapshot.hasData) {
                  _availableDates =
                      snapshot.data!.docs.map((doc) => doc.id).toSet();
                }

                return SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04, vertical: 20),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: colorProvider.color.withOpacity(0.95),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: EdgeInsets.all(12),
                        child: TableCalendar(
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),

                          onDaySelected: (selectedDay, focusedDay) {
                            if (!isSameDay(_selectedDay, selectedDay)) {
                              setState(() {
                                _selectedDay = selectedDay;
                                _focusedDay = focusedDay;
                              });
                              String formatted = _getFormattedDate(selectedDay);

                              if (_availableDates.contains(formatted)) {
                                _fetchSelectedDayData(selectedDay);
                              } else {
                                setState(() {
                                  _selectedDayData = null;
                                });
                              }
                            }
                          },

                          firstDay: DateTime(now.year, now.month - 1, 1),
                          lastDay: DateTime.now(),

                          rowHeight: MediaQuery.of(context).size.width * 0.12,
                          // responsive

                          daysOfWeekHeight: 30,

                          calendarStyle: CalendarStyle(
                            outsideDaysVisible: false,
                            todayDecoration: BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color: Colors.deepPurple,
                              shape: BoxShape.circle,
                            ),
                            defaultTextStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            weekendTextStyle: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.redAccent,
                            ),
                            cellMargin: EdgeInsets.all(4),
                          ),

                          daysOfWeekStyle: DaysOfWeekStyle(
                            weekdayStyle: TextStyle(
                              color: colorProvider.secondColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            weekendStyle: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),

                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            titleTextStyle: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: colorProvider.secondColor,
                            ),
                            leftChevronIcon: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black12,
                              ),
                              child: Icon(Icons.chevron_left, size: 20),
                            ),
                            rightChevronIcon: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black12,
                              ),
                              child: Icon(Icons.chevron_right, size: 20),
                            ),
                          ),
                          // availableGestures: AvailableGestures.none,

                          calendarBuilders: CalendarBuilders(
                            defaultBuilder: (context, date, _) {
                              return _buildModernDay(context, date);
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      _selectedDay != null &&
                          _selectedDayData != null &&
                          _selectedDayData!.isNotEmpty
                          ? _selectedDayInfo()
                          : SizedBox(height: 0),
                      SizedBox(height: 20),
                      if (_selectedDay == null ||
                          !_availableDates
                              .contains(_getFormattedDate(_selectedDay!)))
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: AnimatedBuilder(
                            animation: _buttonAnimation,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, _buttonAnimation.value),
                                child: child,
                              );
                            },
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (widget.role == 'Stay at Hostel') {
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
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(50)),
                                  elevation: 10,
                                  backgroundColor: Color(0xFF835DF1),
                                ),
                                child: Text(
                                  "Submit Sadhana",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
        );
      },
    );
  }

  Widget _buildModernDay(BuildContext context, DateTime day) {
    Color statusColor = _getDayColor(day);

    bool isSelected = isSameDay(_selectedDay, day);
    bool isToday = isSameDay(DateTime.now(), day);

    return Container(
      margin: EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: statusColor == Colors.transparent
            ? Colors.white
            : statusColor.withOpacity(0.85), // full color background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
          ),
        ],
        border: isSelected
            ? Border.all(color: Colors.deepPurple, width: 2)
            : isToday
            ? Border.all(color: Colors.blue, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: statusColor == Colors.transparent
                ? Colors.black87
                : Colors.white, // white text on colored bg
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:provider/provider.dart';
import '../utils/ColorProvider.dart';
import '../utils/MalaLoading.dart';

class BooksSelectionScreen extends StatefulWidget {
  @override
  _BooksSelectionScreenState createState() => _BooksSelectionScreenState();
}

class _BooksSelectionScreenState extends State<BooksSelectionScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _currentBook = "Not Mentioned";

  Map<String, List<String>> _readBooks = {};
  Map<String, List<String>> _unreadBooks = {};
  Map<String, Map<String, dynamic>> _bookDetails = {};

  @override
  void initState() {
    super.initState();
    fetchCurrentBook().then((_) => fetchAllLevelsBooks());
  }

  Future<void> fetchAllLevelsBooks() async {
    List<String> levels = ["level-1", "level-2", "level-3"];
    for (String level in levels) {
      await loadBooksForLevel(level);
    }
  }

  Future<void> fetchCurrentBook() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    final snapshot =
    await _firestore.collection('booksRead').doc(userName).get();
    if (snapshot.exists) {
      var data = snapshot.data() as Map<String, dynamic>?;
      setState(() {
        _currentBook = data?['currentBook'] ?? "Not Mentioned";
      });
    }
  }

  Future<void> setCurrentBook(String book) async {
    User? user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    await _firestore
        .collection('booksRead')
        .doc(userName)
        .set({"currentBook": book}, SetOptions(merge: true));

    setState(() {
      _currentBook = book;
    });

    showSnackbar(context, "Current book updated!", Colors.blue, Icons.menu_book);
  }

  Future<void> loadBooksForLevel(String level) async {
    // Get all books for this level
    DocumentSnapshot allBooksSnap = await _firestore.collection('books').doc(level).get();
    List<String> allBooks = [];
    if (allBooksSnap.exists) {
      var data = allBooksSnap.data();
      if (data is Map<String, dynamic>) {
        var sortedKeys = data.keys.toList()
          ..sort((a, b) {
            int aNum = int.parse(a.split('_')[1]);
            int bNum = int.parse(b.split('_')[1]);
            return aNum.compareTo(bNum);
          });
        allBooks = sortedKeys.map((k) => data[k] as String).toList();
      }

    }

    // Get current user
    User? user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    // Get read books for this user and level
    QuerySnapshot readSnap = await _firestore
        .collection('booksRead')
        .doc(userName)
        .collection(level)
        .get();

    List<String> readBooks = [];
    if (readSnap.docs.isNotEmpty) {
      for (var doc in readSnap.docs) {
        readBooks.add(doc.id);
        var bookData = doc.data() as Map<String, dynamic>;

        // Save book details locally, using proper Firestore keys
        _bookDetails["$level:${doc.id}"] = {
          ...bookData,
          "notes": (bookData["madeNotes"] ?? false) == true, // read madeNotes safely
          "expanded": false, // ensure default expanded state
        };
      }
    }

    // Compute unread books
    List<String> unreadBooks = allBooks.where((b) => !readBooks.contains(b)).toList();

    // Update state
    setState(() {
      _readBooks[level] = readBooks;
      _unreadBooks[level] = unreadBooks;
    });
  }

  Future<void> saveBookDetails(String level, String bookKey) async {
    User? user = _auth.currentUser;
    if (user == null) return;

    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    final details = _bookDetails[bookKey];
    if (details == null) return;

    // Enforce start date requirement
    if (details["startDate"] == null || details["startDate"].toString().isEmpty) {
      showSnackbar(context, "Start Date is required!", Colors.red, Icons.error);
      return;
    }

    Map<String, dynamic> bookData = {
      "bookName": bookKey.split(":")[1],
      "startDate": details["startDate"],
      "madeNotes": details["notes"] ?? false,
    };
    if (details["endDate"] != null) {
      bookData["endDate"] = details["endDate"];
    }

    // Save inside level collection
    await _firestore
        .collection('booksRead')
        .doc(userName)
        .collection(bookKey.split(":")[0])
        .doc(bookKey.split(":")[1])
        .set(bookData, SetOptions(merge: true));

    // Handle currentBook logic
    if (details["isCurrent"] == true && details["endDate"] == null) {
      // set as current book
      await _firestore.collection('booksRead').doc(userName).set({
        "currentBook": bookKey.split(":")[1],
      }, SetOptions(merge: true));

      setState(() {
        _currentBook = bookKey.split(":")[1];
      });
    } else if (details["endDate"] != null && _currentBook == bookKey.split(":")[1]) {
      // if endDate added → remove currentBook
      await _firestore.collection('booksRead').doc(userName).set({
        "currentBook": "Not Mentioned",
      }, SetOptions(merge: true));

      setState(() {
        _currentBook = "Not Mentioned";
      });
    }

    // Update local state
    String levelName = bookKey.split(":")[0];
    setState(() {
      _unreadBooks[levelName]?.remove(bookKey.split(":")[1]);
      _readBooks[levelName] = (_readBooks[levelName] ?? [])..add(bookKey.split(":")[1]);
      _bookDetails[bookKey] = {...details}; // refresh
    });

    showSnackbar(context, "Book saved successfully!", Colors.green, Icons.thumb_up_outlined);
  }

  Widget historyCard(Color color) {
    bool isExpanded = _bookDetails["historyExpanded"]?["expanded"] ?? false;

    final bookEntries = _bookDetails.entries
        .where((e) =>
    e.key.contains(":") &&
        (_readBooks[e.key.split(":")[0]] ?? [])
            .contains(e.key.split(":")[1]))
        .toList();

    // Separate active (no endDate) and completed (with endDate)
    final activeBooks =
    bookEntries.where((e) => e.value["endDate"] == null).toList();
    final completedBooks =
    bookEntries.where((e) => e.value["endDate"] != null).toList();

    return Card(
      margin: EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: color.withOpacity(0.85),
      elevation: 8,
      child: Column(
        children: [
          ListTile(
            title: Text("📚 My Books History",
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            trailing: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: Colors.white),
            onTap: () {
              setState(() {
                _bookDetails["historyExpanded"] = {"expanded": !isExpanded};
              });
            },
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  if (activeBooks.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("⏳ Active Books",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white)),
                        SizedBox(height: 8),
                        ...activeBooks.map((e) {
                          return historyBookCard(
                            e.key,
                            e.key.split(":")[0],
                            isCompleted: false,
                          );
                        }).toList(),
                        SizedBox(height: 12),
                      ],
                    ),
                  if (completedBooks.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("✅ Completed Books",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.white)),
                        SizedBox(height: 8),
                        ...completedBooks.map((e) {
                          return historyBookCard(
                            e.key,
                            e.key.split(":")[0],
                            isCompleted: true,
                          );
                        }).toList(),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Inside historyBookCard:
  Widget historyBookCard(String bookKey, String level, {required bool isCompleted}) {
    final details = _bookDetails[bookKey] ??
        {"startDate": null, "endDate": null, "notes": false, "expanded": false};
    bool isExpanded = details["expanded"] ?? false;
    final bookName = bookKey.split(":")[1];

    String notesEmoji = (details["notes"] ?? false) ? "📝" : "❌";
    bool isActive = details["endDate"] == null;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text("$bookName $notesEmoji",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (_currentBook == bookName)
                  Icon(Icons.star, color: Colors.orange, size: 20),
              ],
            ),
            subtitle: Text(
                "Start: ${details["startDate"] ?? "-"} | End: ${details["endDate"] ?? "-"}"),
            trailing: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            onTap: () {
              setState(() {
                _bookDetails[bookKey] = {...details, "expanded": !isExpanded};
              });
            },
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  datePickerRow("Start Date", details["startDate"], (val) {
                    setState(() {
                      _bookDetails[bookKey] = {...details, "startDate": val, "expanded": true};
                    });
                  }),
                  SizedBox(height: 8),
                  datePickerRow("End Date", details["endDate"], (val) async {
                    bool? madeNotes = details["notes"];
                    if (!isCompleted) {
                      madeNotes = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text("Made Notes?"),
                          content: Text("Did you make notes for this book?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("No")),
                            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Yes")),
                          ],
                        ),
                      );
                    }

                    setState(() {
                      _bookDetails[bookKey] = {
                        ...details,
                        "endDate": val,
                        "notes": madeNotes ?? false,
                        "expanded": false
                      };
                    });

                    await saveBookDetails(level, bookKey);
                  }),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text("Made Notes? "),
                      DropdownButton<bool>(
                        value: details["notes"],
                        hint: Text("Select"),
                        items: [
                          DropdownMenuItem(value: true, child: Text("Yes")),
                          DropdownMenuItem(value: false, child: Text("No")),
                        ],
                        onChanged: (val) async {
                          setState(() {
                            _bookDetails[bookKey] = {...details, "notes": val, "expanded": true};
                          });
                          await saveBookDetails(level, bookKey);
                        },
                      ),
                    ],
                  ),
                  if (isActive) // Show checkbox only for active books
                    Row(
                      children: [
                        Text("Set as Current Book? "),
                        Checkbox(
                          value: _currentBook == bookName,
                          onChanged: (val) async {
                            if (val == true) {
                              await setCurrentBook(bookName);
                            } else {
                              await setCurrentBook("Not Mentioned");
                            }
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }



  Widget levelCard(String level, String title, Color color) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 8),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        color: color.withOpacity(0.85),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey(level),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            iconColor: Colors.white, // arrow color when expanded
            collapsedIconColor: Colors.white, // arrow color when collapsed
            children: [
              if ((_unreadBooks[level] ?? []).isEmpty &&
                  (_readBooks[level] ?? []).isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: CustomLoader()
                )
              else
                Column(
                  children: [
                    ...(_unreadBooks[level] ?? [])
                        .map((book) => bookCard(book, level)),
                    const SizedBox(height: 8),
                  ],
                ),
            ],
            onExpansionChanged: (expanded) {
              if (expanded) loadBooksForLevel(level);
            },
          ),
        ),
      ),
    );
  }

  Widget bookCard(String book, String level) {
    final key = "$level:$book";
    final details = _bookDetails[key] ??
        {"startDate": null, "endDate": null, "notes": null, "expanded": false};

    bool isExpanded = details["expanded"] ?? false;
    bool isActive = details["endDate"] == null && details["startDate"] != null;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(
                  child: Text(book, style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (_currentBook == book)
                  Icon(Icons.star, color: Colors.orange, size: 20),
              ],
            ),
            trailing: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            onTap: () {
              setState(() {
                _bookDetails[key] = {...details, "expanded": !isExpanded};
              });
            },
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  datePickerRow("Start Date", details["startDate"], (val) {
                    setState(() {
                      _bookDetails[key] = {...details, "startDate": val, "expanded": true};
                    });
                  }),
                  SizedBox(height: 8),
                  datePickerRow("End Date", details["endDate"], (val) {
                    setState(() {
                      _bookDetails[key] = {...details, "endDate": val, "expanded": true};
                    });
                  }),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text("Made Notes? "),
                      DropdownButton<bool>(
                        value: details["notes"],
                        hint: Text("Select"),
                        items: [
                          DropdownMenuItem(value: true, child: Text("Yes")),
                          DropdownMenuItem(value: false, child: Text("No")),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _bookDetails[key] = {...details, "notes": val, "expanded": true};
                          });
                        },
                      ),
                    ],
                  ),
                  if (isActive)
                    Row(
                      children: [
                        Text("Set as Current Book? "),
                        Checkbox(
                          value: _currentBook == book,
                          onChanged: (val) async {
                            if (val == true) {
                              await setCurrentBook(book);
                            } else {
                              await setCurrentBook("Not Mentioned");
                            }
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => saveBookDetails(level, key),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.deepPurple,
                    ),
                    child: Text("Save", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget datePickerRow(
      String title, String? value, Function(String) onSelected) {
    return Row(
      children: [
        Text("$title: "),
        Text(value ?? "Not set"),
        Spacer(),
        IconButton(
          icon: Icon(Icons.calendar_today),
          onPressed: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null)
              onSelected(picked.toIso8601String().split("T")[0]);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            title: Text("Select Books You Read",
                style: TextStyle(color: colorProvider.secondColor)),
            backgroundColor: colorProvider.color,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: ListView(
            padding: EdgeInsets.all(16),
            children: [
              levelCard("level-1", "✨ Level 1", colorProvider.thirdColor),
              levelCard("level-2", "🔥 Level 2", colorProvider.thirdColor),
              levelCard("level-3", "🙇 Level 3", colorProvider.thirdColor),
              SizedBox(height: 20,),
              Divider(),
              SizedBox(height: 20,),
              Text(
                "📖 Current Book: $_currentBook",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorProvider.secondColor,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20,),
              Divider(),
              SizedBox(height: 20,),
              historyCard(colorProvider.thirdColor),
            ],
          ),
        );
      },
    );
  }
}



import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';

class AssignedTasks extends StatefulWidget {
  final String uid;

  const AssignedTasks({super.key, required this.uid});

  @override
  State<AssignedTasks> createState() => AssignedTasksState();
}

class AssignedTasksState extends State<AssignedTasks> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> updateAnswer(String level, String qKey, bool value) async {
    await firestore
        .collection("users")
        .doc(widget.uid)
        .collection("questions")
        .doc(level)
        .update({"$qKey.completed": value});
  }

  Widget questionTile(String level, String qKey, Map data) {
    bool completed = data["completed"];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: completed
            ? const LinearGradient(
                colors: [Color(0xffe8f5e9), Color(0xffc8e6c9)])
            : const LinearGradient(
                colors: [Color(0xfff5f5f5), Color(0xffeeeeee)]),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data["question"],
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (completed) const Icon(Icons.check_circle, color: Colors.green)
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    updateAnswer(level, qKey, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("YES"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    updateAnswer(level, qKey, false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text("NO"),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget levelCard(String level) {
    return StreamBuilder<DocumentSnapshot>(
      stream: firestore
          .collection("users")
          .doc(widget.uid)
          .collection("questions")
          .doc(level)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        Map<String, dynamic> data =
            snapshot.data!.data() as Map<String, dynamic>;

        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            level.toUpperCase(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          children: data.entries.map((entry) {
            return questionTile(level, entry.key, entry.value);
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: AppBar(
          leading: IconButton(onPressed: (){
            Navigator.pop(context);
          }, icon: Icon(Icons.arrow_back_outlined,color: colorProvider.secondColor,)),
          backgroundColor: colorProvider.color,
          elevation: 0,
          centerTitle: true,
          title: Text(
            "Knowledge Assessment",
            style: TextStyle(
              color: colorProvider.secondColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: const [
            SizedBox(height: 10),
            _LevelWidget(level: "level-1"),
            _LevelWidget(level: "level-2"),
            _LevelWidget(level: "level-3"),
            _LevelWidget(level: "level-4"),
            _LevelWidget(level: "level-5"),
          ],
        ),
      );
    });
  }
}

class _LevelWidget extends StatelessWidget {
  final String level;

  const _LevelWidget({required this.level});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final colorProvider = Provider.of<ColorProvider>(context, listen: false);
    final uid =
        (context.findAncestorStateOfType<AssignedTasksState>()!).widget.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: firestore
          .collection("users")
          .doc(uid)
          .collection("questions")
          .doc(level)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        if (data == null) {
          return const Center(child: Text("No questions found"));
        }

        int total = data.length;
        int completed = data.values.where((e) => e["completed"] == true).length;
        double progress = total == 0 ? 0 : completed / total;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 6),
                color: Colors.black.withOpacity(0.05),
              )
            ],
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      level.toUpperCase(),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      "$completed / $total",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                ),
              ],
            ),
            children: data.entries.map((entry) {
              bool completed = entry.value["completed"];

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  firestore
                      .collection("users")
                      .doc(uid)
                      .collection("questions")
                      .doc(level)
                      .update({"${entry.key}.completed": !completed});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color:
                        completed ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: completed ? Colors.green : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 22,
                        width: 22,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: completed ? Colors.green : Colors.grey,
                            width: 2,
                          ),
                          color: completed ? Colors.green : Colors.transparent,
                        ),
                        child: completed
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          entry.value["question"],
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            decoration:
                                completed ? TextDecoration.lineThrough : null,
                            color: completed ? Colors.black54 : Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

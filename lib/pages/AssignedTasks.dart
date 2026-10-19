import 'package:flutter/material.dart';
import '../widgets/FolkErrorRetry.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PressScale.dart';

class AssignedTasks extends StatefulWidget {
  final String uid;

  const AssignedTasks({super.key, required this.uid});

  @override
  State<AssignedTasks> createState() => AssignedTasksState();
}

class AssignedTasksState extends State<AssignedTasks> {
  // Reads every level again (their streams are built in `build`).
  void refresh() => setState(() {});

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
    final colors = context.folk;
    final text = context.folkText;
    bool completed = data["completed"];

    return AnimatedContainer(
      duration: FolkMotion.of(context, const Duration(milliseconds: 300)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        color: colors.surface,
        gradient: completed ? FolkGradients.green : null,
        boxShadow: colors.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data["question"],
                  style: text.bodyStrong.copyWith(
                      color: completed ? FolkColors.onGradient : colors.text),
                ),
              ),
              if (completed)
                const Icon(Icons.check_circle, color: FolkColors.onGradient)
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
                    minimumSize: const Size.fromHeight(FolkShape.touchTarget),
                    elevation: 0,
                    backgroundColor: colors.primaryBg,
                    foregroundColor: colors.primaryFg,
                    textStyle: text.button,
                    shape: const StadiumBorder(),
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
                    minimumSize: const Size.fromHeight(FolkShape.touchTarget),
                    elevation: 0,
                    backgroundColor: colors.surfaceSecondary,
                    foregroundColor: colors.text,
                    textStyle: text.button.copyWith(color: colors.text),
                    shape: const StadiumBorder(),
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
        if (snapshot.hasError) {
          return FolkErrorRetry(
            compact: true,
            message: "Couldn't load this level just now.",
            onRetry: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const GhostPlaceholder(
              width: double.infinity,
              height: 88,
              radius: FolkShape.cardRadius,
              showBars: false);
        }

        Map<String, dynamic> data =
            snapshot.data!.data() as Map<String, dynamic>;

        return ExpansionTile(
          iconColor: context.folk.text,
          collapsedIconColor: context.folk.mutedText,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            level.toUpperCase(),
            style: context.folkText.topBarTitle,
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
    return FolkScaffold(
      title: "Knowledge Assessment",
      onBack: () {
        Navigator.pop(context);
      },
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            FolkSpace.pagePadding, 10, FolkSpace.pagePadding, 30),
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
  }
}

class _LevelWidget extends StatelessWidget {
  final String level;

  const _LevelWidget({required this.level});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    final colors = context.folk;
    final text = context.folkText;
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
        if (snapshot.hasError) {
          return FolkErrorRetry(
            compact: true,
            message: "Couldn't load this level just now.",
            onRetry: () => context
                .findAncestorStateOfType<AssignedTasksState>()
                ?.refresh(),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: GhostPlaceholder(
                width: double.infinity,
                height: 88,
                radius: FolkShape.cardRadius,
                showBars: false),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;

        if (data == null) {
          return Center(child: Text("No questions found", style: text.body));
        }

        int total = data.length;
        int completed = data.values.where((e) => e["completed"] == true).length;
        double progress = total == 0 ? 0 : completed / total;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FolkShape.cardRadius),
            boxShadow: colors.cardShadows,
          ),
          // ExpansionTile paints its header/ink via the nearest Material
          // ancestor — without one here, the Container's own colour above
          // sits between it and the Scaffold's Material, triggering
          // "ListTile background color or ink splashes may be invisible"
          // (recurred three times in this project already — same fix each
          // time).
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(FolkShape.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                iconColor: colors.text,
                collapsedIconColor: colors.mutedText,
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
                          style: text.topBarTitle.copyWith(fontSize: 17),
                        ),
                        Text(
                          "$completed / $total",
                          style: text.small
                              .copyWith(fontWeight: FontWeight.w500),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: colors.surfaceSecondary,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            FolkCalendarTokens.legendSubmitted),
                      ),
                    ),
                  ],
                ),
                children: data.entries.map((entry) {
                  bool completed = entry.value["completed"];

                  return PressScale(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                      onTap: () {
                        firestore
                            .collection("users")
                            .doc(uid)
                            .collection("questions")
                            .doc(level)
                            .update({"${entry.key}.completed": !completed});
                      },
                      child: AnimatedContainer(
                        duration: FolkMotion.of(context, const Duration(milliseconds: 200)),
                        constraints: const BoxConstraints(
                            minHeight: FolkShape.touchTarget),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceSecondary,
                          borderRadius:
                              BorderRadius.circular(FolkShape.tileRadius),
                          border: Border.all(
                            color: completed
                                ? FolkCalendarTokens.legendSubmitted
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: FolkMotion.of(context, const Duration(milliseconds: 200)),
                              height: 24,
                              width: 24,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: completed
                                      ? FolkCalendarTokens.legendSubmitted
                                      : colors.disabledText,
                                  width: 2,
                                ),
                                color: completed
                                    ? FolkCalendarTokens.legendSubmitted
                                    : Colors.transparent,
                              ),
                              child: completed
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: FolkColors.onGradient,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                entry.value["question"],
                                style: text.body.copyWith(
                                  fontWeight: FontWeight.w500,
                                  decoration: completed
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color:
                                      completed ? colors.mutedText : colors.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

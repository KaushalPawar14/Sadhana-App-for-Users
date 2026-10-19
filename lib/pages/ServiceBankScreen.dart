import 'package:flutter/material.dart';
import '../widgets/FolkErrorRetry.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SeenMarkers.dart';
import '../utils/ServiceAssignments.dart';
import '../utils/ServiceBankContent.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/GradientCard.dart';

/// Service Bank — replaces `pages/DevotionalServiceScreen.dart` entirely
/// (Service Bank task, Part 5). Reached from the same "D" tile on
/// `ABCDEScreen.dart` the old screen used, with the same constructor shape.
///
/// ---------------------------------------------------------------------------
/// Part 5 item 4 — shows ALL 19 services, not only the assigned ones
/// ---------------------------------------------------------------------------
/// Recommended and implemented: the content is a fixed, identical-for-
/// everyone curriculum (Part 2), so a student benefits from seeing the
/// whole roadmap ahead of them, not just what's currently assigned — the
/// same reasoning the old screen already applied to its 3 "Standard
/// Services" (shown to everyone regardless of assignment), just extended to
/// all 19 instead of 3. "Assigned to Me" stays the first, primary section
/// (with status controls); "All Services" below it is read-only reference
/// material for anything not currently assigned to this student.
///
/// ---------------------------------------------------------------------------
/// Part 5 item 3 / Rule 14/15 — competence is immune to any write here
/// ---------------------------------------------------------------------------
/// This file imports `utils/ServiceAssignments.dart` (this app's OWN copy —
/// see that file's header). That file has no `setCompetence` function at
/// all, so there is no code path anywhere in this screen that could write a
/// `competence` field — not a hidden check, an absent capability. The only
/// write anywhere below is [updateAssignmentStatus], and it never touches
/// `competence`.
class ServiceBankScreen extends StatefulWidget {
  final String uid;
  final String userName;
  final String role;

  const ServiceBankScreen({
    super.key,
    required this.uid,
    required this.userName,
    required this.role,
  });

  @override
  State<ServiceBankScreen> createState() => _ServiceBankScreenState();
}

class _ServiceBankScreenState extends State<ServiceBankScreen> {
  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) —
  /// `assignmentsForStudentStream` (`utils/ServiceAssignments.dart`) used to
  /// be called fresh directly in `build()`, itself building a new
  /// `.where(...).snapshots()` query each time. Hoisted to a field, built
  /// once in `initState()` — safe unconditionally, since `widget.uid` is
  /// fixed for this screen's whole life (a pushed, single-student route).
  /// `ServiceAssignments.dart`'s own query (filters, scoping) is unchanged —
  /// only where it gets called from moved.
  late Stream<List<ServiceAssignment>> _assignmentsStream;

  @override
  void initState() {
    super.initState();
    _assignmentsStream = assignmentsForStudentStream(widget.uid);
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // service assignments.
    SeenMarkers.markSeen(widget.uid, 'serviceAssignments');
  }

  Future<void> _advanceStatus(ServiceAssignment assignment) async {
    final order = [kStatusAssigned, kStatusInProgress, kStatusCompleted];
    final currentIndex = order.indexOf(assignment.status);
    if (currentIndex == -1 || currentIndex >= order.length - 1) return;

    await updateAssignmentStatus(
      assignmentId: assignment.id,
      newStatus: order[currentIndex + 1],
      updatedBy: widget.uid,
    );
  }

  // Assigned = violet, in progress = saffron, completed = green; the text on
  // each is always the dark ink.
  FolkGradientStyle _statusStyle(String status) {
    switch (status) {
      case kStatusCompleted:
        return FolkGradientStyle.green;
      case kStatusInProgress:
        return FolkGradientStyle.saffron;
      default:
        return FolkGradientStyle.violet;
    }
  }

  Widget _statusChip(ServiceAssignment assignment) {
    final text = context.folkText;
    final isCompleted = assignment.status == kStatusCompleted;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: FolkGradients.of(_statusStyle(assignment.status)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            statusLabel(assignment.status),
            style: text.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: FolkColors.onGradient,
            ),
          ),
          if (!isCompleted) ...[
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward,
                size: 14, color: FolkColors.onGradient),
          ],
        ],
      ),
    );
    if (isCompleted) return chip;
    // The whole chip is the "next status" button, in a 48 dp tall hit area.
    return Semantics(
      button: true,
      label: 'Move to the next status',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _advanceStatus(assignment),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: FolkShape.touchTarget),
          child: Align(alignment: Alignment.centerLeft, child: chip),
        ),
      ),
    );
  }

  Widget _competenceRow(ServiceCompetence competence) {
    final colors = context.folk;
    final text = context.folkText;
    final isYes = competence.level == kCompetenceYes;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isYes ? Icons.check_circle : Icons.hourglass_bottom,
              size: 16,
              color: isYes
                  ? FolkCalendarTokens.legendSubmitted
                  : colors.mutedText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              // Read-only display of the guide's own assessment — see this
              // file's header for why nothing here can ever write this.
              "Guide assessment: ${isYes ? 'Yes' : 'Not yet'}"
              "${competence.note != null ? ' — ${competence.note}' : ''}",
              style: text.small.copyWith(
                  fontSize: 12.5, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceExpansionTile(ServiceBankEntry service,
      {ServiceAssignment? assignment}) {
    final colors = context.folk;
    final text = context.folkText;
    return Container(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        boxShadow: colors.cardShadows,
      ),
      clipBehavior: Clip.antiAlias,
      // ExpansionTile paints its header/ink via the nearest Material
      // ancestor — without one here, the Container's own colour above sits
      // between it and the Scaffold's Material, triggering "ListTile
      // background color or ink splashes may be invisible" (this exact
      // warning has recurred three times in this project already — same fix
      // each time).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            iconColor: colors.text,
            collapsedIconColor: colors.mutedText,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: FolkGradients.green,
              ),
              child: Center(
                child: Text("${service.number}",
                    style: text.bodyStrong.copyWith(
                        fontSize: 14, color: FolkColors.onGradient)),
              ),
            ),
            title: Text(service.title,
                style: text.bodyStrong.copyWith(fontSize: 14.5, height: 1.3)),
            subtitle: assignment == null
                ? null
                : Row(children: [_statusChip(assignment)]),
            children: [
              if (assignment != null && assignment.competence != null)
                _competenceRow(assignment.competence!),
              const SizedBox(height: 8),
              ...service.subPoints.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("•  ", style: text.bodyStrong),
                        Expanded(
                            child: Text(p,
                                style: text.body
                                    .copyWith(fontSize: 13.5, height: 1.4))),
                      ],
                    ),
                  )),
              if (service.nuance != null) ...[
                const SizedBox(height: 6),
                GradientCard(
                  style: FolkGradientStyle.warm,
                  radius: 16,
                  padding: const EdgeInsets.all(12),
                  decorate: false,
                  child: Text(service.nuance!,
                      style: text.body.copyWith(
                          fontSize: 13,
                          color: FolkColors.onGradient,
                          height: 1.4)),
                ),
              ],
              if (service.context != null) ...[
                const SizedBox(height: 6),
                Text(service.context!,
                    style: text.small.copyWith(
                        fontSize: 12.5,
                        fontStyle: FontStyle.italic,
                        height: 1.4)),
              ],
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: colors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(16)),
                child: Text(
                  "Assessment question: “${service.assessmentQuestion}”",
                  style: text.bodyStrong
                      .copyWith(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FolkSpace.md),
      child: Text(label, style: context.folkText.topBarTitle.copyWith(fontSize: 18)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkScaffold(
      title: "Service Bank",
      body: StreamBuilder<List<ServiceAssignment>>(
        stream: _assignmentsStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return FolkErrorRetry(
              message: "Couldn't load your services just now.",
              onRetry: () => setState(() {
                _assignmentsStream = assignmentsForStudentStream(widget.uid);
              }),
            );
          }
          if (!snap.hasData) {
            // Ghost rows while the assignments load.
            return GhostScope(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(FolkSpace.pagePadding),
                children: [
                  for (var i = 0; i < 5; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: FolkSpace.cardGap),
                      child: GhostPlaceholder(
                        width: double.infinity,
                        height: 64,
                        radius: FolkShape.tileRadius,
                        showBars: false,
                      ),
                    ),
                ],
              ),
            );
          }

          final active = snap.data!.where((a) => !a.isWithdrawn).toList()
            ..sort((a, b) => a.serviceNumber.compareTo(b.serviceNumber));
          final assignedNumbers = active.map((a) => a.serviceNumber).toSet();

          return ListView(
            padding: const EdgeInsets.all(FolkSpace.pagePadding),
            physics: const BouncingScrollPhysics(),
            children: [
              _sectionHeading("Assigned to Me"),
              if (active.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                      boxShadow: colors.cardShadows),
                  child: Text("No services assigned yet", style: text.small),
                )
              else
                ...active.map((a) {
                  final service = kServiceBank.firstWhere(
                      (s) => s.number == a.serviceNumber,
                      orElse: () => kServiceBank.first);
                  return _serviceExpansionTile(service, assignment: a);
                }),
              const SizedBox(height: 26),
              _sectionHeading("All Services"),
              ...kServiceBank
                  .where((s) => !assignedNumbers.contains(s.number))
                  .map((s) => _serviceExpansionTile(s)),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

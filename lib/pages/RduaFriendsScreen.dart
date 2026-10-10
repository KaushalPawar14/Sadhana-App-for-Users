import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/StudentApi.dart';
import '../utils/SameGender.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkChip.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';
import '../widgets/RoundIconButton.dart';

/// RDUA Friends — friend requests, groups, and group voice rooms.
///
/// Schema (all additive, all Rule-12-justified in `functions/rduaFriends.js`
/// where each collection is first written server-side; client writes below
/// mirror the exact same shapes):
///   friendRequests/{autoId}   fromUid, fromName, toUid, toName, status, createdAt
///   friends/{uid}/list/{friendUid}   friendUid, name, role, guideId, addedAt
///   friendGroups/{uid}/groups/{groupId}   groupName, memberUids, createdAt, updatedAt
///   voiceRooms/{roomId}   createdBy, createdByName, status, roomCode,
///                         participantUids, createdAt, endedAt
///
/// Search never surfaces `mobileNumber` — only `name` + `role` + `guideId`
/// (Part 1 item 1's real fields), matching the task's explicit privacy
/// requirement.
class RduaFriendsScreen extends StatefulWidget {
  const RduaFriendsScreen({super.key});

  @override
  State<RduaFriendsScreen> createState() => _RduaFriendsScreenState();
}

class _RduaFriendsScreenState extends State<RduaFriendsScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late final TabController _tabController;
  String? _uid;
  String? _myName;

  /// Who is of my gender. A student sees, finds, and connects with students of
  /// their own gender only; until this is read nothing about other students is
  /// shown.
  GenderDirectory? _directory;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — these
  /// three used to be constructed fresh inside `_friendsTab`/`_requestsTab`/
  /// `_groupsTab`, called directly from `build()` — and this screen rebuilds
  /// on every tab switch too (`_handleTabChange`'s own `setState`), not just
  /// a `ColorProvider` toggle, so this was a particularly high-frequency
  /// instance of the bug. `uid` isn't known synchronously in `initState()`
  /// here (unlike `ABCDEScreen.dart`/`Profile.dart`) — it only resolves once
  /// `_loadSelf()`'s async read completes — so these are built there
  /// instead, the ONE time `_uid` transitions from null to set (`build()`'s
  /// own `uid == null` branch never even calls the three tab methods before
  /// that happens, so there is no earlier moment these could be needed).
  /// `_uid` never changes again afterward, so this is still "build once,"
  /// just deferred to when the value is first known rather than forced into
  /// `initState()`.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _friendsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _requestsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _groupsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // The floating-action column below shows an extra Groups-only button
    // (see build()), so it needs to rebuild whenever the selected tab
    // changes, not just when the tab content itself changes.
    _tabController.addListener(_handleTabChange);
    _loadSelf();
  }

  void _handleTabChange() {
    if (mounted) setState(() {});
    // Master Task 2026-09-10, Part 6 — "seen" for friend requests is
    // opening THIS tab specifically (index 1), not the whole screen —
    // Friends/Groups are unrelated content.
    if (_tabController.index == 1 && _uid != null) {
      SeenMarkers.markSeen(_uid!, 'friendRequests');
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSelf() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await _firestore.collection('users').doc(user.uid).get();
    GenderDirectory? directory;
    try {
      directory = await GenderDirectory.forCurrentUser();
    } catch (_) {
      // Without it no other student is shown or addable: this fails closed.
    }
    if (!mounted) return;
    setState(() {
      _directory = directory;
      _uid = user.uid;
      _myName = (snap.data()?['name'] ?? 'Student').toString();
      _friendsStream = _firestore
          .collection('friends')
          .doc(user.uid)
          .collection('list')
          .snapshots();
      _requestsStream = _firestore
          .collection('friendRequests')
          .where('toUid', isEqualTo: user.uid)
          .snapshots();
      _groupsStream = _firestore
          .collection('friendGroups')
          .doc(user.uid)
          .collection('groups')
          .snapshots();
    });
  }

  // ---------------------------------------------------------------------------
  // Search + send request
  // ---------------------------------------------------------------------------

  // Documents (friends/{uid}/list) of students of my gender; the document id is
  // the friend's uid. Nothing before the directory has been read.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sameGender(
          Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs) =>
      [
        for (final d in docs)
          if (_directory?.sameByUid(d.id) ?? false) d,
      ];

  Future<void> _openSearch() async {
    final uid = _uid;
    final myName = _myName;
    if (uid == null || myName == null) return;

    List<Map<String, dynamic>> results = [];
    bool searched = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> runSearch(String q) async {
              final trimmed = q.trim().toLowerCase();
              if (trimmed.isEmpty) {
                setSheetState(() {
                  results = [];
                  searched = false;
                });
                return;
              }
              // No full-text search exists anywhere in this project
              // (Part 1 item 2) — fetch the small real roster once and
              // filter client-side, matching this project's own repeated
              // precedent for collections at this scale.
              // Same-gender search runs on the server: a student cannot read
              // other students' documents.
              List<Map<String, dynamic>> matches;
              try {
                matches = await StudentApi.instance.searchStudents(trimmed);
              } catch (_) {
                matches = const [];
              }
              setSheetState(() {
                results = matches;
                searched = true;
              });
            }

            final colors = context.folk;
            final text = context.folkText;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * .75,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(FolkShape.cardRadius)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Find a friend",
                        style: text.topBarTitle.copyWith(fontSize: 18)),
                    const SizedBox(height: 14),
                    TextField(
                      autofocus: true,
                      onChanged: runSearch,
                      style: text.body,
                      cursorColor: colors.text,
                      decoration: FolkDialog.field(context,
                              hint: "Search by name")
                          .copyWith(
                              prefixIcon:
                                  Icon(Icons.search, color: colors.mutedText)),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: !searched
                          ? const SizedBox()
                          : results.isEmpty
                              ? Center(
                                  child: Text("No students found",
                                      style: text.body))
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (context, i) {
                                    final r = results[i];
                                    final name = (r['name'] ?? '').toString();
                                    final role = (r['role'] ?? '').toString();
                                    final guideId =
                                        (r['guideId'] ?? '').toString();
                                    // Disambiguation context only —
                                    // `mobileNumber`/`email` are never read
                                    // into `r`'s displayed fields here.
                                    final context2 = [
                                      if (role.isNotEmpty) role,
                                      if (guideId.isNotEmpty)
                                        "$guideId's group",
                                    ].join(' · ');

                                    // This sheet's own outer Container has a
                                    // colour with no Material between it and
                                    // this ListTile, which triggers "ListTile
                                    // background color or ink splashes may be
                                    // invisible" (recurred three times in this
                                    // project already — same fix each time).
                                    return Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        leading: Container(
                                          width: 40,
                                          height: 40,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: FolkGradients.violet,
                                          ),
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: text.bodyStrong.copyWith(
                                                color: FolkColors.onGradient),
                                          ),
                                        ),
                                        title:
                                            Text(name, style: text.bodyStrong),
                                        subtitle: context2.isEmpty
                                            ? null
                                            : Text(context2,
                                                style: text.small
                                                    .copyWith(fontSize: 12)),
                                        trailing: TextButton(
                                          style: FolkDialog.quietButton(
                                                  colors, text)
                                              .copyWith(
                                                  foregroundColor:
                                                      WidgetStatePropertyAll(
                                                          colors.text)),
                                          onPressed: () async {
                                            await _sendFriendRequest(
                                              fromUid: uid,
                                              fromName: myName,
                                              toUid: r['uid'].toString(),
                                              toName: name,
                                            );
                                            if (context.mounted) {
                                              Navigator.pop(sheetContext);
                                            }
                                          },
                                          child: const Text("Add"),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendFriendRequest({
    required String fromUid,
    required String fromName,
    required String toUid,
    required String toName,
  }) async {
    try {
      // A request can only go to a student of the same gender, whatever
      // brought the other student here.
      final directory = _directory;
      if (directory == null || !directory.sameByUid(toUid)) {
        if (mounted) {
          showSnackbar(context, "You can only add students of your own gender.",
              Colors.orange, Icons.info_outline);
        }
        return;
      }

      // Avoid a duplicate pending request to the same person — one
      // equality filter, checked in Dart, same shape this project always
      // uses (see the file-wide note on avoiding composite indexes).
      final existing = await _firestore
          .collection('friendRequests')
          .where('fromUid', isEqualTo: fromUid)
          .get();
      final alreadyPending = existing.docs.any(
          (d) => d.data()['toUid'] == toUid && d.data()['status'] == 'pending');
      if (alreadyPending) {
        if (mounted) {
          showSnackbar(context, "Request already sent", Colors.orange,
              Icons.info_outline);
        }
        return;
      }

      await _firestore.collection('friendRequests').add({
        'fromUid': fromUid,
        'fromName': fromName,
        'toUid': toUid,
        'toName': toName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        showSnackbar(
            context, "Friend request sent", Colors.green, Icons.check_circle);
      }
    } catch (_) {
      if (mounted) {
        showSnackbar(
            context, "Could not send request", Colors.red, Icons.error);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Respond to requests
  // ---------------------------------------------------------------------------

  Future<void> _respondToRequest(
      String requestId, Map<String, dynamic> data, bool accept) async {
    try {
      if (!accept) {
        await _firestore.collection('friendRequests').doc(requestId).update({
          'status': 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Accepting is done on the server: it checks the request is addressed to
      // you, still pending and between two students of the same gender, then
      // writes BOTH friend lists and marks the request accepted (a student may
      // not write another student's list).
      await StudentApi.instance.acceptFriendRequest(requestId);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        showSnackbar(context, e.message ?? "Could not update request",
            Colors.orange, Icons.info_outline);
      }
    } catch (_) {
      if (mounted) {
        showSnackbar(
            context, "Could not update request", Colors.red, Icons.error);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------

  Future<void> _createGroup(String uid) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return FolkDialog.alert(
          dialogContext,
          title: "New group",
          content: TextField(
            controller: controller,
            autofocus: true,
            style: text.body,
            cursorColor: colors.text,
            decoration: FolkDialog.field(dialogContext, hint: "Group name"),
          ),
          actions: [
            TextButton(
              style: FolkDialog.quietButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: FolkDialog.primaryButton(colors, text),
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text("Create"),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;

    await _firestore
        .collection('friendGroups')
        .doc(uid)
        .collection('groups')
        .add({
      'groupName': name,
      'memberUids': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _manageGroupMembers(
      String uid, String groupId, List<String> currentMembers) async {
    final sheetColor = context.folk.surface;
    final friendsSnap = await _firestore
        .collection('friends')
        .doc(uid)
        .collection('list')
        .get();
    final selected = Set<String>.from(currentMembers);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sheetColor,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(FolkShape.cardRadius)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = context.folk;
            final text = context.folkText;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Group members",
                      style: text.topBarTitle.copyWith(fontSize: 18)),
                  const SizedBox(height: 10),
                  if (_sameGender(friendsSnap.docs).isEmpty)
                    Text("You have no friends to add yet.", style: text.body),
                  ..._sameGender(friendsSnap.docs).map((d) {
                    final friendUid = d.id;
                    final name = (d.data()['name'] ?? '').toString();
                    return CheckboxListTile(
                      activeColor: colors.primaryBg,
                      checkColor: colors.primaryFg,
                      value: selected.contains(friendUid),
                      title: Text(name, style: text.bodyStrong),
                      onChanged: (v) => setSheetState(() {
                        if (v == true) {
                          selected.add(friendUid);
                        } else {
                          selected.remove(friendUid);
                        }
                      }),
                    );
                  }),
                  const SizedBox(height: 10),
                  PrimaryButton(
                    label: "Save",
                    onPressed: () async {
                      await _firestore
                          .collection('friendGroups')
                          .doc(uid)
                          .collection('groups')
                          .doc(groupId)
                          .update({
                        'memberUids': selected.toList(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Rooms
  // ---------------------------------------------------------------------------

  /// ZegoCloud removal (2026-09-09, size/perf task) — voice rooms are no
  /// longer wired to any real backend (see `VoiceRoomService.dart`'s own
  /// header). This used to check the caller's friend groups, optionally
  /// show a "which group?" picker, create a real `voiceRooms` document
  /// (with a room code from the now-removed `_generateRoomCode`), call
  /// `sendRoomInvites`, and only then push `VoiceRoomScreen`. All of that
  /// is removed rather than left unreachable behind an early return —
  /// there is no reason to create a room document or notify a group about
  /// a room nobody can actually talk in. Friends and groups themselves are
  /// untouched and still fully work.
  void _startRoom(String uid, String name) {
    showSnackbar(context, "Voice rooms are coming in a future update.",
        Colors.blueGrey, Icons.mic_off);
  }

  /// ZegoCloud removal (2026-09-09, size/perf task) — same reasoning as
  /// `_startRoom`: no reason to prompt for a room code, look it up in
  /// Firestore, and only then refuse — the whole flow is removed, not left
  /// unreachable.
  void _joinByCode(String uid) {
    showSnackbar(context, "Voice rooms are coming in a future update.",
        Colors.blueGrey, Icons.mic_off);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`: no `PopScope`/`WillPopScope`
  /// at all before this fix, so a hardware back press with the keyboard
  /// open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check.
  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final name = _myName;
    final colors = context.folk;
    final text = context.folkText;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
          return;
        }
        Navigator.of(context).pop();
      },
      child: FolkScaffold(
        title: "RDUA Friends",
        actions: [
          RoundIconButton(
            icon: Icons.person_add_alt,
            semanticLabel: 'Find a friend',
            onPressed: uid == null ? null : _openSearch,
          ),
        ],
        // The three tabs as chips; they drive the same TabController the
        // swipeable TabBarView below uses.
        bottom: Padding(
          padding: const EdgeInsets.only(top: FolkSpace.lg),
          child: AnimatedBuilder(
            animation: _tabController.animation!,
            builder: (context, _) {
              final selectedIndex = _tabController.animation!.value.round();
              const labels = ["Friends", "Requests", "Groups"];
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: FolkSpace.pagePadding),
                child: Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                            right: i == labels.length - 1 ? 0 : FolkSpace.sm),
                        child: FolkChip(
                          label: labels[i],
                          selected: i == selectedIndex,
                          large: true,
                          onTap: () => _tabController.animateTo(i),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        floatingActionButton: uid == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Groups tab only. Previously a separate `Positioned`
                  // FAB inside `_groupsTab`'s own Stack, anchored to this
                  // SAME bottom-right corner — which is why it sat
                  // directly underneath "Start Voice Room" below and
                  // could not be reliably tapped. Folded into this
                  // existing stacked-FAB column (Rule 1: the app's own
                  // convention for two floating actions is already
                  // "stack vertically with a gap") instead of a second,
                  // independently-positioned button.
                  if (_tabController.index == 2) ...[
                    FloatingActionButton(
                      heroTag: 'new-group',
                      mini: true,
                      elevation: 0,
                      backgroundColor: colors.surface,
                      foregroundColor: colors.text,
                      onPressed: () => _createGroup(uid),
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton.extended(
                    heroTag: 'join-code',
                    elevation: 0,
                    backgroundColor: colors.surface,
                    foregroundColor: colors.text,
                    onPressed: () => _joinByCode(uid),
                    icon: const Icon(Icons.dialpad),
                    label: Text("Join by Code", style: text.chip),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'start-room',
                    elevation: 0,
                    backgroundColor: colors.primaryBg,
                    foregroundColor: colors.primaryFg,
                    onPressed: () => _startRoom(uid, name ?? 'Student'),
                    icon: const Icon(Icons.mic),
                    label: Text("Start Voice Room",
                        style: text.chip.copyWith(color: colors.primaryFg)),
                  ),
                ],
              ),
        body: uid == null
            ? GhostScope(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(FolkSpace.pagePadding),
                  children: [
                    for (var i = 0; i < 4; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: FolkSpace.cardGap),
                        child: GhostPlaceholder(
                          width: double.infinity,
                          height: 72,
                          radius: FolkShape.tileRadius,
                          showBars: false,
                        ),
                      ),
                  ],
                ),
              )
            : TabBarView(
                controller: _tabController,
                children: [
                  _friendsTab(uid),
                  _requestsTab(uid),
                  _groupsTab(uid),
                ],
              ),
      ),
    );
  }

  Widget _avatar() {
    final colors = context.folk;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceSecondary,
      ),
      child: Icon(Icons.person, color: colors.text),
    );
  }

  Widget _friendsTab(String uid) {
    final text = context.folkText;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _friendsStream,
      builder: (context, snap) {
        final docs = _sameGender(snap.data?.docs ?? []);
        if (docs.isEmpty) {
          return Center(
              child:
                  Text("No friends yet — tap + to search.", style: text.body));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(FolkSpace.pagePadding),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final f = docs[i].data();
            final role = (f['role'] ?? '').toString();
            final guideId = (f['guideId'] ?? '').toString();
            final ctx = [
              if (role.isNotEmpty) role,
              if (guideId.isNotEmpty) "$guideId's group",
            ].join(' · ');
            return FolkCard(
              margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
              radius: FolkShape.tileRadius,
              padding: const EdgeInsets.symmetric(
                  horizontal: FolkSpace.lg, vertical: 12),
              child: Row(
                children: [
                  _avatar(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((f['name'] ?? '').toString(),
                            style: text.bodyStrong),
                        if (ctx.isNotEmpty) Text(ctx, style: text.small),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _requestsTab(String uid) {
    final colors = context.folk;
    final text = context.folkText;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Single equality filter, both directions checked client-side after
      // the fact via two separate simple queries below — kept as two
      // StreamBuilders rather than one OR query for clarity here.
      stream: _requestsStream,
      builder: (context, incomingSnap) {
        // Only requests from students of my gender are shown.
        final incoming = (incomingSnap.data?.docs ?? [])
            .where((d) => d.data()['status'] == 'pending')
            .where((d) =>
                _directory?.sameByUid(d.data()['fromUid']?.toString()) ?? false)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(FolkSpace.pagePadding),
          children: [
            Text("Incoming".toUpperCase(), style: text.label),
            const SizedBox(height: 8),
            if (incoming.isEmpty) Text("No pending requests", style: text.body),
            ...incoming.map((d) {
              final data = d.data();
              return FolkCard(
                margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
                radius: FolkShape.tileRadius,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text((data['fromName'] ?? '').toString(),
                          style: text.bodyStrong),
                    ),
                    IconButton(
                      tooltip: 'Accept',
                      constraints: const BoxConstraints(
                          minWidth: FolkShape.touchTarget,
                          minHeight: FolkShape.touchTarget),
                      icon: const Icon(Icons.check,
                          color: FolkCalendarTokens.legendSubmitted),
                      onPressed: () => _respondToRequest(d.id, data, true),
                    ),
                    IconButton(
                      tooltip: 'Decline',
                      constraints: const BoxConstraints(
                          minWidth: FolkShape.touchTarget,
                          minHeight: FolkShape.touchTarget),
                      icon: Icon(Icons.close, color: colors.calendarMissedText),
                      onPressed: () => _respondToRequest(d.id, data, false),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _groupsTab(String uid) {
    final colors = context.folk;
    final text = context.folkText;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groupsStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
              child: Text("No groups yet — tap + to create one.",
                  style: text.body));
        }
        return ListView.builder(
          // Bottom padding cleared for this tab's own 3-button FAB stack
          // (+ New Group, Join by Code, Start Voice Room) — see build()'s
          // floatingActionButton.
          padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
              FolkSpace.pagePadding, FolkSpace.pagePadding, 190),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final g = docs[i].data();
            final members = ((g['memberUids'] as List?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    <String>[])
                .where((m) => _directory?.sameByUid(m) ?? false)
                .toList();
            return FolkCard(
              margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
              radius: FolkShape.tileRadius,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((g['groupName'] ?? '').toString(),
                            style: text.bodyStrong),
                        Text("${members.length} member(s)", style: text.small),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Manage members',
                    constraints: const BoxConstraints(
                        minWidth: FolkShape.touchTarget,
                        minHeight: FolkShape.touchTarget),
                    icon: Icon(Icons.group_add, color: colors.text),
                    onPressed: () =>
                        _manageGroupMembers(uid, docs[i].id, members),
                  ),
                  IconButton(
                    tooltip: 'Delete group',
                    constraints: const BoxConstraints(
                        minWidth: FolkShape.touchTarget,
                        minHeight: FolkShape.touchTarget),
                    icon: Icon(Icons.delete_outline,
                        color: colors.calendarMissedText),
                    onPressed: () => _firestore
                        .collection('friendGroups')
                        .doc(uid)
                        .collection('groups')
                        .doc(docs[i].id)
                        .delete(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/SeenMarkers.dart';
import '../utils/Snackbar.dart';

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
    if (!mounted) return;
    setState(() {
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
              final snap = await _firestore.collection('users').get();
              final matches = snap.docs
                  .where((d) {
                    if (d.id == uid) return false;
                    final name =
                        (d.data()['name'] ?? '').toString().toLowerCase();
                    return name.contains(trimmed);
                  })
                  .map((d) => {'uid': d.id, ...d.data()})
                  .toList();
              setSheetState(() {
                results = matches;
                searched = true;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height * .75,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Find a friend",
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 14),
                    TextField(
                      autofocus: true,
                      onChanged: runSearch,
                      decoration: InputDecoration(
                        hintText: "Search by name",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: !searched
                          ? const SizedBox()
                          : results.isEmpty
                              ? const Center(child: Text("No students found"))
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

                                    // This sheet's own outer Container has
                                    // `decoration: BoxDecoration(color:
                                    // Colors.white, ...)` with no Material
                                    // between it and this ListTile, which
                                    // triggers "ListTile background color
                                    // or ink splashes may be invisible"
                                    // (recurred three times in this
                                    // project already — same fix each
                                    // time).
                                    return Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor:
                                              Colors.deepPurple.shade50,
                                          child: Text(
                                            name.isNotEmpty
                                                ? name[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                color: Colors.deepPurple),
                                          ),
                                        ),
                                        title: Text(name),
                                        subtitle: context2.isEmpty
                                            ? null
                                            : Text(context2,
                                                style: const TextStyle(
                                                    fontSize: 12)),
                                        trailing: TextButton(
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
    final fromUid = (data['fromUid'] ?? '').toString();
    final fromName = (data['fromName'] ?? '').toString();
    final toUid = (data['toUid'] ?? '').toString();
    final toName = (data['toName'] ?? '').toString();

    try {
      if (!accept) {
        await _firestore.collection('friendRequests').doc(requestId).update({
          'status': 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Symmetric write, both sides, atomically (Part 2 item 2) — a batch
      // so either both friendship rows exist or neither does.
      final fromUserSnap =
          await _firestore.collection('users').doc(fromUid).get();
      final toUserSnap = await _firestore.collection('users').doc(toUid).get();

      final batch = _firestore.batch();
      batch.update(
        _firestore.collection('friendRequests').doc(requestId),
        {'status': 'accepted', 'respondedAt': FieldValue.serverTimestamp()},
      );
      batch.set(
        _firestore
            .collection('friends')
            .doc(toUid)
            .collection('list')
            .doc(fromUid),
        {
          'friendUid': fromUid,
          'name': fromName,
          'role': (fromUserSnap.data()?['role'] ?? '').toString(),
          'guideId': (fromUserSnap.data()?['guideId'] ?? '').toString(),
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      batch.set(
        _firestore
            .collection('friends')
            .doc(fromUid)
            .collection('list')
            .doc(toUid),
        {
          'friendUid': toUid,
          'name': toName,
          'role': (toUserSnap.data()?['role'] ?? '').toString(),
          'guideId': (toUserSnap.data()?['guideId'] ?? '').toString(),
          'addedAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
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
      builder: (dialogContext) => AlertDialog(
        title: const Text("New group"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Group name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text("Create"),
          ),
        ],
      ),
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
    final friendsSnap = await _firestore
        .collection('friends')
        .doc(uid)
        .collection('list')
        .get();
    final selected = Set<String>.from(currentMembers);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Group members",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (friendsSnap.docs.isEmpty)
                    const Text("You have no friends to add yet."),
                  ...friendsSnap.docs.map((d) {
                    final friendUid = d.id;
                    final name = (d.data()['name'] ?? '').toString();
                    return CheckboxListTile(
                      value: selected.contains(friendUid),
                      title: Text(name),
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
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
                      child: const Text("Save"),
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

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
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
          child: Scaffold(
            backgroundColor: colorProvider.color,
            appBar: AppBar(
              backgroundColor: colorProvider.color,
              elevation: 0,
              iconTheme: IconThemeData(color: colorProvider.secondColor),
              title: Text("RDUA Friends",
                  style: TextStyle(
                      color: colorProvider.secondColor,
                      fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: Icon(Icons.person_add_alt,
                      color: colorProvider.secondColor),
                  onPressed: uid == null ? null : _openSearch,
                ),
              ],
              bottom: TabBar(
                controller: _tabController,
                labelColor: Colors.deepPurple,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.deepPurple,
                tabs: const [
                  Tab(text: "Friends"),
                  Tab(text: "Requests"),
                  Tab(text: "Groups"),
                ],
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
                          onPressed: () => _createGroup(uid),
                          child: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FloatingActionButton.extended(
                        heroTag: 'join-code',
                        backgroundColor: Colors.blueGrey,
                        onPressed: () => _joinByCode(uid),
                        icon: const Icon(Icons.dialpad),
                        label: const Text("Join by Code"),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton.extended(
                        heroTag: 'start-room',
                        backgroundColor: Colors.green.shade700,
                        onPressed: () => _startRoom(uid, name ?? 'Student'),
                        icon: const Icon(Icons.mic),
                        label: const Text("Start Voice Room"),
                      ),
                    ],
                  ),
            body: uid == null
                ? const Center(child: CircularProgressIndicator())
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
      },
    );
  }

  Widget _friendsTab(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _friendsStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text("No friends yet — tap + to search."));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final f = docs[i].data();
            final role = (f['role'] ?? '').toString();
            final guideId = (f['guideId'] ?? '').toString();
            final ctx = [
              if (role.isNotEmpty) role,
              if (guideId.isNotEmpty) "$guideId's group",
            ].join(' · ');
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text((f['name'] ?? '').toString()),
                subtitle: ctx.isEmpty ? null : Text(ctx),
              ),
            );
          },
        );
      },
    );
  }

  Widget _requestsTab(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Single equality filter, both directions checked client-side after
      // the fact via two separate simple queries below — kept as two
      // StreamBuilders rather than one OR query for clarity here.
      stream: _requestsStream,
      builder: (context, incomingSnap) {
        final incoming = (incomingSnap.data?.docs ?? [])
            .where((d) => d.data()['status'] == 'pending')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text("Incoming",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            if (incoming.isEmpty) const Text("No pending requests"),
            ...incoming.map((d) {
              final data = d.data();
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text((data['fromName'] ?? '').toString()),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => _respondToRequest(d.id, data, true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _respondToRequest(d.id, data, false),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _groupsTab(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _groupsStream,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
              child: Text("No groups yet — tap + to create one."));
        }
        return ListView.builder(
          // Bottom padding cleared for this tab's own 3-button FAB stack
          // (+ New Group, Join by Code, Start Voice Room) — see build()'s
          // floatingActionButton.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 190),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final g = docs[i].data();
            final members =
                (g['memberUids'] as List?)?.map((e) => e.toString()).toList() ??
                    [];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text((g['groupName'] ?? '').toString()),
                subtitle: Text("${members.length} member(s)"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.group_add),
                      onPressed: () =>
                          _manageGroupMembers(uid, docs[i].id, members),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _firestore
                          .collection('friendGroups')
                          .doc(uid)
                          .collection('groups')
                          .doc(docs[i].id)
                          .delete(),
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
}

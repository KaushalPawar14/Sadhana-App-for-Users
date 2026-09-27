import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';

/// Which notifications this student wants to receive.
///
/// Writes to `users/{uid}.notificationPrefs` — a map of
/// `{notificationType: bool}` on the student's own user document, chosen over a
/// subcollection because it is five booleans on a document this app already
/// reads, so it costs no extra query.
///
/// ⚠️ **Absent means ON, everywhere.** Every check — here and in all five send
/// paths — is written `!= false`, never `== true`. Every student who predates
/// this screen has no `notificationPrefs` field at all, and an `== true` test
/// would silently unsubscribe the entire cohort the moment this shipped. A
/// toggle only ever *appears* off when the field is explicitly `false`.
///
/// ⚠️ **Turning something off here genuinely stops it.** The switches are not
/// cosmetic: the 08:00 and 11:00 Cloud Functions and the three guide-triggered
/// sends all read this map before sending. That is why the copy avoids
/// promising anything about "important" notifications still arriving — none of
/// these are exempt.
///
/// Saves immediately on toggle, with no Save button, matching this app's
/// existing preference behaviour (`ColorProvider.toggleColor()` and the switch
/// in `BookPageList`, both of which persist on change).
class NotificationPreferencesPage extends StatefulWidget {
  final String uid;

  const NotificationPreferencesPage({super.key, required this.uid});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

/// One row on this screen. `key` is the exact Firestore field name.
class _PrefItem {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;

  const _PrefItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

/// Every student-facing notification this system sends, as found by a full
/// grep of both apps and `functions/` — not from memory.
///
/// If a new student-facing notification is ever added, it belongs here too,
/// otherwise students get something they cannot turn off.
const List<_PrefItem> _kPrefs = [
  _PrefItem(
    key: 'sadhanaReminderMorning',
    title: 'Morning sadhana reminder',
    subtitle: 'At 8:00 am, if your report for the day is not filled yet',
    icon: Icons.wb_twilight,
  ),
  _PrefItem(
    key: 'sadhanaReminderMidday',
    title: 'Midday sadhana reminder',
    subtitle: 'At 11:00 am, a second nudge if it is still pending',
    icon: Icons.wb_sunny_outlined,
  ),
  _PrefItem(
    key: 'associationUpdates',
    title: 'Meeting updates',
    subtitle: 'When your guide confirms, changes or cancels a meeting',
    icon: Icons.groups_outlined,
  ),
  _PrefItem(
    key: 'chantingChallenge',
    title: 'Chanting challenges',
    subtitle: 'When your guide sets a new group chanting target',
    icon: Icons.self_improvement,
  ),
  _PrefItem(
    key: 'guideManualReminder',
    title: 'Reminders from your guide',
    subtitle: 'When your guide personally nudges you about a report',
    icon: Icons.notifications_active_outlined,
  ),
];

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  /// Keys currently being written, so a row can show progress and ignore a
  /// second tap mid-write.
  final Set<String> _saving = <String>{};

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(widget.uid);

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) —
  /// `_userRef.snapshots()` used to be called fresh directly in `build()`.
  /// `_userRef` itself stays a getter (it's also used for one-off writes,
  /// where recomputing it costs nothing — no network call, just a local
  /// reference object); only the STREAM built once from it is hoisted,
  /// built in `initState()` since `widget.uid` is fixed for this screen's
  /// whole life.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();
    _userStream = _userRef.snapshots();
  }

  /// Absent or true both mean ON. See the class doc for why this is never
  /// written as `== true`.
  bool _isOn(Map<String, dynamic>? data, String key) {
    final prefs = data?['notificationPrefs'];
    if (prefs is! Map) return true;
    return prefs[key] != false;
  }

  Future<void> _set(String key, bool value) async {
    setState(() => _saving.add(key));

    try {
      // Dotted field path so only this one key is written — a whole-map write
      // would clobber a key added by a newer app version.
      await _userRef.set(
        {
          'notificationPrefs': {key: value},
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Could not save that just now"),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text(
              "Notifications",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
          ),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            // Live, so the switches reflect the stored value rather than local
            // state that could drift from Firestore.
            stream: _userStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final data = snapshot.data?.data();

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      "Choose what you would like to be notified about. "
                      "Everything is on to begin with — turning something off "
                      "stops it completely, so you will not hear about it at "
                      "all until you turn it back on.",
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: colorProvider.secondColor.withOpacity(.8),
                      ),
                    ),
                  ),
                  ..._kPrefs.map((item) {
                    final on = _isOn(data, item.key);
                    final busy = _saving.contains(item.key);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      // ⚠️ `Material` between the decorated Container and the
                      // tile (added 2026-08-19). A `ListTile` paints its ink
                      // splash onto the nearest `Material` ancestor. With only
                      // this Container's `DecoratedBox` in between, the nearest
                      // one was the Scaffold — *behind* the white fill — so
                      // every tap's splash was drawn underneath an opaque
                      // surface and never seen. Flutter logs exactly that
                      // ("ListTile background color or ink splashes may be
                      // invisible").
                      //
                      // `Colors.transparent` deliberately: an opaque Material
                      // would paint its own square background over the
                      // Container's 16px rounded corners. The same fix and the
                      // same reasoning as `DevotionalServiceManager` in the
                      // Guide app.
                      //
                      // Purely a feedback fix — the fill, border, radius,
                      // margin and contentPadding are all untouched, so the row
                      // looks identical.
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: SwitchListTile(
                          value: on,
                        // Ignore a tap already in flight for this key.
                        onChanged:
                            busy ? null : (next) => _set(item.key, next),
                        activeColor: Colors.green.shade600,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        title: Row(
                          children: [
                            Icon(item.icon,
                                size: 18, color: Colors.grey.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (busy)
                              const SizedBox(
                                width: 13,
                                height: 13,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            item.subtitle,
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.grey.shade600),
                          ),
                        ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

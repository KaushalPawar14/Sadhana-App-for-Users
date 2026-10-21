import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

// MY MUSIC - the curriculum and the student's progress.
//
// TWO ADDITIVE COLLECTIONS (justified):
//  - `musicCurriculum/{instrumentId}`: the instruments and their checkpoints, ONE document per instrument (name, optional
//    YouTube link, order, and its ordered checkpoints as {id, title}). The HODs and Guides edit it in the Guide app and
//    both apps read it live, so it cannot be a constant in the apps. Every instrument and every checkpoint has a STABLE id.
//  - `musicProgress/{uid}`: ONE document per student: `ticks` (checkpoint id -> who ticked it and when) and `others` (the
//    instruments the student added themselves). Progress is kept BY CHECKPOINT ID, never by position or name, so renaming
//    or reordering keeps everyone's ticks, a deleted checkpoint simply stops counting (its tick stays in storage, unseen),
//    and a newly added checkpoint makes a completed instrument incomplete again until it is ticked. The student and any
//    admin who can see the student (the usual scope rules) may tick and untick: no approval.

class MusicCheckpoint {
  const MusicCheckpoint({required this.id, required this.title});

  final String id;
  final String title;
}

class MusicInstrument {
  const MusicInstrument({required this.id, required this.name, this.link = '', this.order = 0, this.checkpoints = const []});

  final String id;
  final String name;

  /// A YouTube link, or '' when there is none.
  final String link;
  final int order;
  final List<MusicCheckpoint> checkpoints;

  bool get hasLink => link.trim().isNotEmpty;

  static MusicInstrument? fromDoc(String id, Map<String, dynamic>? d) {
    if (d == null) return null;
    final name = (d['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final raw = d['checkpoints'];
    final cps = <MusicCheckpoint>[
      if (raw is List)
        for (final c in raw)
          if (c is Map && (c['id'] ?? '').toString().isNotEmpty && (c['title'] ?? '').toString().trim().isNotEmpty)
            MusicCheckpoint(id: c['id'].toString(), title: c['title'].toString().trim()),
    ];
    final order = d['order'];
    return MusicInstrument(
      id: id,
      name: name,
      link: (d['link'] ?? '').toString().trim(),
      order: order is num ? order.toInt() : 0,
      checkpoints: cps,
    );
  }

  Map<String, Object?> toMap() => {
        'name': name,
        'link': link,
        'order': order,
        'checkpoints': [for (final c in checkpoints) {'id': c.id, 'title': c.title}],
      };
}

/// Who ticked a checkpoint and when ("student" = the student themselves, otherwise an admin's id).
class MusicTick {
  const MusicTick({required this.by, required this.byName, this.at});

  final String by;
  final String byName;
  final DateTime? at;

  bool get byStudent => by == 'student';
}

enum MusicLevel { basic, intermediate, expert }

extension MusicLevelX on MusicLevel {
  String get label => switch (this) { MusicLevel.basic => 'Basic', MusicLevel.intermediate => 'Intermediate', MusicLevel.expert => 'Expert' };
  String get key => name;
  static MusicLevel fromKey(Object? k) => MusicLevel.values.firstWhere((l) => l.name == k, orElse: () => MusicLevel.basic);
}

/// An instrument the student added themselves ("Others").
class OtherInstrument {
  const OtherInstrument({required this.id, required this.name, required this.level});

  final String id;
  final String name;
  final MusicLevel level;

  OtherInstrument copyWith({String? name, MusicLevel? level}) => OtherInstrument(id: id, name: name ?? this.name, level: level ?? this.level);

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'level': level.key};
}

class MusicProgress {
  const MusicProgress({this.ticks = const {}, this.others = const []});

  /// Checkpoint id -> who ticked it and when.
  final Map<String, MusicTick> ticks;
  final List<OtherInstrument> others;

  static const MusicProgress empty = MusicProgress();

  /// How many of [instrument]'s CURRENT checkpoints are ticked (a tick of a deleted checkpoint does not count).
  int done(MusicInstrument instrument) => instrument.checkpoints.where((c) => ticks.containsKey(c.id)).length;

  /// Completed = it has checkpoints and every one of them is ticked. Unticking one removes it; adding a checkpoint
  /// makes a completed instrument incomplete again.
  bool completed(MusicInstrument instrument) => instrument.checkpoints.isNotEmpty && done(instrument) == instrument.checkpoints.length;

  static MusicProgress fromDoc(Map<String, dynamic>? d) {
    if (d == null) return empty;
    final ticks = <String, MusicTick>{};
    final rawTicks = d['ticks'];
    if (rawTicks is Map) {
      rawTicks.forEach((k, v) {
        if (v is! Map) return;
        final at = v['at'];
        ticks[k.toString()] = MusicTick(
          by: (v['by'] ?? 'student').toString(),
          byName: (v['byName'] ?? '').toString(),
          at: at is Timestamp ? at.toDate() : null,
        );
      });
    }
    final others = <OtherInstrument>[];
    final rawOthers = d['others'];
    if (rawOthers is List) {
      for (final o in rawOthers) {
        if (o is Map && (o['id'] ?? '').toString().isNotEmpty && (o['name'] ?? '').toString().trim().isNotEmpty) {
          others.add(OtherInstrument(id: o['id'].toString(), name: o['name'].toString().trim(), level: MusicLevelX.fromKey(o['level'])));
        }
      }
    }
    return MusicProgress(ticks: ticks, others: others);
  }
}

/// A new stable id (`prefix` + time + random), for an instrument or checkpoint added later.
String newMusicId(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

/// Where the curriculum and the progress live. The apps use [FirestoreMusicStore]; tests hand in a fake.
abstract class MusicStore {
  /// The instruments, in the HODs' order, live.
  Stream<List<MusicInstrument>> curriculum();

  /// One student's progress, live (empty until they tick something).
  Stream<MusicProgress> progress(String uid);

  /// Ticks / unticks a checkpoint. [by] is "student" or the admin's id; [byName] is shown subtly next to the tick.
  Future<void> setTick(String uid, String checkpointId, bool ticked, {required String by, required String byName});

  /// Replaces the student's own "Others" list.
  Future<void> saveOthers(String uid, List<OtherInstrument> others);
}

class FirestoreMusicStore implements MusicStore {
  FirestoreMusicStore([FirebaseFirestore? firestore]) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Stream<List<MusicInstrument>> curriculum() => _db.collection('musicCurriculum').snapshots().map((snap) {
        final list = [
          for (final d in snap.docs)
            if (MusicInstrument.fromDoc(d.id, d.data()) case final i?) i,
        ];
        list.sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return list;
      });

  @override
  Stream<MusicProgress> progress(String uid) => _db.collection('musicProgress').doc(uid).snapshots().map((s) => MusicProgress.fromDoc(s.data()));

  @override
  Future<void> setTick(String uid, String checkpointId, bool ticked, {required String by, required String byName}) async {
    final ref = _db.collection('musicProgress').doc(uid);
    if (ticked) {
      await ref.set({
        'uid': uid,
        'ticks': {
          checkpointId: {'by': by, 'byName': byName, 'at': FieldValue.serverTimestamp()},
        },
      }, SetOptions(merge: true));
    } else {
      try {
        await ref.update({'ticks.$checkpointId': FieldValue.delete()});
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow; // nothing was ticked yet: nothing to remove
      }
    }
  }

  @override
  Future<void> saveOthers(String uid, List<OtherInstrument> others) => _db.collection('musicProgress').doc(uid).set({
        'uid': uid,
        'others': [for (final o in others) o.toMap()],
      }, SetOptions(merge: true));
}

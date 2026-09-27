import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds a new student's `users/{uid}/questions/{level}` docs the first
/// time they sign in. Extracted out of `services/AccessToken.dart` (task:
/// "Remove the embedded service-account key from the Student app") — this
/// content was unrelated to that file's actual subject (minting an FCM
/// access token from a bundled service-account key) and needed a home of
/// its own once that file was deleted.
final Map<String, List<String>> questionLevels = {
  "level-1": [
    "Who am I?",
    "Does God exist?",
    "GOD Vs. Demigods & Definition of GOD",
    "Yugadharma for Kaliyuga",
    "Laws of Karma",
  ],
  "level-2": [
    "Importance of Vedic Literatures",
    "3 modes of material Nature",
    "Reincarnation",
    "Material world Vs. Spiritual world",
    "4 regulative Principles",
  ],
  "level-3": [
    "Energies of Lord Krishna",
    "Incarnations of Lord Krishna",
    "Glories of devotional service",
    "Purpose of Human form of Life",
    "Importance of accepting a Spiritual Master",
  ],
  "level-4": [
    "3 features of Absolute Truth",
    "Deity Worship or Idol Worship",
    "Why so many religions in different parts of the World",
    "Glories of Visiting Lord's Dhams",
    "Glories of Vaishnava association",
  ],
  "level-5": [
    "Importance of ekadashi and observing fasting on acharyas appearance etc",
    "Pranam Mantras of Deities",
    "Vaishnava etiquettes",
    "Different kinds of Liberation",
    "Different kinds of mellows of relationship with the Lord",
    "Glories of Preaching Krishna consciousness to others",
  ]
};

Future<void> initializeQuestionsIfNeeded(String uid) async {

  final baseRef = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('questions');

  final checkDoc = await baseRef.doc("level-1").get();

  // If level-1 does not exist, create everything
  if (!checkDoc.exists) {

    for (var level in questionLevels.entries) {

      Map<String, dynamic> data = {};

      for (int i = 0; i < level.value.length; i++) {
        data['q${i + 1}'] = {
          "question": level.value[i],
          "completed": false,
        };
      }

      await baseRef.doc(level.key).set(data);
    }

    print("Questions initialized for $uid");
  }
}

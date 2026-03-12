class Scorecard {
  int totalChantRounds;
  int totalBookRead;
  int totalSBClass;
  int totalServiceDone;

  Scorecard({
    required this.totalChantRounds,
    required this.totalBookRead,
    required this.totalSBClass,
    required this.totalServiceDone,
  });

  // Factory method to create a Scorecard object from a Firestore document snapshot
  factory Scorecard.fromFirestore(Map<String, dynamic> data) {
    return Scorecard(
      totalChantRounds: data['totalChantRounds'] ?? 0,
      totalBookRead: data['totalBookRead'] ?? 0,
      totalSBClass: data['totalSBClass'] ?? 0,
      totalServiceDone: data['totalServiceDone'] ?? 0,
    );
  }

  // Method to convert a Scorecard object to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'totalChantRounds': totalChantRounds,
      'totalBookRead': totalBookRead,
      'totalSBClass': totalSBClass,
      'totalServiceDone': totalServiceDone,
    };
  }
}

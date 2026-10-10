// CompetitionResults.dart


// ------------------- MODELS -------------------

class UserCompetitionResult {
  final String name;
  final double totalScore;
  final double bhagavatam;
  final double dailyService;
  final double chantingRounds;
  final double bookReading;
  final double extraLecture;
  final double templeMultiplier;
  final double japaMultiplier;
  final double sleepingMultiplier;

  UserCompetitionResult({
    required this.name,
    required this.totalScore,
    required this.bhagavatam,
    required this.dailyService,
    required this.chantingRounds,
    required this.bookReading,
    required this.extraLecture,
    required this.templeMultiplier,
    required this.japaMultiplier,
    required this.sleepingMultiplier,
  });

  Map<String, dynamic> toMap() => {
    "name": name,
    "total_score": totalScore,
    "bhagavatam": bhagavatam,
    "daily_service": dailyService,
    "chanting_rounds": chantingRounds,
    "book_reading": bookReading,
    "extra_lecture": extraLecture,
    "temple_multiplier": templeMultiplier,
    "japa_multiplier": japaMultiplier,
    "sleeping_multiplier": sleepingMultiplier,
  };

  factory UserCompetitionResult.fromMap(Map<String, dynamic> map) =>
      UserCompetitionResult(
        name: map['name'],
        totalScore: map['total_score'],
        bhagavatam: map['bhagavatam'],
        dailyService: map['daily_service'],
        chantingRounds: map['chanting_rounds'],
        bookReading: map['book_reading'],
        extraLecture: map['extra_lecture'],
        templeMultiplier: map['temple_multiplier'],
        japaMultiplier: map['japa_multiplier'],
        sleepingMultiplier: map['sleeping_multiplier'],
      );
}

class WeeklyResults {
  final String weekId; // YYYY-WW
  final List<UserCompetitionResult> topUsers;
  final DateTime generatedAt;

  // The top three of EACH gender (additive fields: `topUsers` above stays as it
  // always was). A student is shown the winners of their own gender only.
  final List<UserCompetitionResult>? topUsersMale;
  final List<UserCompetitionResult>? topUsersFemale;

  WeeklyResults({
    required this.weekId,
    required this.topUsers,
    required this.generatedAt,
    this.topUsersMale,
    this.topUsersFemale,
  });

  Map<String, dynamic> toMap() => {
    "topUsers": topUsers.map((u) => u.toMap()).toList(),
    if (topUsersMale != null)
      "topUsersMale": topUsersMale!.map((u) => u.toMap()).toList(),
    if (topUsersFemale != null)
      "topUsersFemale": topUsersFemale!.map((u) => u.toMap()).toList(),
    "generatedAt": generatedAt.toIso8601String(),
  };
}

class MonthlyResults {
  final String monthId; // YYYY-MM
  final List<UserCompetitionResult> topUsers;
  final DateTime generatedAt;

  // The top three of EACH gender (additive fields: `topUsers` above stays as it
  // always was). A student is shown the winners of their own gender only.
  final List<UserCompetitionResult>? topUsersMale;
  final List<UserCompetitionResult>? topUsersFemale;

  MonthlyResults({
    required this.monthId,
    required this.topUsers,
    required this.generatedAt,
    this.topUsersMale,
    this.topUsersFemale,
  });

  Map<String, dynamic> toMap() => {
    "topUsers": topUsers.map((u) => u.toMap()).toList(),
    if (topUsersMale != null)
      "topUsersMale": topUsersMale!.map((u) => u.toMap()).toList(),
    if (topUsersFemale != null)
      "topUsersFemale": topUsersFemale!.map((u) => u.toMap()).toList(),
    "generatedAt": generatedAt.toIso8601String(),
  };
}

// ------------------- FINALISATION IS SERVER-SIDE -------------------
// Weekly / monthly finalisation (top three per gender, badges, results docs, the
// reset of the weekly / monthly scores) used to run here, on whichever student's
// phone opened the app first. It now runs on the server (functions/
// competitionFinalize.js, Sunday 00:05 / 1st 00:10 IST) using the same marker
// documents, so the app only ever READS the results.

// Who gets the weekly winner badge: the best student of each gender, if they
// scored anything at all.
List<String> weeklyWinnerNames(Map<String, List<UserCompetitionResult>> byGender) => [
      for (final list in byGender.values)
        if (list.isNotEmpty && list.first.totalScore != 0) list.first.name,
    ];

// Who gets which monthly badge: for each gender, the top three in order (gold,
// silver, bronze), skipped altogether when that gender's best scored nothing.
List<({String name, String field})> monthlyBadgeAwards(
    Map<String, List<UserCompetitionResult>> byGender) {
  const fields = ["monthly-gold", "monthly-silver", "monthly-bronze"];
  return [
    for (final list in byGender.values)
      if (list.isNotEmpty && list.first.totalScore != 0)
        for (var i = 0; i < list.length && i < 3; i++)
          (name: list[i].name, field: fields[i]),
  ];
}

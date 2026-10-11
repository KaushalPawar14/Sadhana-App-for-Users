import '../theme/FolkTokens.dart';

// The four starter questions shown when today's chat is empty: one per category the
// assistant answers, each with its colour. Each category has a pool of eight questions and
// shows a different one each day, so the set is never the same two days running.

class StarterCategory {
  const StarterCategory({
    required this.label,
    required this.style,
    required this.dayOffset,
    required this.questions,
  });

  // The small label on the card ("Spiritual question").
  final String label;
  final FolkGradientStyle style;

  // Spreads the four categories over the pool, so their rotations are not in step.
  final int dayOffset;
  final List<String> questions;
}

// The grid order is row by row: purple, orange / green, pink. Purple is top-left and
// pink bottom-right (a diagonal, never side by side or one above the other); stacked
// (large text), the same order keeps purple first and pink last.
const List<StarterCategory> kStarterCategories = [
  StarterCategory(
    label: 'Spiritual question',
    style: FolkGradientStyle.violet, // PURPLE
    dayOffset: 0,
    questions: [
      "Who am I if I'm not this body? What does Prabhupada say?",
      'Why is chanting Hare Krishna so important?',
      'What is karma, and how can I become free from it?',
      'What is the purpose of human life, according to Prabhupada?',
      'Why does a loving God allow suffering in the world?',
      'What is the difference between the soul and the mind?',
      "How should I understand the Gita's message of surrendering to Krishna?",
      'Why do we offer our food to Krishna before we eat it?',
    ],
  ),
  StarterCategory(
    label: 'How the app works',
    style: FolkGradientStyle.saffron, // ORANGE
    dayOffset: 3,
    questions: [
      'How do I mark a book as already completed?',
      'Where can I see my leaderboard and my weekly results?',
      'How do I set my chanting commitment in Profile?',
      'How does the japa counter work?',
      'How do I submit my sadhana for a day I missed?',
      'Where can I read my daily message and my earlier chats?',
      'How do I turn notifications on or off?',
      "How do I find my guide's name in the app?",
    ],
  ),
  StarterCategory(
    label: 'Daily practice',
    style: FolkGradientStyle.green, // GREEN
    dayOffset: 5,
    questions: [
      'How can I chant my 16 rounds with more attention?',
      'How do I stay steady in my practice during exams?',
      'I find it hard to wake up early for mangala arati. Any tips?',
      'How do I stop my mind wandering while I chant?',
      "How can I read Prabhupada's books regularly even when I'm busy?",
      'What is a good daily routine for a college student in Krishna consciousness?',
      'How can I finish my japa earlier in the day?',
      'How do I hear the Bhagavatam class with real attention?',
    ],
  ),
  StarterCategory(
    label: 'How am I doing',
    style: FolkGradientStyle.coral, // PINK
    dayOffset: 1,
    questions: [
      'How am I doing compared to others in my group? What should I improve?',
      'Am I improving in my sadhana lately?',
      'Did I keep my chanting promise this week?',
      'How is my streak, and which days did I miss?',
      'Where do I stand in my group for reading and chanting?',
      'What is the one thing I should work on this week?',
      'How was my sadhana yesterday compared to my usual?',
      'Be honest: am I being consistent, and what should I do next?',
    ],
  ),
];

// The calendar day as a whole number (days since 1970), from the LOCAL date.
int _dayNumber(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ 86400000;

// The question each category shows on [day]: the next one in its pool every day.
List<String> startersForDay(DateTime day) {
  final n = _dayNumber(day);
  return [
    for (final c in kStarterCategories)
      c.questions[(n + c.dayOffset) % c.questions.length],
  ];
}

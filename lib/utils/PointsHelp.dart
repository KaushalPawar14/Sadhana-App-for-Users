import 'Commitments.dart';
import 'DayScore.dart';
import 'FormPoints.dart';

/// The words of one "i" help sheet: a title, short paragraphs, and a small table of examples / tiers.
class PointsHelp {
  const PointsHelp({required this.title, required this.paragraphs, this.rows = const [], this.footer});

  final String title;
  final List<String> paragraphs;

  /// (left, right) pairs: "16 rounds" -> "50 pts", "By 5:35 AM" -> "×1.5".
  final List<(String, String)> rows;
  final String? footer;
}

String _pts(double p) => '${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(1)} pts';

String _footerFor(ReportForm form) => form == ReportForm.folk
    ? 'Your day = all the points added × your temple × sleep × japa multipliers.'
    : 'Your day = all the points added × your wake-up × sleep × japa multipliers.';

/// The help of a scoring question, in plain words, with examples from the student's own commitments and the real tier
/// tables of their category. [topic] null = how the total works.
PointsHelp pointsHelp(PointsTopic? topic, ReportForm form, Commitments commitments) {
  final folk = form == ReportForm.folk;
  final chantC = commitments.rounds > 0 ? commitments.rounds : kDefaultChantCommitment;
  final readC = commitments.readingMinutes ?? 0;

  PointsHelp tiers(String title, String intro, ScoreTier tier, {String? note}) => PointsHelp(
        title: title,
        paragraphs: [intro, if (note != null) note],
        rows: [
          for (final r in tierRows(tier)) ('By ${clockText(r.limit)}', multiplierText(r.multiplier)),
          ('Later, or not entered', multiplierText(1.0)),
        ],
        footer: _footerFor(form),
      );

  if (topic == null) {
    return PointsHelp(
      title: "How today's points add up",
      paragraphs: [
        folk
            ? 'Add the points of the Bhagavatam class, daily services, chanting, reading and the extra lecture.'
            : 'Add the points of the Bhagavatam class, chanting and reading.',
        folk ? 'Then multiply by your temple, sleep and japa multipliers.' : 'Then multiply by your wake-up, sleep and japa multipliers.',
        'Example: 150 points × 1.5 × 1.25 × 1.0 = 281 points.',
      ],
      footer: 'The number shown is what this day earns if you submit it now. A time you have not entered yet counts as ×1.0.',
    );
  }

  switch (topic) {
    case PointsTopic.chanting:
      final half = (chantC / 2).ceil();
      return PointsHelp(
        title: 'Chanting points',
        paragraphs: [
          'Points = 50 × (rounds you chanted ÷ your daily commitment).',
          commitments.roundsSet
              ? 'Your commitment is $chantC rounds a day.'
              : 'You have not set your commitment yet, so the standard $chantC rounds is used until you set yours in My Commitments.',
          'There is no upper limit: chanting more earns more.',
        ],
        rows: [for (final n in [chantC, half, chantC * 2]) ('$n rounds', _pts(chantingPoints(n, chantC)))],
        footer: _footerFor(form),
      );
    case PointsTopic.reading:
      if (readC > 0) {
        final half = (readC / 2).ceil();
        return PointsHelp(
          title: 'Reading points',
          paragraphs: [
            'Points = 50 × (minutes you read ÷ your daily reading commitment).',
            'Your commitment is $readC minutes a day.',
            'There is no upper limit: reading more earns more.',
          ],
          rows: [for (final n in [readC, half, readC * 2]) ('$n minutes', _pts(readingPoints(n, readC)))],
          footer: _footerFor(form),
        );
      }
      return PointsHelp(
        title: 'Reading points',
        paragraphs: [
          'Your reading commitment is 0 (you are just beginning), so any reading that day earns a flat 50 points, and no reading earns 0.',
          commitments.readingSet ? 'You can raise your commitment any time in My Commitments.' : 'You have not set a reading commitment yet, so this rule is used until you do.',
        ],
        rows: const [('Any reading', '50 pts'), ('No reading', '0 pts')],
        footer: _footerFor(form),
      );
    case PointsTopic.sbClass:
      return PointsHelp(
        title: 'Bhagavatam class points',
        paragraphs: ['How much of the class you heard.'],
        rows: const [('Fully', '50 pts'), ('Partial', '25 pts'), ('Missed', '0 pts')],
        footer: _footerFor(form),
      );
    case PointsTopic.services:
      return PointsHelp(
        title: 'Daily services points',
        paragraphs: ['How much of your assigned services you did.'],
        rows: const [('Done fully', '50 pts'), ('Done partially', '25 pts'), ('Not done', '0 pts')],
        footer: _footerFor(form),
      );
    case PointsTopic.extraLecture:
      return PointsHelp(
        title: 'Extra lecture points',
        paragraphs: ['Listening to an extra lecture earns points by how long you heard.'],
        rows: const [('More than 30 minutes', '50 pts'), ('More than 15 minutes', '25 pts'), ('No', '0 pts')],
        footer: _footerFor(form),
      );
    case PointsTopic.temple:
      return tiers('Temple entry multiplier', 'Your points of the day are multiplied by this for the time you entered the temple hall. The earlier, the higher.', ScoreTier.temple);
    case PointsTopic.wakeup:
      return tiers('Wake-up multiplier', 'Your points of the day are multiplied by this for the time you woke up. The earlier, the higher.', ScoreTier.wakeup);
    case PointsTopic.sleep:
      return tiers('Sleep multiplier', 'Your points of the day are multiplied by this for the time you went to sleep. The earlier, the higher.',
          folk ? ScoreTier.sleepFolk : ScoreTier.sleepHostel,
          note: 'A time after midnight is saved as 11:59 PM, so it is ×1.0.');
    case PointsTopic.japa:
      return tiers('Japa finish multiplier', 'Your points of the day are multiplied by this for the time you finished your japa. The earlier, the higher.', ScoreTier.japa);
  }
}

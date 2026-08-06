import 'package:flutter/material.dart';
import 'package:folk_app/HostelersPage/Sadhana.dart';
import 'package:folk_app/pages/Competition.dart';
import 'package:folk_app/pages/Questions.dart';
import 'package:folk_app/pages/RduaSession.dart';
import 'package:folk_app/pages/JapaCounter.dart';
import 'package:folk_app/pages/GuidanceChat.dart';

class TodayJourneyPage extends StatelessWidget {
  const TodayJourneyPage({
    super.key,
    required this.role,
    required this.userName,
  });

  final String role;
  final String userName;

  bool get _isHosteller => role == 'Stay at Hostel';

  void _openSadhana(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isHosteller ? SadhanaPage() : QuestionsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = userName.trim().isEmpty
        ? 'friend'
        : userName.trim().split(RegExp(r'\s+')).first;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5EF),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hare Krishna, $firstName',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF183C2B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'One meaningful step is enough for today.',
                        style: TextStyle(
                          color: Color(0xFF65736B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                CircleAvatar(
                  radius: 23,
                  backgroundColor: const Color(0xFFDCEADE),
                  child: Text(
                    firstName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF24563D),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SadhanaCard(onOpen: () => _openSadhana(context)),
            const SizedBox(height: 14),
            _RduaCard(
              onContinue: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RduaSessionPage()),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Continue your journey',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF183C2B),
              ),
            ),
            const SizedBox(height: 12),
            const _JourneyAction(
              icon: Icons.menu_book_rounded,
              title: 'Perfect Questions, Perfect Answers',
              detail: 'Continue from Chapter 3 · about 8 minutes',
              action: 'Read',
              color: Color(0xFF315F45),
            ),
            const _JourneyAction(
              icon: Icons.graphic_eq_rounded,
              title: 'Your assigned hearing',
              detail: 'FOLK–2 · Topic 3 · 7 minutes left',
              action: 'Listen',
              color: Color(0xFF805A24),
            ),
            _JourneyAction(
              icon: Icons.self_improvement_rounded,
              title: 'Chant one round now',
              detail: '108-count mode with gentle vibration',
              action: 'Start',
              color: const Color(0xFF6E4E8B),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JapaCounterPage()),
              ),
            ),
            _JourneyAction(
              icon: Icons.forum_outlined,
              title: 'Understand from the teachings',
              detail: 'Grounded principle guidance · guide-aware',
              action: 'Ask',
              color: const Color(0xFF4F5FA8),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuidanceChatPage()),
              ),
            ),
            _JourneyAction(
              icon: Icons.people_alt_outlined,
              title: 'Speak with your FOLK guide',
              detail: 'Request a suitable personal-association time',
              action: 'Request',
              color: const Color(0xFF346D79),
              onTap: () => _showAssociationRequest(context),
            ),
            _JourneyAction(
              icon: Icons.emoji_events_outlined,
              title: 'Janmāṣṭamī hearing challenge',
              detail: 'Continue your self-paced competition',
              action: 'Open',
              color: const Color(0xFFB45B31),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CompetitionPage(role: role)),
              ),
            ),
            const SizedBox(height: 18),
            const _UpcomingCard(),
          ],
        ),
      ),
    );
  }

  void _showAssociationRequest(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          22,
          4,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Request personal association',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'Choose a broad topic or briefly write what you would like to discuss. Your guide will confirm the time.',
              style: TextStyle(color: Color(0xFF68736C), height: 1.4),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Broad topic',
                border: OutlineInputBorder(),
              ),
              items: const [
                'Spiritual practice',
                'Books or philosophy',
                'College and time',
                'Personal guidance',
              ]
                  .map((topic) => DropdownMenuItem(
                        value: topic,
                        child: Text(topic),
                      ))
                  .toList(),
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Anything you want your guide to know? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Preview only — no request was sent to a real guide.',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF315F45),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  'Preview request',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SadhanaCard extends StatelessWidget {
  const _SadhanaCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2DED1)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8C4),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                const Icon(Icons.wb_sunny_outlined, color: Color(0xFF9A5D17)),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today’s sādhana',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF25342B),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Record chanting, hearing, reading and service',
                  style: TextStyle(fontSize: 12, color: Color(0xFF748078)),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: onOpen,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD68A2D),
            ),
            child: const Text('Fill'),
          ),
        ],
      ),
    );
  }
}

class _RduaCard extends StatelessWidget {
  const _RduaCard({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF244C38), Color(0xFF3E7655)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33244C38),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TONIGHT’S RDUA CIRCLE',
            style: TextStyle(
              color: Color(0xFFE9C27B),
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Why does hearing change us?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Read five paragraphs, discuss one idea and reflect together.',
            style: TextStyle(color: Color(0xFFD6E5DA), height: 1.4),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '12 min · FOLK–2 · Topic 3',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1B65D),
                  foregroundColor: const Color(0xFF2D3E32),
                  elevation: 0,
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0E8),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.calendar_month_rounded, color: Color(0xFF315F45)),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thursday hostel session',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF183C2B),
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '8:30 PM · SVNIT hostel · Chanting and discussion',
                  style: TextStyle(color: Color(0xFF526159), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyAction extends StatelessWidget {
  const _JourneyAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.action,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String action;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE7E9E3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                height: 45,
                width: 45,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF27342C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF748078),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                action,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

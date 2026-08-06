import 'package:flutter/material.dart';

class RduaSessionPage extends StatefulWidget {
  const RduaSessionPage({super.key});

  @override
  State<RduaSessionPage> createState() => _RduaSessionPageState();
}

class _RduaSessionPageState extends State<RduaSessionPage> {
  int step = 0;

  static const steps = [
    _RduaStep(
      name: 'Read',
      duration: 'About 5 min',
      title: 'Hearing is the beginning of remembrance',
      body:
          'The student leader reads one paragraph and another student continues. The complete approved Prabhupāda passage appears here without AI rewriting it.',
      source: 'Approved corpus citation appears here',
      action: 'Finished reading',
    ),
    _RduaStep(
      name: 'Discuss',
      duration: 'About 3 min',
      title: 'Begin with one natural question',
      body:
          'What changes when we hear repeatedly—even before we feel completely convinced? Invite two or three students to speak naturally.',
      source:
          'Optional leader help is available only if the group becomes stuck',
      action: 'We discussed it',
    ),
    _RduaStep(
      name: 'Understand & Analyze',
      duration: 'About 3 min',
      title: 'Reflect together',
      body:
          '1. What was the most striking idea?\n\n2. Why may regular hearing be difficult in college?\n\n3. What small experiment can we try before tomorrow?',
      source:
          'One optional group reflection may be saved by the student leader',
      action: 'Save reflections',
    ),
    _RduaStep(
      name: 'Chant & close',
      duration: 'About 1 min',
      title: 'Chant one round together',
      body:
          'Keep the phones aside after starting. Tomorrow’s passage continues the same thought so the group develops curiosity and continuity.',
      source: 'Completion records participation—not spiritual qualification',
      action: 'Complete session',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final item = steps[step];
    final isLast = step == steps.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5EF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF315F45),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('RDUA · Session 06',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('WHY DOES HEARING CHANGE US?',
                  style: TextStyle(
                      color: Color(0xFF315F45),
                      fontSize: 12,
                      letterSpacing: 1.25,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Step ${step + 1} of ${steps.length} · ${item.name}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF334139))),
                  Text(item.duration,
                      style: const TextStyle(
                          color: Color(0xFF758078), fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: (step + 1) / steps.length,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: const Color(0xFFDDE3DA),
                color: const Color(0xFFD68A2D),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(21),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFDF8),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE4DFD2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name.toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFF9A5D17),
                              fontSize: 12,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Text(item.title,
                          style: const TextStyle(
                              fontSize: 22,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF25342B))),
                      const SizedBox(height: 17),
                      Text(item.body,
                          style: const TextStyle(
                              fontSize: 16,
                              height: 1.55,
                              color: Color(0xFF455149))),
                      const Spacer(),
                      const Divider(color: Color(0xFFE4DFD2)),
                      Text(item.source,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Color(0xFF768078),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    onPressed:
                        step == 0 ? null : () => setState(() => step -= 1),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 15)),
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (isLast) {
                          Navigator.pop(context);
                        } else {
                          setState(() => step += 1);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF315F45),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13)),
                      ),
                      child: Text(item.action,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RduaStep {
  const _RduaStep({
    required this.name,
    required this.duration,
    required this.title,
    required this.body,
    required this.source,
    required this.action,
  });

  final String name;
  final String duration;
  final String title;
  final String body;
  final String source;
  final String action;
}

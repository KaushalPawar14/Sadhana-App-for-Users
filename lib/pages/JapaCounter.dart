import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JapaCounterPage extends StatefulWidget {
  const JapaCounterPage({super.key});

  @override
  State<JapaCounterPage> createState() => _JapaCounterPageState();
}

class _JapaCounterPageState extends State<JapaCounterPage> {
  int beads = 0;
  int rounds = 0;

  void _count() {
    HapticFeedback.selectionClick();
    setState(() {
      if (beads == 107) {
        beads = 0;
        rounds += 1;
      } else {
        beads += 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = beads / 108;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5EF),
      appBar: AppBar(
        title: const Text('Soulful japa'),
        backgroundColor: const Color(0xFFF6F5EF),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 26),
          child: Column(
            children: [
              const Text(
                'Keep the phone aside if it distracts you. This counter is only a quiet aid.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6D7871), height: 1.4),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _count,
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 14,
                          backgroundColor: const Color(0xFFE2E5DF),
                          color: const Color(0xFFD68A2D),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$beads',
                            style: const TextStyle(
                              fontSize: 62,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF294F3A),
                            ),
                          ),
                          const Text(
                            'of 108 · tap to count',
                            style: TextStyle(
                              color: Color(0xFF6E7972),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: const Color(0xFFE3E7E1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.self_improvement_rounded,
                        color: Color(0xFF685390)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$rounds completed round${rounds == 1 ? '' : 's'} in this session',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        beads = 0;
                        rounds = 0;
                      }),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Reference audio will appear only after an approved recording is supplied and licensed for this use.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7C8680), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

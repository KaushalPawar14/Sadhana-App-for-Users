import 'package:flutter/material.dart';

class GuidanceChatPage extends StatefulWidget {
  const GuidanceChatPage({super.key});

  @override
  State<GuidanceChatPage> createState() => _GuidanceChatPageState();
}

class _GuidanceChatPageState extends State<GuidanceChatPage> {
  final controller = TextEditingController();
  final messages = <_Message>[
    const _Message(
      false,
      'You may ask about chanting, hearing, reading, service, or a philosophical topic. Principle guidance will be grounded in the approved Prabhupāda corpus; personal matters are better guided by your FOLK guide.',
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _sendPreview() {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      messages.add(_Message(true, text));
      messages.add(const _Message(
        false,
        'This is a safe interface preview. The reviewed Prabhupāda corpus is not connected yet, so I will not manufacture guidance. You can request personal association with your FOLK guide from the Today page.',
      ));
      controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5EF),
      appBar: AppBar(
        title: const Text('Guidance from teachings'),
        backgroundColor: const Color(0xFFF6F5EF),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1CE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Your assigned FOLK guide can review this conversation to support you appropriately.',
                style: TextStyle(
                  color: Color(0xFF795218),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final item = messages[index];
                  return Align(
                    alignment: item.fromStudent
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 330),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: item.fromStudent
                            ? const Color(0xFF315F45)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(17),
                        border: item.fromStudent
                            ? null
                            : Border.all(color: const Color(0xFFE3E7E1)),
                      ),
                      child: Text(
                        item.body,
                        style: TextStyle(
                          color: item.fromStudent
                              ? Colors.white
                              : const Color(0xFF405148),
                          height: 1.42,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'What would you like to understand?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  IconButton.filled(
                    onPressed: _sendPreview,
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF315F45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message {
  const _Message(this.fromStudent, this.body);
  final bool fromStudent;
  final String body;
}

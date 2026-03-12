import 'package:flutter/material.dart';

void showSadhanaRulesDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          "🪔 Hare Krishna!",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "📿 Sadhana Pointing System",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              SizedBox(height: 10),
              Text("🟢 Chanting:"),
              Text("• 4 rounds = 1 point"),
              SizedBox(height: 8),
              Text("📖 Reading:"),
              Text("• 20 minutes = 1 point"),
              SizedBox(height: 8),
              Text("🛕 Service / Hearing:"),
              Text("• Points will be given in Sadhana"),
              SizedBox(height: 12),
              Text(
                "⏰ Time Bonus (Very Important)",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text("🛕 Temple Entry Bonus:"),
              Text("• Before 5:30 AM → 1.25x"),
              Text("• Before 6:30 AM → 1.15x"),
              Text("• Before 7:30 AM → 1.05x"),
              SizedBox(height: 8),
              Text("📿 Japa Completion Bonus:"),
              Text("• Before 1:00 PM → 1.25x"),
              Text("• Before 6:00 PM → 1.15x"),
              Text("• Before 10:00 PM → 1.05x"),
              SizedBox(height: 8),
              Text("🌙 Sleeping Time Bonus:"),
              Text("• Before 10:15 PM → 1.25x"),
              Text("• Before 10:45 PM → 1.15x"),
              Text("• Before 11:15 PM → 1.05x"),
              SizedBox(height: 10),
              Text("→ Later times = No bonus (1.0x)"),
              SizedBox(height: 12),
              Text(
                "⚡ Priority is given to discipline in time!",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text(
                "✨ \"Chant Hare Krishna and be happy.\"",
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              SizedBox(height: 8),
              Text(
                "🙏 Sincere chanting, attentive hearing, and humble service will purify the heart.",
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      );
    },
  );
}

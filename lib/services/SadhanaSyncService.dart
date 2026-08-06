import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/AppConfiguration.dart';
import 'FolkIdentityService.dart';

class SadhanaSyncService {
  const SadhanaSyncService();

  Future<void> shadowUpsert({
    required DateTime entryDate,
    required String residenceMode,
    required int chantingRounds,
    required int bookReadingMinutes,
    required double classHearingScore,
    required String legacyCollection,
    required String legacyDocumentPath,
    String? sleepTime,
    String? wakeTime,
    String? japaFinishTime,
    String? templeEntryTime,
    double? dailyServiceScore,
  }) async {
    if (!AppConfiguration.writesSupabase ||
        !FolkIdentityService.isInitialized) {
      return;
    }

    final client = FolkIdentityService.client;
    final student = client?.auth.currentUser;
    if (client == null || student == null) return;

    final date = '${entryDate.year.toString().padLeft(4, '0')}-'
        '${entryDate.month.toString().padLeft(2, '0')}-'
        '${entryDate.day.toString().padLeft(2, '0')}';

    try {
      await client.from('sadhana_entries').upsert({
        'student_id': student.id,
        'entry_date': date,
        'residence_mode': residenceMode,
        'sleep_time': sleepTime,
        'wake_time': wakeTime,
        'chanting_rounds': chantingRounds,
        'class_hearing_score': classHearingScore,
        'book_reading_minutes': bookReadingMinutes,
        'japa_finish_time': japaFinishTime,
        'temple_entry_time': templeEntryTime,
        'daily_service_score': dailyServiceScore,
        'status': 'submitted',
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
        'source': 'legacy_firebase',
        'legacy_collection': legacyCollection,
        'legacy_document_path': legacyDocumentPath,
      }, onConflict: 'student_id,entry_date');
    } on PostgrestException catch (error) {
      // Firebase remains the protected write path during shadow mode.
      // The migration dashboard will surface reconciliation failures.
      debugPrint('Supabase shadow write was not applied: ${error.message}');
    } catch (error) {
      debugPrint('Supabase shadow write was skipped safely: $error');
    }
  }
}

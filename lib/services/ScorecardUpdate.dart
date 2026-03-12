import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/HostelSadhana.dart';
import '../models/Scorecard.dart';

class ScorecardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Method to fetch the current scorecard for a specific user
  Future<Scorecard> getCurrentScorecard(String userName) async {
    try {
      DocumentSnapshot scorecardDoc = await _firestore.collection('scorecard').doc(userName).get();

      if (scorecardDoc.exists) {
        // Create a Scorecard object from Firestore data
        return Scorecard.fromFirestore(scorecardDoc.data() as Map<String, dynamic>);
      } else {
        // If no scorecard exists for the user, return a default Scorecard object
        return Scorecard(
          totalChantRounds: 0,
          totalBookRead: 0,
          totalSBClass: 0,
          totalServiceDone: 0,
        );
      }
    } catch (e) {
      print("Error fetching scorecard: $e");
      // Return an empty scorecard on error
      return Scorecard(
        totalChantRounds: 0,
        totalBookRead: 0,
        totalSBClass: 0,
        totalServiceDone: 0,
      );
    }
  }

  // Method to update the scorecard after new data is submitted
  Future<void> updateScorecard(
      String userName,
      int newChantRounds,
      int newBookRead,
      int newSBClass,
      int newServiceDone,
      ) async {
    try {
      // Fetch the current scorecard
      Scorecard currentScorecard = await getCurrentScorecard(userName);

      // Calculate the updated totals
      int updatedChantRounds = currentScorecard.totalChantRounds + newChantRounds;
      int updatedBookRead = currentScorecard.totalBookRead + newBookRead;
      int updatedSBClass = currentScorecard.totalSBClass + newSBClass;
      int updatedServiceDone = currentScorecard.totalServiceDone + newServiceDone;

      // Create a new Scorecard object with the updated values
      Scorecard updatedScorecard = Scorecard(
        totalChantRounds: updatedChantRounds,
        totalBookRead: updatedBookRead,
        totalSBClass: updatedSBClass,
        totalServiceDone: updatedServiceDone,
      );

      // Update the scorecard in Firestore
      await _firestore.collection('scorecard').doc(userName).set(updatedScorecard.toMap());

      print("Scorecard updated successfully.");
    } catch (e) {
      print("Error updating scorecard: $e");
    }
  }
}



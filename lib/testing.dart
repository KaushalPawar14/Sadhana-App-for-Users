import 'package:cloud_firestore/cloud_firestore.dart';

void uploadBooksLevel3ToFirebase() async {
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  List<String> books = [
    "BHAGAVAD GITA AS IT IS (DELUXE EDITION)",
    "BHAGAVAD GITA AS IT IS",
    "KRISHNA: THE SUPREME PERSONALITY OF GODHEAD",
    "MUKUNDA-MALA-STOTRA",
    "NARAD-BHAKTI SUTRA",
    "SRI NAMAMRTA",
    "SELECTED VERSES FROM THE VEDIC SCRIPTURES",
    "THE NECTAR OF DEVOTION",
    "SRIMAD BHAGAVATAM",
    "SRI CHAITANYA CHARITAMRITA",
    "SRILA PRABHUPADA LILAMRTA",
    "VALMIKI'S RAMAYANA",
    "SAPTARISHI SET",
    "VEDIC LIBRARY"
  ];

  Map<String, dynamic> bookData = {};
  for (int i = 0; i < books.length; i++) {
    bookData["book_${i + 1}"] = books[i];
  }

  await firestore.collection("books").doc("level-3").set(bookData);

  print("Books uploaded successfully under level-3!");
}

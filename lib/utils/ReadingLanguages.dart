// The reading / listening languages, in the order the language button cycles
// through them: English -> Hindi -> Gujarati -> Telugu -> English.
//
// One list for both the Books and the Podcast screens. The chosen language is
// stored once, as `users/{uid}.readingPrefs.language` (see each screen's
// `_setLanguage`), so changing it on one screen changes it on the other.
const Map<String, String> kReadingLanguages = {
  'en': 'English',
  'hi': 'हिन्दी',
  'gu': 'ગુજરાતી',
  'te': 'తెలుగు',
};

// What the language button shows: a short mark of the current language.
const Map<String, String> kReadingLanguageMarks = {
  'en': 'EN',
  'hi': 'हि',
  'gu': 'ગુ',
  'te': 'తె',
};

// The language after [current] in [kReadingLanguages] order, wrapping round.
// An unknown code starts again from English.
String nextReadingLanguage(String current) {
  final codes = kReadingLanguages.keys.toList();
  final i = codes.indexOf(current);
  return codes[(i + 1) % codes.length];
}

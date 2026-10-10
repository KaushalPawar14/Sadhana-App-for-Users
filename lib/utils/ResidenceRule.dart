// Where a student can stay, by gender. "Stay at FOLK" is for boys only: a girl can
// choose Hostel or Localite, and a girl is never recorded as staying at FOLK.
const String kStayAtFolk = 'Stay at FOLK';
const String kStayAtHostel = 'Stay at Hostel';
const String kStayAtLocalite = 'Stay at Localite';

const String kFolkBoysOnlyNote = 'Stay at FOLK is available for boys only.';
const String kContactGuideToRegister =
    'Please contact your guide to complete registration.';

// The residences a student of [gender] may choose.
List<String> residenceChoices(String? gender) => gender == 'female'
    ? const [kStayAtHostel, kStayAtLocalite]
    : const [kStayAtFolk, kStayAtHostel, kStayAtLocalite];

// True for the one combination that must never be written: a female student at
// FOLK (whether she chose it or a guide's entry assigned it).
bool folkForbidden(String? gender, String? role) =>
    gender == 'female' && role == kStayAtFolk;

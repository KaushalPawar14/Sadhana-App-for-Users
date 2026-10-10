import 'dart:math' as math;

// Colour maths for the book reader: WCAG contrast, and the rule that keeps every
// run of text readable on its background in Light, Dark and Sepia. Pure Dart
// (colours are ARGB ints) so the book scan tool runs the very same code.

// WCAG AA for body text.
const double kReaderMinContrast = 4.5;

const int kBlackArgb = 0xFF000000;
const int kWhiteArgb = 0xFFFFFFFF;

// The reader's three modes (what the reader's ReaderPalette is built from).
class ReaderModeColors {
  const ReaderModeColors({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.onChrome,
  });

  final int background;
  final int text;
  final int secondaryText;
  final int onChrome;
}

const Map<String, ReaderModeColors> kReaderModeColors = {
  'light': ReaderModeColors(
    background: 0xFFFFFFFF,
    text: 0xFF1D1D1D,
    secondaryText: 0x8A000000, // black54
    onChrome: 0xDD000000, // black87
  ),
  'dark': ReaderModeColors(
    background: 0xFF121212,
    text: 0xFFE0E0E0,
    secondaryText: 0x99FFFFFF, // white60
    onChrome: 0xFFE0E0E0,
  ),
  'sepia': ReaderModeColors(
    background: 0xFFF4ECD8,
    text: 0xFF4B3621,
    secondaryText: 0xFF7A6650,
    onChrome: 0xFF4B3621,
  ),
};

// The bookmarked paragraph's tint: Colors.deepPurple at 7 %.
const int kBookmarkTintArgb = 0x12673AB7;

int _a(int c) => (c >> 24) & 0xFF;
int _r(int c) => (c >> 16) & 0xFF;
int _g(int c) => (c >> 8) & 0xFF;
int _b(int c) => c & 0xFF;

// [top] painted over the opaque [bottom].
int compositeOver(int top, int bottom) {
  final a = _a(top) / 255.0;
  int mix(int t, int b) => (t * a + b * (1 - a)).round().clamp(0, 255);
  return 0xFF000000 |
      (mix(_r(top), _r(bottom)) << 16) |
      (mix(_g(top), _g(bottom)) << 8) |
      mix(_b(top), _b(bottom));
}

double _channel(int v) {
  final s = v / 255.0;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

// Relative luminance of an opaque colour.
double luminance(int argb) =>
    0.2126 * _channel(_r(argb)) +
    0.7152 * _channel(_g(argb)) +
    0.0722 * _channel(_b(argb));

// WCAG contrast ratio of [text] on [background]. A translucent text colour is
// first composited over the background; the background must be opaque.
double contrastRatio(int text, int background) {
  final fg = _a(text) == 255 ? text : compositeOver(text, background);
  final l1 = luminance(fg);
  final l2 = luminance(background);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

// The colour a run of text is actually drawn in BEFORE the readability rule:
// its own authored colour, or (when it has none) the reader's default (dark
// grey in Light; the mode's text colour in Dark and Sepia). Text on an authored
// heading banner keeps the reader's default, which is not re-coloured there.
int effectiveColorBefore(
  int? runColor, {
  required String mode,
  required bool onBanner,
}) {
  if (runColor != null) return runColor;
  if (onBanner || mode == 'light') return 0xDD000000; // kReaderDefaultTextArgb
  return kReaderModeColors[mode]!.text;
}

// The colour a run of text is drawn in AFTER the readability rule: the run's own
// effective colour if it reaches [kReaderMinContrast] against [background]
// (intentional colours that already pass are kept); otherwise whichever of the
// mode's text colours reads best (shading included); and only if even those
// fall short, plain black or white, whichever is better.
int readableColor(
  int? runColor, {
  required String mode,
  required int background,
  bool onBanner = false,
}) {
  final colors = kReaderModeColors[mode]!;
  final own = effectiveColorBefore(runColor, mode: mode, onBanner: onBanner);
  if (contrastRatio(own, background) >= kReaderMinContrast) return own;

  var best = colors.text;
  var bestRatio = contrastRatio(best, background);
  for (final c in [colors.onChrome, colors.secondaryText]) {
    final r = contrastRatio(c, background);
    if (r > bestRatio) {
      best = c;
      bestRatio = r;
    }
  }
  if (bestRatio >= kReaderMinContrast) return best;

  final black = contrastRatio(kBlackArgb, background);
  final white = contrastRatio(kWhiteArgb, background);
  return black >= white ? kBlackArgb : kWhiteArgb;
}

// The opaque background text sits on: the page colour, tinted when the
// paragraph is bookmarked, or the heading banner's own fill.
int backgroundFor(String mode, {int? bannerFill, bool bookmarked = false}) {
  if (bannerFill != null) return compositeOver(bannerFill, kReaderModeColors[mode]!.background);
  final page = kReaderModeColors[mode]!.background;
  return bookmarked ? compositeOver(kBookmarkTintArgb, page) : page;
}

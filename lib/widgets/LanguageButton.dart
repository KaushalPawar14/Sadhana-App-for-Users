import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/ReadingLanguages.dart';
import 'PressScale.dart';

// One compact button for the top bar that shows the current language (EN, हि, ગુ,
// తె). Each tap asks for the next language in [kReadingLanguages] order; the
// screen does the one existing `_setLanguage` write. A 48 dp target; its
// tooltip and spoken label name the language in full.
class LanguageButton extends StatelessWidget {
  const LanguageButton({
    super.key,
    required this.language,
    required this.onChanged,
  });

  final String language;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final name = kReadingLanguages[language] ?? kReadingLanguages.values.first;
    final next = nextReadingLanguage(language);
    final nextName = kReadingLanguages[next]!;
    final mark = kReadingLanguageMarks[language] ?? 'EN';

    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        label: 'Language: $name. Tap to change to $nextName',
        excludeSemantics: true,
        onTap: () => onChanged(next),
        child: PressScale(
          child: SizedBox(
            width: FolkShape.touchTarget,
            height: FolkShape.touchTarget,
            child: Center(
              child: Container(
                width: FolkShape.iconButtonSize,
                height: FolkShape.iconButtonSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surface,
                  boxShadow: colors.iconShadows,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkResponse(
                    onTap: () => onChanged(next),
                    radius: FolkShape.touchTarget / 2,
                    child: Center(
                      // The mark never grows past the circle, whatever the
                      // student's text size.
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            mark,
                            maxLines: 1,
                            style: text.bodyStrong.copyWith(
                                fontSize: 14, color: colors.text, height: 1.1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

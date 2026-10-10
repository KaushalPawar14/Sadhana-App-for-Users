import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';
import '../widgets/FloatingPillNavBar.dart';

/// How far above the bottom edge the floating assistant and voice-room
/// buttons must stay: clear of the floating pill navigation (68 dp tall, 20 dp
/// up, plus the system bottom inset) with a 12 dp gap. Both overlays use it so
/// they can never be dragged or restored under the bar.
double floatingButtonBottomInset(BuildContext context) =>
    FloatingPillNavBar.reservedHeight(context) + FolkSpace.md;

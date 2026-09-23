import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../text/bidi.dart';
import '../theme/mode_theme.dart';
import '../theme/tokens.dart';

/// Required on any screen that shows data.
///
/// The text is reproduced **verbatim and in English**, because that is the
/// form the licence specifies. It is not translated, shortened or reworded,
/// and it is fetched from `/attribution` rather than hard-coded so it cannot
/// drift from what the server says.
class AttributionNote extends StatelessWidget {
  const AttributionNote(this.attribution, {super.key, this.compact = true});

  final Attribution attribution;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    if (attribution.text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsetsDirectional.symmetric(vertical: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // An English paragraph inside an RTL page: isolated and explicitly
          // left-to-right, or it reorders around its own punctuation.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              bidiIsolate(attribution.text),
              textAlign: TextAlign.start,
              // ink2. This is the one paragraph the licence requires be
              // shown, so it is the last text in the app that should be hard
              // to read — and ink3 measures 3.00:1 against the page.
              style: TextStyle(
                fontFamily: Faces.ui,
                fontSize: compact ? 11.5 : 13,
                height: 1.55,
                color: p.ink2,
              ),
            ),
          ),
          if (!compact) ...[
            SizedBox(height: Insets.sm),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                '${attribution.licence} · ${attribution.sourceUrl}',
                style: TextStyle(
                  fontFamily: Faces.mono,
                  fontSize: 11.5,
                  color: p.ink2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

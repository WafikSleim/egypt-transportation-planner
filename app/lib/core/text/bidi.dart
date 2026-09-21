/// Bidirectional text helpers.
///
/// This app runs right-to-left and shows a lot of names it did not write.
/// Two of them are routinely Latin inside an Arabic sentence:
///
/// - **Metro stop names.** The metro feed ships no `translations.txt`, so its
///   108 stops come back as `Ain Helwan`, `Al-Shohadaa` even when the rest of
///   the response is Arabic.
/// - **Place names from OpenStreetMap** that have no `name:ar`.
///
/// Dropped into RTL text unprotected, a Latin run re-orders around the
/// punctuation next to it — `Al-Shohadaa ←` ends up on the wrong side of an
/// arrow, or a stop pair reads back to front. That is not a cosmetic bug: it
/// tells the user to travel in the wrong direction.
library;

final _arabic = RegExp(r'[؀-ۿݐ-ݿ]');

/// True when the string has no Arabic letters at all — the case where the UI
/// should also *say* the name is not available in Arabic.
bool isLatinName(String s) => !_arabic.hasMatch(s);

/// Wrap in a Unicode first-strong isolate so the run keeps its own direction
/// and cannot re-order the text around it.
///
/// Applied to every name that came from the data rather than from the copy
/// deck. Harmless on Arabic strings, which is why it is unconditional — an
/// "only when Latin" check is one more place to forget.
String bidiIsolate(String s) => '\u2068$s\u2069';

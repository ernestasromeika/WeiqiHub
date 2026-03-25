import 'package:wqhub/wq/rank.dart';
import 'package:characters/characters.dart';

extension RankParsing on Rank {
  /// Parse a Pandanet rank string like "5d*", "1k*", "3d", "10k", "2p", "NR".
  /// Strips trailing *, +, ?, spaces. Returns Rank.unknown for unparseable input.
  static Rank fromString(String input) {
    if (input.isEmpty) return Rank.unknown;
    // Strip spaces, *, +, ? characters
    final cleaned =
        input.trim().replaceAll(RegExp(r'[\s*+?]'), '').toLowerCase();
    if (cleaned.isEmpty || cleaned == 'nr') return Rank.unknown;

    final match = RegExp(r'^(\d+)([kdp])$').firstMatch(cleaned);
    if (match == null) return Rank.unknown;

    final number = int.parse(match.group(1)!);
    final type = match.group(2)!;

    // Look up the rank enum value by name
    final name = '$type$number'; // e.g. "k5", "d3", "p1"
    for (final rank in Rank.values) {
      if (rank.name == name) return rank;
    }
    return Rank.unknown;
  }
}

bool isSubsequence(String text, String pattern) {
  final textChars = text.characters;
  final patternChars = pattern.characters;
  var pIndex = 0;
  for (final ch in textChars) {
    if (pIndex < patternChars.length && ch == patternChars.elementAt(pIndex)) {
      pIndex++;
      if (pIndex == patternChars.length) return true;
    }
  }
  return pIndex == patternChars.length;
}

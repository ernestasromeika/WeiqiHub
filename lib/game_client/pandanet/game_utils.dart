import 'package:wqhub/wq/rank.dart';
import 'package:characters/characters.dart';

extension RankParsing on Rank {
  /// Parse a Pandanet rank string like "5d*", "1k+", "3d?", "10k", "2p", "NR".
  /// Keeps only digits and k/d/p, discards everything else.
  static Rank fromString(String input) {
    if (input.isEmpty) return Rank.unknown;
    // Keep only digits and k/d/p
    final cleaned = input.toLowerCase().replaceAll(RegExp(r'[^0-9kdp]'), '');
    if (cleaned.isEmpty) return Rank.unknown;

    final match = RegExp(r'^(\d+)([kdp])$').firstMatch(cleaned);
    if (match == null) return Rank.unknown;

    final name = '${match.group(2)}${match.group(1)}'; // e.g. "k5", "d3", "p1"
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

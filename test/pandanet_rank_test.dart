import 'package:flutter_test/flutter_test.dart';
import 'package:wqhub/game_client/pandanet/game_utils.dart';
import 'package:wqhub/wq/rank.dart';

void main() {
  group('RankParsing.fromString', () {
    group('standard kyu ranks', () {
      test('parses 1k', () {
        expect(RankParsing.fromString('1k'), Rank.k1);
      });

      test('parses 5k', () {
        expect(RankParsing.fromString('5k'), Rank.k5);
      });

      test('parses 10k', () {
        expect(RankParsing.fromString('10k'), Rank.k10);
      });

      test('parses 18k', () {
        expect(RankParsing.fromString('18k'), Rank.k18);
      });

      test('parses 30k', () {
        expect(RankParsing.fromString('30k'), Rank.k30);
      });
    });

    group('standard dan ranks', () {
      test('parses 1d', () {
        expect(RankParsing.fromString('1d'), Rank.d1);
      });

      test('parses 3d', () {
        expect(RankParsing.fromString('3d'), Rank.d3);
      });

      test('parses 5d', () {
        expect(RankParsing.fromString('5d'), Rank.d5);
      });

      test('parses 10d', () {
        expect(RankParsing.fromString('10d'), Rank.d10);
      });
    });

    group('pro ranks', () {
      test('parses 1p', () {
        expect(RankParsing.fromString('1p'), Rank.p1);
      });

      test('parses 5p', () {
        expect(RankParsing.fromString('5p'), Rank.p5);
      });

      test('parses 9p', () {
        expect(RankParsing.fromString('9p'), Rank.p9);
      });
    });

    group('ranks with asterisk suffix', () {
      test('parses 5d*', () {
        expect(RankParsing.fromString('5d*'), Rank.d5);
      });

      test('parses 1k*', () {
        expect(RankParsing.fromString('1k*'), Rank.k1);
      });
    });

    group('ranks with plus suffix', () {
      test('parses 3d+', () {
        expect(RankParsing.fromString('3d+'), Rank.d3);
      });

      test('parses 1k+', () {
        expect(RankParsing.fromString('1k+'), Rank.k1);
      });
    });

    group('ranks with question mark suffix', () {
      test('parses 2d?', () {
        expect(RankParsing.fromString('2d?'), Rank.d2);
      });
    });

    group('ranks with surrounding spaces', () {
      test('parses " 3d "', () {
        expect(RankParsing.fromString(' 3d '), Rank.d3);
      });

      test('parses "  1k*  "', () {
        expect(RankParsing.fromString('  1k*  '), Rank.k1);
      });
    });

    group('stats response format (rank followed by trailing numbers)', () {
      test('parses "1k* 28"', () {
        expect(RankParsing.fromString('1k* 28'), Rank.k1);
      });

      test('parses "5d  0"', () {
        expect(RankParsing.fromString('5d  0'), Rank.d5);
      });
    });

    group('NR (not rated)', () {
      test('parses "NR" as unknown', () {
        expect(RankParsing.fromString('NR'), Rank.unknown);
      });

      test('parses "nr" as unknown', () {
        expect(RankParsing.fromString('nr'), Rank.unknown);
      });
    });

    group('empty string', () {
      test('returns unknown for empty string', () {
        expect(RankParsing.fromString(''), Rank.unknown);
      });
    });

    group('invalid inputs', () {
      test('returns unknown for "abc"', () {
        expect(RankParsing.fromString('abc'), Rank.unknown);
      });

      test('returns unknown for "0k"', () {
        expect(RankParsing.fromString('0k'), Rank.unknown);
      });

      test('returns unknown for "31k"', () {
        expect(RankParsing.fromString('31k'), Rank.unknown);
      });

      test('returns unknown for "11d"', () {
        expect(RankParsing.fromString('11d'), Rank.unknown);
      });

      test('returns unknown for "11p"', () {
        expect(RankParsing.fromString('11p'), Rank.unknown);
      });

      test('returns unknown for "***"', () {
        expect(RankParsing.fromString('***'), Rank.unknown);
      });
    });

    group('bracket format from games list', () {
      test('parses "[ 3d*]"', () {
        expect(RankParsing.fromString('[ 3d*]'), Rank.d3);
      });

      test('parses "[ 1k*]"', () {
        expect(RankParsing.fromString('[ 1k*]'), Rank.k1);
      });
    });

    group('mixed case', () {
      test('parses "5D*"', () {
        expect(RankParsing.fromString('5D*'), Rank.d5);
      });

      test('parses "1K"', () {
        expect(RankParsing.fromString('1K'), Rank.k1);
      });
    });

    group('unknown rank behavior', () {
      test('unknown rank returns "?" from toString()', () {
        expect(Rank.unknown.toString(), '?');
      });

      test('fromString returns unknown for unrecognized input', () {
        expect(RankParsing.fromString('xyz'), Rank.unknown);
      });
    });
  });
}

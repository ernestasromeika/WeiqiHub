import 'dart:async';
import 'package:logging/logging.dart';
import 'package:wqhub/game_client/game.dart';
import 'package:wqhub/game_client/game_result.dart';
import 'package:wqhub/game_client/game_timer.dart';
import 'package:wqhub/game_client/automatic_counting_info.dart';
import 'package:wqhub/game_client/counting_result.dart';
import 'package:wqhub/wq/wq.dart' as wq;
import 'package:wqhub/game_client/time_control/time_control.dart';
import 'package:wqhub/game_client/time_control/canadian_byoyomi.dart';
import 'pandanet_tcp_manager.dart';
import 'package:wqhub/game_client/rules.dart';

class PandanetGame extends Game {
  static final _logger = Logger('PandanetGame');
  final PandanetTcpManager tcp;

  late final Completer<GameResult> _resultCompleter;
  final _moveController = StreamController<wq.Move?>.broadcast();
  final _automaticCountingController = StreamController<bool>.broadcast();
  final _countingResultController =
      StreamController<CountingResult>.broadcast();

  late final GameTimer _blackTimer;
  late final GameTimer _whiteTimer;

  GameResult? _lastResult;
  StreamSubscription<String>? _sub;
  bool _handicapApplied = false;
  int _lastProcessedMoveNum = -1;
  static List<(int, int)> handicapPoints19(int n) {
    // TODO: refactor this mess.
    const pts = <(int, int)>[
      (3, 15), // 1
      (15, 3), // 2
      (3, 3), // 3
      (15, 15), // 4
      (9, 9), // 5
      (3, 9), // 6
      (15, 9), // 7
      (9, 3), // 8
      (9, 15), // 9
    ];

    final seq = <List<int>>[
      [], // 0
      [], // 1
      [0, 1], // 2
      [0, 1, 2], // 3
      [0, 1, 2, 3], // 4
      [0, 1, 2, 3, 4], // 5
      [0, 1, 2, 3, 5, 6], // 6
      [5, 4, 6], // 7
      [0, 1, 2, 3, 5, 6, 7, 8], // 8
      [0, 1, 2, 3, 4, 5, 6, 7, 8], // 9
    ];

    if (n < 2) return const [];
    final used = seq[n.clamp(2, 9)];
    return [for (final i in used) pts[i]];
  }

  PandanetGame({
    required String id,
    required int boardSize,
    required wq.Color myColor,
    required TimeControl timeControl,
    required this.tcp,
    int handicap = 0,
    double komi = 6.5,
    List<wq.Move> previousMoves = const [],
  }) : super(
          id: id,
          boardSize: boardSize,
          rules: Rules.japanese,
          handicap: handicap,
          komi: komi,
          myColor: myColor,
          timeControl: timeControl,
          previousMoves: previousMoves,
        ) {
    _resultCompleter = Completer<GameResult>();

    final initialTimeState = timeControl.initialState();
    _blackTimer = GameTimer(
      timeControl: timeControl,
      initialState: initialTimeState,
    );
    _whiteTimer = GameTimer(
      timeControl: timeControl,
      initialState: initialTimeState,
    );

    _blackTimer.addListener(() {
      blackTime.value = _blackTimer.value;
    });
    _whiteTimer.addListener(() {
      whiteTime.value = _whiteTimer.value;
    });

    _sub = tcp.messages.listen(_onMessage, onError: (_) {
      if (!_resultCompleter.isCompleted) {
        _resultCompleter.completeError('Connection lost before game finished');
      }
    });
    if (handicap >= 2) {
      final pts = handicapPoints19(handicap.clamp(2, 9));
      for (final p in pts) {
        _moveController.add((col: wq.Color.black, p: p));
      }
      _handicapApplied = true;
    }

    // Start the timer for the player whose turn it is.
    // In an even game, black moves first. With handicap, white moves first.
    if (handicap >= 2) {
      _whiteTimer.start(initialTimeState);
    } else {
      _blackTimer.start(initialTimeState);
    }

    // Send greeting (required by Pandanet etiquette / server rules)
    tcp.send('say Hi!');
  }

  List<String> get _goLetters =>
      List.generate(19, (i) => String.fromCharCode(i + 65))
          .where((c) => c != 'I')
          .toList(growable: false);

  /// Track the last parsed TIME states for black and white, so we can
  /// start the correct timer after a move is received.
  CanadianByoyomiTimeState? _pendingBlackTime;
  CanadianByoyomiTimeState? _pendingWhiteTime;

  void _onMessage(String message) {
    // Server sends multi-line batched messages. Process each line separately.
    for (final line in message.split('\n')) {
      _processLine(line.trim());
    }
  }

  void _processLine(String text) {
    if (text.isEmpty) return;
    _logger.info('processLine: $text');

    final handiMatch = RegExp(r'\(B\):\s*Handicap\s+(\d+)').firstMatch(text);
    if (handiMatch != null) {
      final handiCount = int.parse(handiMatch.group(1)!);

      if (handiCount >= 2) {
        final pts = handicapPoints19(handiCount.clamp(2, 9));
        for (final p in pts) {
          _moveController.add((col: wq.Color.black, p: p));
        }
      }
      return;
    }

    // Parse TIME messages:
    // 15 TIME:<id>:<player>(<color>): <byo_flag> <main_a>/<main_b> <byo_a>/<byo_b> <stones_a>/<stones_b> ...
    //
    // When byo_flag=0 (in main time):
    //   main_a/main_b = used/total, byo_a/byo_b = 0/total, stones_a/stones_b = total/total
    //   mainTimeLeft = main_b - main_a, periodTimeLeft = byo_b, stonesRemaining = stones_b
    //
    // When byo_flag=1 (in byo-yomi):
    //   main_a/main_b = 0/total (irrelevant), byo_a/byo_b = remaining/total, stones_a/stones_b = remaining/total
    //   mainTimeLeft = 0, periodTimeLeft = byo_a, stonesRemaining = stones_a
    final timeMatch = RegExp(
      r'15 TIME:\d+:\w+\(([BW])\):\s*(\d+)\s+(\d+)/(\d+)\s+(\d+)/(\d+)\s+(\d+)/(\d+)',
    ).firstMatch(text);
    if (timeMatch != null) {
      final color = timeMatch.group(1)!;
      final byoFlag = int.parse(timeMatch.group(2)!);
      final mainA = int.parse(timeMatch.group(3)!);
      final mainB = int.parse(timeMatch.group(4)!);
      final byoA = int.parse(timeMatch.group(5)!);
      final byoB = int.parse(timeMatch.group(6)!);
      final stonesA = int.parse(timeMatch.group(7)!);
      final stonesB = int.parse(timeMatch.group(8)!);

      // All fields use remaining/total format regardless of byoFlag.
      // byoFlag=0: in main time, byoFlag=1: in byo-yomi
      final CanadianByoyomiTimeState state;
      if (byoFlag == 0) {
        // In main time: main_a = remaining main seconds
        state = CanadianByoyomiTimeState(
          mainTimeLeft: Duration(seconds: mainA),
          periodTimeLeft: Duration(seconds: byoB),
          stonesRemaining: stonesB,
          stonesPerPeriod: stonesB,
        );
      } else {
        // In byo-yomi: main exhausted, byo_a = remaining period seconds
        state = CanadianByoyomiTimeState(
          mainTimeLeft: Duration.zero,
          periodTimeLeft: Duration(seconds: byoA),
          stonesRemaining: stonesA,
          stonesPerPeriod: stonesB,
        );
      }

      _logger.info('TIME parsed: color=$color, byoFlag=$byoFlag, '
          'mainLeft=${state.mainTimeLeft.inSeconds}s, '
          'periodLeft=${state.periodTimeLeft.inSeconds}s, '
          'stones=${state.stonesRemaining}/${state.stonesPerPeriod}');

      if (color == 'B') {
        _pendingBlackTime = state;
      } else {
        _pendingWhiteTime = state;
      }
      return;
    }

    final isThisGame = RegExp('Game\\s+$id\\b').hasMatch(text) ||
        RegExp('\\{Game\\s+$id\\b').hasMatch(text);
    final isMoveLine = RegExp(r'^\s*15\s+\d+\s*\([BW]\):').hasMatch(text) ||
        RegExp(r'\(\s*[BW]\s*\):\s*[A-Ta-t]\d{1,2}').hasMatch(text);

    if (!_handicapApplied && isThisGame) {
      final h = RegExp(r'\bHandicap\s+(\d+)\b').firstMatch(text);
      if (h != null) {
        final hCount = int.parse(h.group(1)!);
        if (hCount >= 2) {
          final pts = handicapPoints19(hCount.clamp(2, 9));
          for (final p in pts) {
            _moveController.add((col: wq.Color.black, p: p));
          }
        }
        _handicapApplied = true;
        return;
      }
    }

    // Detect resignation: "9 <player> has resigned the game."
    if (text.contains('has resigned the game') && _lastResult == null) {
      // Determine who resigned by checking which player name appears
      final whiteUser = white.value.username ?? '';
      final blackUser = black.value.username ?? '';
      wq.Color winner;
      if (text.contains(whiteUser) && whiteUser.isNotEmpty) {
        winner = wq.Color.black; // white resigned → black wins
      } else if (text.contains(blackUser) && blackUser.isNotEmpty) {
        winner = wq.Color.white; // black resigned → white wins
      } else {
        // Fallback: if we resigned, opponent wins
        winner = myColor == wq.Color.white ? wq.Color.black : wq.Color.white;
      }
      _logger.info('Resignation detected. Winner: ${winner.name}');
      _blackTimer.stop();
      _whiteTimer.stop();
      _finalizeResult(GameResult(
        winner: winner,
        result: 'Resign',
        description: null,
      ));
      return;
    }

    // Detect resignation via broadcast: "21 {Game <id>: ... : White/Black resigns.}"
    final rzBroadcast =
        RegExp('Game\\s+$id:.*:\\s+(Black|White)\\s+resigns').firstMatch(text);
    if (rzBroadcast != null && _lastResult == null) {
      final loser = rzBroadcast.group(1) == 'Black' ? wq.Color.black : wq.Color.white;
      _logger.info('Resignation broadcast detected. Loser: ${loser.name}');
      _blackTimer.stop();
      _whiteTimer.stop();
      _finalizeResult(GameResult(
        winner: loser == wq.Color.black ? wq.Color.white : wq.Color.black,
        result: 'Resign',
        description: null,
      ));
      return;
    }

    // Detect "lost the game ... due to nocount-resignation" as a fallback
    if (text.contains('lost the game') && text.contains('resignation') && _lastResult == null) {
      final whiteUser = white.value.username ?? '';
      final blackUser = black.value.username ?? '';
      wq.Color winner;
      if (text.contains(whiteUser) && whiteUser.isNotEmpty) {
        winner = wq.Color.black;
      } else if (text.contains(blackUser) && blackUser.isNotEmpty) {
        winner = wq.Color.white;
      } else {
        winner = myColor == wq.Color.white ? wq.Color.black : wq.Color.white;
      }
      _logger.info('Resignation (nocount) detected. Winner: ${winner.name}');
      _blackTimer.stop();
      _whiteTimer.stop();
      _finalizeResult(GameResult(
        winner: winner,
        result: 'Resign',
        description: null,
      ));
      return;
    }

    // Detect scoring result: "The result is B+3.5" or "The result is W+R"
    final fin = RegExp(r'The result is\s+([BW])\+([0-9.R]+)').firstMatch(text);
    if (fin != null && _lastResult == null) {
      final winner = fin.group(1) == 'B' ? wq.Color.black : wq.Color.white;
      final desc = fin.group(2)!;
      _logger.info('Score result: ${winner.name} wins by $desc');
      _blackTimer.stop();
      _whiteTimer.stop();
      _finalizeResult(GameResult(
        winner: winner,
        result: desc,
        description: null,
      ));
      return;
    }

    // Handle time forfeit
    if (text.contains('forfeits on time') && _lastResult == null) {
      final whiteForfeits = text.contains('White forfeits');
      _logger.info('Time forfeit: ${whiteForfeits ? "white" : "black"} loses');
      _blackTimer.stop();
      _whiteTimer.stop();
      _finalizeResult(GameResult(
        winner: whiteForfeits ? wq.Color.black : wq.Color.white,
        result: 'Time',
        description: null,
      ));
      return;
    }

    if (!isThisGame && !isMoveLine) return;

    // Parse move line: "15  <move_num>(<color>): <coord> [<captured>]"
    final mv =
        RegExp(r'(\d+)\s*\(\s*([BW])\s*\):\s*([A-Ta-t]\d{1,2})').firstMatch(text);
    if (mv != null) {
      final moveNum = int.parse(mv.group(1)!);
      final col = mv.group(2) == 'B' ? wq.Color.black : wq.Color.white;
      final parsed = parseCoordinate(mv.group(3)!);

      // Skip if we already processed this move number (own move echo)
      if (moveNum <= _lastProcessedMoveNum) {
        _logger.info('Skipping duplicate move $moveNum');
        // Still apply timers from server update even for our own echoed move
        _applyPendingTimers(lastMoveColor: col);
        return;
      }
      _lastProcessedMoveNum = moveNum;

      // Only add to move stream if it's the opponent's move
      // (our own moves were already added in move())
      if (col != myColor) {
        _moveController.add((col: col, p: parsed));
      }

      // Update timers: the player who just moved stops; the next player starts
      _applyPendingTimers(lastMoveColor: col);
      return;
    }
  }

  void _applyPendingTimers({required wq.Color lastMoveColor}) {
    // Update both timer states from server data if available
    if (_pendingBlackTime != null) {
      _blackTimer.stop();
      if (lastMoveColor == wq.Color.white) {
        // Black's turn next → start black timer
        _blackTimer.start(_pendingBlackTime!);
      } else {
        // Black just moved → show updated state but don't run
        blackTime.value = (blackTime.value.$1 + 1, _pendingBlackTime!);
      }
      _pendingBlackTime = null;
    }

    if (_pendingWhiteTime != null) {
      _whiteTimer.stop();
      if (lastMoveColor == wq.Color.black) {
        // White's turn next → start white timer
        _whiteTimer.start(_pendingWhiteTime!);
      } else {
        // White just moved → show updated state but don't run
        whiteTime.value = (whiteTime.value.$1 + 1, _pendingWhiteTime!);
      }
      _pendingWhiteTime = null;
    }
  }

  void _finalizeResult(GameResult r) {
    if (_lastResult != null) return;
    _lastResult = r;

    _countingResultController.add(
      CountingResult(
        winner: r.winner!,
        scoreLead: double.tryParse(r.result.replaceAll('R', '0')) ?? 0,
        ownership: List.generate(19, (_) => List<wq.Color?>.filled(19, null)),
        isFinal: true,
      ),
    );

    if (!_resultCompleter.isCompleted) {
      _resultCompleter.complete(r);
    }
  }

  (int, int) parseCoordinate(String coord) {
    final letter = coord[0].toUpperCase();
    final number = int.tryParse(coord.substring(1)) ?? 1;

    final col = _goLetters.indexOf(letter);
    final row = boardSize - number;

    return (row, col);
  }

  String formatCoordinates((int x, int y) point) {
    final col = point.$2;
    final row = boardSize - point.$1;
    final letter = _goLetters[col];
    final number = row;
    return '$letter$number';
  }

  /// Replay a move from game history (for restoration).
  /// Does NOT send to the server -- just updates the board.
  void replayMove(wq.Move move) {
    _lastProcessedMoveNum++;
    _moveController.add(move);
  }

  @override
  Stream<wq.Move?> moves() => _moveController.stream;

  @override
  Future<void> move(wq.Move move) async {
    _lastProcessedMoveNum++; // Pre-increment so the echo is skipped
    final coords = formatCoordinates(move.p);
    tcp.send(coords);
    _moveController.add(move);
  }

  @override
  Future<void> pass() async => tcp.send('pass');

  @override
  Future<void> resign() async => tcp.send('resign');

  @override
  Future<void> toggleManuallyRemovedStones(
      List<wq.Point> stones, bool removed) async {
    // TODO: implement manual stone removal for Pandanet scoring
  }

  @override
  Stream<bool> automaticCountingResponses() =>
      _automaticCountingController.stream;

  @override
  Stream<CountingResult> countingResults() => _countingResultController.stream;

  @override
  Stream<bool> countingResultResponses() => const Stream.empty();

  @override
  Future<AutomaticCountingInfo> automaticCounting() async {
    tcp.send('pass');
    await Future.delayed(const Duration(milliseconds: 500));
    tcp.send('done');
    return const AutomaticCountingInfo(timeout: Duration(seconds: 30));
  }

  @override
  Future<GameResult> result() async => _resultCompleter.future;

  @override
  Future<void> aiReferee() async {}

  @override
  Future<void> forceCounting() async {}

  @override
  Future<void> agreeToAutomaticCounting(bool agree) async {}

  @override
  Future<void> acceptCountingResult(bool agree) async {}

  void dispose() {
    _sub?.cancel();
    _blackTimer.dispose();
    _whiteTimer.dispose();
    _moveController.close();
    _automaticCountingController.close();
    _countingResultController.close();
    if (!_resultCompleter.isCompleted) {
      _resultCompleter.completeError('Disposed before game finished');
    }
  }
}

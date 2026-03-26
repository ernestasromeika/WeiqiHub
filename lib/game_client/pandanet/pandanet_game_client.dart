import 'dart:async';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:wqhub/game_client/automatch_preset.dart';
import 'package:wqhub/game_client/game.dart';
import 'package:wqhub/game_client/game_client.dart';
import 'package:wqhub/game_client/game_record.dart';
import 'package:wqhub/game_client/rules.dart';
import 'package:wqhub/game_client/server_features.dart';
import 'package:wqhub/game_client/server_info.dart';
import 'package:wqhub/game_client/time_control/canadian_byoyomi.dart';
import 'package:wqhub/game_client/user_info.dart';
import 'pandanet_sgf_parser.dart';
import 'pandanet_html_parser.dart';
import 'pandanet_tcp_manager.dart';
import 'pandanet_game.dart';
import 'seek_config.dart';
import 'game_utils.dart';
import 'package:wqhub/wq/wq.dart' as wq;
import 'package:wqhub/wq/rank.dart';

class PandaNetGameClient extends GameClient {
  final Logger _logger = Logger('PandaNetGameClient');
  static const String _userAgent = 'WeiqiHub/1.0';

  final ValueNotifier<UserInfo?> _userInfo = ValueNotifier(null);
  final ValueNotifier<String> _password = ValueNotifier('');
  final ValueNotifier<DateTime> _disconnected = ValueNotifier(DateTime.now());
  final http.Client _httpClient = http.Client();
  final PandanetTcpManager _tcpManager = PandanetTcpManager();

  List<SeekConfig> _seekConfigs = [];

  final String serverUrl = 'https://pandanet-igs.com/';
  final String apiUrl = 'https://my.pandanet.co.jp/';
  final String snsUrl = 'https://sns.pandanet.co.jp/';

  @override
  ServerInfo get serverInfo => ServerInfo(
        id: 'pandanet',
        name: (loc) => 'PandaNet (IGS)',
        nativeName: 'PandaNet (IGS)',
        description: (loc) => 'Internet Go Server - PandaNet',
        homeUrl: serverUrl,
        registerUrl: Uri.parse('${serverUrl}igs_users/register'),
      );

  @override
  ServerFeatures get serverFeatures => ServerFeatures(
        manualCounting: true,
        automaticCounting: true,
        aiReferee: false,
        aiRefereeMinMoveCount: const IMapConst({}),
        forcedCounting: false,
        forcedCountingMinMoveCount: const IMapConst({}),
      );

  @override
  ValueNotifier<UserInfo?> get userInfo => _userInfo;

  @override
  ValueNotifier<DateTime> get disconnected => _disconnected;

  @override
  ValueNotifier<IMap<String, AutomatchPresetStats>> get automatchStats =>
      ValueNotifier(const IMapConst({}));

  @override
  IList<AutomatchPreset> get automatchPresets => _buildAutomatchPresets();

  IList<AutomatchPreset> _buildAutomatchPresets() {
    final configs =
        _seekConfigs.isNotEmpty ? _seekConfigs : _fallbackSeekConfigs;
    // Sort by period time ascending (matching GoPanda2 dropdown order)
    final sorted = List<SeekConfig>.from(configs)
      ..sort((a, b) => a.periodTime.compareTo(b.periodTime));
    final presets = <AutomatchPreset>[];

    for (final config in sorted) {
      presets.add(AutomatchPreset(
        id: 'seek_${config.id}_19',
        boardSize: 19,
        variant: Variant.standard,
        rules: Rules.japanese,
        timeControl: CanadianByoyomiTimeControl(
          mainTime: config.mainTime,
          periodTime: config.periodTime,
          stonesPerPeriod: config.stonesPerPeriod,
        ),
      ));
    }
    return presets.lock;
  }

  static final List<SeekConfig> _fallbackSeekConfigs = [
    const SeekConfig(
      id: 2,
      mainTime: Duration(seconds: 60),
      periodTime: Duration(seconds: 300),
      stonesPerPeriod: 25,
    ),
    const SeekConfig(
      id: 1,
      mainTime: Duration(seconds: 60),
      periodTime: Duration(seconds: 420),
      stonesPerPeriod: 25,
    ),
    const SeekConfig(
      id: 0,
      mainTime: Duration(seconds: 60),
      periodTime: Duration(seconds: 600),
      stonesPerPeriod: 25,
    ),
    const SeekConfig(
      id: 3,
      mainTime: Duration(seconds: 60),
      periodTime: Duration(seconds: 900),
      stonesPerPeriod: 25,
    ),
  ];

  @override
  Future<ReadyInfo> ready() async => ReadyInfo();

  Future<void> _connectTcp(String username, String password) async {
    if (_tcpManager.isConnected) return;
    try {
      await _tcpManager.connect(username, password);
      _logger.info('TCP connection established');
    } catch (e) {
      _logger.warning('Failed to connect to PandaNet TCP server: $e');
    }
  }

  @override
  Future<UserInfo> login(String username, String password) async {
    try {
      _logger.info('Attempting login for user "$username"...');
      await _connectTcp(username, password);

      final stats = await _tcpManager.getStats();
      final rank = RankParsing.fromString(stats.rank);
      final user = UserInfo(
        userId: stats.player,
        username: stats.player,
        rank: rank,
        online: true,
        winCount: stats.wins,
        lossCount: stats.losses,
      );

      _userInfo.value = user;
      _password.value = password;

      // Fetch seek configs after login
      try {
        _seekConfigs = await _tcpManager.getSeekConfigs();
        _logger.info('Fetched ${_seekConfigs.length} seek configs');
      } catch (e) {
        _logger.warning('Failed to fetch seek configs, using fallbacks: $e');
        _seekConfigs = [];
      }

      return user;
    } catch (e, st) {
      _logger.warning('Login error: $e:$st');
      rethrow;
    }
  }

  @override
  void logout() {
    _userInfo.value = null;
    _password.value = '';
    _seekConfigs = [];
    try {
      _tcpManager.close();
    } catch (e) {
      _logger.fine('Error closing TCP manager: $e');
    }
  }

  @override
  Future<Game?> ongoingGame() async {
    final username = _userInfo.value?.username;
    if (username == null || username.isEmpty) return null;

    if (!_tcpManager.isConnected) {
      try {
        await _tcpManager.connect(username, _password.value);
      } catch (e) {
        _logger.warning('Failed to connect for game restoration: $e');
        return null;
      }
    }

    try {
      // Start listening for game start messages IMMEDIATELY.
      // The opponent may have already loaded the game before we even check.
      final gameStartFuture = _parseGameStart(
        username: username,
        fallbackTimeControl: _fallbackTimeControl,
        timeout: const Duration(seconds: 10),
      );

      // Check for stored/adjourned games
      final storedGames = await _tcpManager.getStoredGames();
      if (storedGames.isNotEmpty) {
        final gameName = storedGames.first;
        _logger.info('Found stored game: $gameName. Attempting to load...');
        _tcpManager.loadGame(gameName);
      } else {
        _logger.info(
            'No stored games found. Waiting briefly for opponent-initiated load...');
      }

      // Wait for game start (from our load OR from opponent's load)
      final game = await gameStartFuture;

      if (game == null) {
        _logger.info('No ongoing game detected.');
        return null;
      }

      // Get all previous moves and set them on the game
      try {
        final moveLines = await _tcpManager.getGameMoves(int.parse(game.id));
        final moves = _parseMoveLines(moveLines, game.boardSize);
        game.setRestoredMoves(moves);
        _logger.info('Restored ${moves.length} moves for game ${game.id}');
      } catch (e) {
        _logger.warning('Failed to restore moves: $e');
      }

      return game;
    } catch (e) {
      _logger.warning('Error during game restoration: $e');
      return null;
    }
  }

  static final CanadianByoyomiTimeControl _fallbackTimeControl =
      CanadianByoyomiTimeControl(
    mainTime: Duration(seconds: 60),
    periodTime: Duration(seconds: 600),
    stonesPerPeriod: 25,
  );

  @override
  Future<Game> findGame(String presetId) async {
    final username = _userInfo.value?.username;
    if (username == null || username.isEmpty) {
      throw Exception('Not logged in');
    }

    // Parse preset ID: seek_<configId>_<boardSize>
    final parts = presetId.split('_');
    int configId = 0;
    int boardSize = 19;
    if (parts.length >= 3 && parts[0] == 'seek') {
      configId = int.tryParse(parts[1]) ?? 0;
      boardSize = int.tryParse(parts[2]) ?? 19;
    }

    // Find the matching preset to get its time control
    final preset = automatchPresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => automatchPresets.first,
    );

    if (!_tcpManager.isConnected) {
      await _tcpManager.connect(username, _password.value);
    }

    // Send seek entry
    _logger
        .info('Sending seek entry: configId=$configId, boardSize=$boardSize');
    _tcpManager.sendSeekEntry(configId, boardSize);

    // Wait for game start
    final game = await _parseGameStart(
      username: username,
      fallbackTimeControl: preset.timeControl as CanadianByoyomiTimeControl,
    );

    if (game == null) {
      throw Exception('Failed to find game');
    }

    return game;
  }

  /// Shared helper: listens for game start messages from the TCP stream
  /// and constructs a PandanetGame when all required data is received.
  /// Used by both findGame() (after seek entry) and ongoingGame() (after load).
  Future<PandanetGame?> _parseGameStart({
    required String username,
    required CanadianByoyomiTimeControl fallbackTimeControl,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final completer = Completer<PandanetGame?>();
    StreamSubscription<String>? subscription;

    String? gameId;
    String? whitePlayer;
    String? blackPlayer;
    int handicap = 0;
    int boardSize = 19;
    double komi = 6.5;
    CanadianByoyomiTimeControl? timeControl;

    subscription = _tcpManager.messages.listen((message) {
      _logger.info(
          '_parseGameStart received: ${message.substring(0, message.length > 200 ? 200 : message.length)}');
      final text = message.trim();

      // 63 OPPONENT_FOUND <opponent> (seek only, not load)
      if (text.startsWith('63 OPPONENT_FOUND')) {
        final opponent = text.split(' ').length > 2 ? text.split(' ')[2] : '';
        _logger.info('Opponent found: $opponent');
      }

      // 15 Game <id> I: <white> (...) vs <black> (...)
      if (text.contains('15 Game') &&
          text.contains(' I: ') &&
          text.contains(' vs ')) {
        final gameIdMatch = RegExp(r'15 Game (\d+)').firstMatch(text);
        final playersMatch =
            RegExp(r'I:\s*(\w+)\s*\(.*?\)\s*vs\s+(\w+)').firstMatch(text);

        gameId = gameIdMatch?.group(1);
        whitePlayer = playersMatch?.group(1);
        blackPlayer = playersMatch?.group(2);
        _logger.info(
            'Game line: id=$gameId, white=$whitePlayer, black=$blackPlayer');
      }

      // 15 TIME:<id>:<player>(<color>): ...
      final timeMatch = RegExp(
        r'15 TIME:\d+:\w+\([BW]\):\s*\d+\s+(\d+)/(\d+)\s+(\d+)/(\d+)\s+(\d+)/(\d+)',
      ).firstMatch(text);
      if (timeMatch != null && timeControl == null) {
        final mainTotal = int.parse(timeMatch.group(2)!);
        final byoTotal = int.parse(timeMatch.group(4)!);
        final stonesTotal = int.parse(timeMatch.group(6)!);
        timeControl = CanadianByoyomiTimeControl(
          mainTime: Duration(seconds: mainTotal),
          periodTime: Duration(seconds: byoTotal),
          stonesPerPeriod: stonesTotal,
        );
        _logger.info(
          'Time control from server: main=${mainTotal}s, byo=${byoTotal}s, stones=$stonesTotal',
        );
      }

      // 15 GAMERPROPS:<id>: <board_size> <handicap> <komi>
      final propsMatch = RegExp(
        r'15 GAMERPROPS:\d+:\s*(\d+)\s+(\d+)\s+([\d.]+)',
      ).firstMatch(text);
      if (propsMatch != null) {
        boardSize = int.parse(propsMatch.group(1)!);
        handicap = int.parse(propsMatch.group(2)!);
        komi = double.parse(propsMatch.group(3)!);
        _logger.info(
            'GAMERPROPS: board=$boardSize, handicap=$handicap, komi=$komi');
      }

      // Game is ready when we see "Creating match" or "accepted" or "1 6" with a valid gameId
      final gameReady = text.contains('Creating match') ||
          text.contains('accepted') ||
          (text.contains('1 6') && gameId != null && whitePlayer != null);

      if (gameReady && gameId != null) {
        final tc = timeControl ?? fallbackTimeControl;

        final myColor =
            username == whitePlayer ? wq.Color.white : wq.Color.black;

        final game = PandanetGame(
          tcp: _tcpManager,
          id: gameId!,
          boardSize: boardSize,
          timeControl: tc,
          myColor: handicap > 0 ? wq.Color.white : myColor,
          handicap: handicap,
          komi: komi,
          previousMoves: [], // Mutable: may be populated by setRestoredMoves()
        );

        final myRank = _userInfo.value?.rank ?? Rank.unknown;
        final myName = _userInfo.value?.username ?? username;

        game.white.value = UserInfo(
          userId: whitePlayer ?? '',
          username: whitePlayer ?? '',
          rank: whitePlayer == myName ? myRank : Rank.unknown,
          online: true,
        );
        game.black.value = UserInfo(
          userId: blackPlayer ?? '',
          username: blackPlayer ?? '',
          rank: blackPlayer == myName ? myRank : Rank.unknown,
          online: true,
        );

        _logger.info(
          'Game created: id=$gameId, white=$whitePlayer, black=$blackPlayer, '
          'handicap=$handicap, komi=$komi, myColor=${game.myColor.name}',
        );

        subscription?.cancel();
        if (!completer.isCompleted) {
          completer.complete(game);
        }
      }

      // Handle load failure
      if (text.startsWith('5 ') && !completer.isCompleted) {
        _logger.warning('Game load error: $text');
        subscription?.cancel();
        completer.complete(null);
      }
    }, onError: (e) {
      subscription?.cancel();
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future.timeout(timeout, onTimeout: () {
      subscription?.cancel();
      return null;
    });
  }

  /// Parse move lines from the `moves` command into a list of wq.Move.
  List<wq.Move> _parseMoveLines(List<String> lines, int boardSize) {
    final goLetters = goColumnLetters;

    final moves = <wq.Move>[];
    for (final line in lines) {
      final match = RegExp(r'\d+\s*\(\s*([BW])\s*\):\s*([A-Ta-t]\d{1,2})')
          .firstMatch(line);
      if (match != null) {
        final colorStr = match.group(1)!;
        final coord = match.group(2)!;
        if (coord.toLowerCase() == 'handicap') continue;

        final col = colorStr == 'B' ? wq.Color.black : wq.Color.white;
        final letter = coord[0].toUpperCase();
        final number = int.tryParse(coord.substring(1)) ?? 1;
        final x = boardSize - number;
        final y = goLetters.indexOf(letter);

        if (y >= 0) {
          moves.add((col: col, p: (x, y)));
        }
      }
    }
    return moves;
  }

  @override
  void stopAutomatch() {
    _tcpManager.sendSeekCancel();
  }

  @override
  Future<List<GameSummary>> listGames() async {
    final username = _userInfo.value?.username;
    final password = _password.value;

    if (username == null || username.isEmpty || password.isEmpty) {
      _logger.warning('Cannot fetch, not logged in.');
      return [];
    }

    final response = await _httpClient.post(
      Uri.parse('${apiUrl}cgi-bin/cgi.exe?MH'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'pg': 'SearchResult',
        'PageNo': '1',
        'MyName': username,
        'userid': username,
        'password': password,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch game list: ${response.statusCode}');
    }
    final games = parseGameList(response.body, RankParsing.fromString);
    for (final game in games) {
      _logger.info(game.id);
    }
    return games;
  }

  @override
  Future<GameRecord> getGame(String gameId) async {
    final response = await _httpClient.get(Uri.parse(gameId));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch SGF: ${response.statusCode}');
    }

    var sgfContent = cleanSgfContent(response.body);
    return PandanetSgfParser.parse(sgfContent);
  }

  void dispose() {
    _httpClient.close();
    _userInfo.dispose();
    _disconnected.dispose();
  }
}

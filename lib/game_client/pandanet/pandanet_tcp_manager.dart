import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'game_utils.dart';
import 'seek_config.dart';

class PandaUserStats {
  final String player;
  final String rating;
  final int wins;
  final int losses;
  final String rank;

  PandaUserStats({
    required this.player,
    required this.rating,
    required this.wins,
    required this.losses,
    required this.rank,
  });
}

class PandanetTcpManager {
  final _logger = Logger('PandanetTcpManager');
  Socket? _socket;
  bool _connected = false;

  final _incoming = StreamController<String>.broadcast();
  Stream<String> get messages => _incoming.stream;

  bool get isConnected => _connected;

  final List<String> _whoBuffer = [];
  Completer<PandaUserStats>? _statsCompleter;
  Completer<List<Map<String, String>>>? _whoCompleter;
  Completer<List<SeekConfig>>? _seekConfigCompleter;
  final List<String> _seekConfigBuffer = [];
  final List<String> _buffer = [];

  Future<void> connect(String username, String password) async {
    if (_connected && _socket != null) return;

    _logger.info('Connecting to igs.joyjoy.net:6969...');
    try {
      _socket = await Socket.connect('igs.joyjoy.net', 6969);
      _connected = true;
      _logger.info('Connected.');

      _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _logger.info('Logging in as $username...');
      _socket!.writeln(username);
      await Future.delayed(const Duration(milliseconds: 300));
      _socket!.writeln(password);
      await Future.delayed(const Duration(milliseconds: 300));
      _socket!.writeln('toggle client true');
      _socket!.writeln('toggle nmatch true');
      _socket!.writeln('toggle seek true');
    } catch (e, st) {
      _connected = false;
      _logger.severe('Connection error: $e:$st');
      rethrow;
    }
  }

  void _onData(List<int> data) {
    final chunk = String.fromCharCodes(data);

    for (final rawLine in chunk.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) continue;

      if (line.startsWith('27')) {
        _whoBuffer.add(line);
        continue;
      }

      if ((line.startsWith('1 5') || line.startsWith('1 6')) &&
          _whoBuffer.isNotEmpty) {
        final parsed = _parseWho(_whoBuffer.join('\n'));
        _whoBuffer.clear();
        if (_whoCompleter != null && !_whoCompleter!.isCompleted) {
          _whoCompleter!.complete(parsed);
        }
        continue;
      }

      // Buffer seek config lines
      if (line.startsWith('63 CONFIG_LIST')) {
        _seekConfigBuffer.add(line);
        continue;
      }
      if (line.startsWith('63 CONFIG_LIST_END') ||
          ((line.startsWith('1 5') || line.startsWith('1 6')) &&
              _seekConfigBuffer.isNotEmpty)) {
        _finishSeekConfigBuffer();
        if (line.startsWith('1 5') || line.startsWith('1 6')) {
          // Don't skip; fall through so the prompt is handled normally
        } else {
          continue;
        }
      }

      // Pass 63 prefixed messages directly to the stream (for OPPONENT_FOUND, ENTRY, etc.)
      if (line.startsWith('63 ')) {
        _logger.info('<<< $line');
        _incoming.add(line);
        continue;
      }

      _buffer.add(line);

      if (line.startsWith('1 5') || line.startsWith('1 6')) {
        final msg = _buffer.join('\n');
        _buffer.clear();
        _handleFullMessage(msg);
      }
    }
  }

  void _finishSeekConfigBuffer() {
    final configs = _parseSeekConfigs(_seekConfigBuffer);
    _seekConfigBuffer.clear();
    if (_seekConfigCompleter != null && !_seekConfigCompleter!.isCompleted) {
      _seekConfigCompleter!.complete(configs);
    }
  }

  List<SeekConfig> _parseSeekConfigs(List<String> lines) {
    final configs = <SeekConfig>[];
    for (final line in lines) {
      // 63 CONFIG_LIST <id> <main_sec> <byo_sec> <stones> <unk1> <unk2>
      // Also handle CONFIG_LIST_START
      if (line.contains('CONFIG_LIST_START') ||
          line.contains('CONFIG_LIST_END')) {
        continue;
      }
      final parts = line.split(RegExp(r'\s+'));
      // Expected: ['63', 'CONFIG_LIST', id, main, byo, stones, unk1, unk2]
      if (parts.length >= 6) {
        final id = int.tryParse(parts[2]);
        final mainSec = int.tryParse(parts[3]);
        final byoSec = int.tryParse(parts[4]);
        final stones = int.tryParse(parts[5]);
        if (id != null && mainSec != null && byoSec != null && stones != null) {
          configs.add(SeekConfig(
            id: id,
            mainTime: Duration(seconds: mainSec),
            periodTime: Duration(seconds: byoSec),
            stonesPerPeriod: stones,
          ));
        }
      }
    }
    return configs;
  }

  List<Map<String, String>> _parseWho(String text) {
    final players = <Map<String, String>>[];
    final regex = RegExp(r'\s+([A-Za-z0-9_]+)\s+\S+\s+([0-9kdpsNR\*]+)');

    for (final match in regex.allMatches(text)) {
      final name = match.group(1);
      final rank = match.group(2);
      if (name != null && rank != null) {
        players.add({'name': name, 'rank': rank});
      }
    }

    return players;
  }

  void _handleFullMessage(String msg) {
    // Log ALL messages before noise filtering for debugging
    _logger.fine('<<< RAW: ${msg.substring(0, msg.length > 120 ? 120 : msg.length)}');
    if (_isNoise(msg)) return;
    _logger.info('<<< $msg');
    _incoming.add(msg);

    if (msg.contains('9 Player:')) {
      final parsed = _parseStats(msg);
      if (parsed != null &&
          _statsCompleter != null &&
          !_statsCompleter!.isCompleted) {
        _statsCompleter!.complete(parsed);
      }
    }

    if (msg.startsWith('9 Players') || msg.contains('(I)')) {
      final list = _parseWho(msg);
      if (list.isNotEmpty &&
          _whoCompleter != null &&
          !_whoCompleter!.isCompleted) {
        _whoCompleter!.complete(list);
      }
    }
  }

  PandaUserStats? _parseStats(String msg) {
    String? player;
    String? rating;
    String? rank;
    int wins = 0;
    int losses = 0;

    for (final line in msg.split('\n')) {
      final t = line.trim();
      if (t.startsWith('9 Player:')) {
        player = t.split('Player:').last.trim();
      } else if (t.startsWith('9 Rating:')) {
        rating = t.split('Rating:').last.trim();
      } else if (t.startsWith('9 Rank:')) {
        rank = t.split('Rank:').last.trim();
      } else if (t.startsWith('9 Wins:')) {
        final v = int.tryParse(t.split('Wins:').last.trim());
        if (v != null) wins = v;
      } else if (t.startsWith('9 Losses:')) {
        final v = int.tryParse(t.split('Losses:').last.trim());
        if (v != null) losses = v;
      }
    }

    if (player != null && rating != null && rank != null) {
      return PandaUserStats(
        player: player,
        rating: rating,
        wins: wins,
        losses: losses,
        rank: rank,
      );
    }
    return null;
  }

  Future<PandaUserStats> getStats() async {
    final s = _socket;
    if (!_connected || s == null) {
      _logger.warning('Cannot send stats, not connected.');
      throw Exception('Not connected');
    }

    _statsCompleter = Completer<PandaUserStats>();
    s.writeln('stats');
    _logger.info('>>> stats');
    return _statsCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('Stats response timeout'),
    );
  }

  Future<List<Map<String, String>>> getWho({String? range}) async {
    if (!_connected || _socket == null) throw Exception('Not connected');
    _whoCompleter = Completer<List<Map<String, String>>>();

    final cmd = range != null ? 'who $range' : 'who';
    _socket!.writeln(cmd);
    _logger.info('>>> $cmd');

    return _whoCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('Who response timeout'),
    );
  }

  Future<List<SeekConfig>> getSeekConfigs() async {
    if (!_connected || _socket == null) throw Exception('Not connected');
    _seekConfigCompleter = Completer<List<SeekConfig>>();
    _seekConfigBuffer.clear();

    _socket!.writeln('seek config_list');
    _logger.info('>>> seek config_list');

    return _seekConfigCompleter!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('Seek config_list response timeout'),
    );
  }

  void sendSeekEntry(
    int configId,
    int boardSize, {
    int maxWeaker = 3,
    int maxStronger = 3,
    bool ratedOnly = false, // TODO: change back to true for production
  }) {
    send('seek entry $configId $boardSize $maxWeaker $maxStronger ${ratedOnly ? 1 : 0}');
  }

  void sendSeekCancel() {
    send('seek entry_cancel');
  }

  void send(String command) {
    final s = _socket;
    if (!_connected || s == null) {
      _logger.warning('Cannot send "$command", not connected.');
      return;
    }
    _logger.info('>>> $command');
    s.writeln(command);
  }

  void sendMatch(
    String opponent, {
    String color = 'B',
    int main = 60,
    int overtime = 5,
  }) {
    send('match $opponent $color 19 $main $overtime');
  }

  void sendUnmatch(String opponent) => send('unmatch $opponent');
  void sendResign() => send('resign');
  void sendPass() => send('pass');
  void sendScore() => send('score');

  bool _isNoise(String msg) {
    final t = msg.trimRight();
    if (!t.startsWith('21 {')) return false;

    const patterns = <String>[
      '21 { has connected.}',
      '21 { has disconnected}',
      '21 {Match :  vs.  }',
      '21 {Game :  vs  : Black resigns.}',
      '21 {Game :  vs  : White resigns.}',
      '21 {Game :  vs  : W  B }',
      '21 {Game :  vs  has adjourned.}',
      '21 {Game :  vs  : White forfeits on time.}',
      '21 {Game :  vs  : Black forfeits on time.}'
    ];

    for (final pattern in patterns) {
      if (isSubsequence(t, pattern)) return true;
    }
    return false;
  }

  void _onError(Object error, StackTrace st) {
    _logger.warning('Socket error: $error');
    _connected = false;
  }

  void _onDone() {
    _logger.info('Socket closed.');
    _connected = false;
  }

  void close() {
    _logger.info('Closing TCP connection.');
    _connected = false;
    _socket?.destroy();
    _socket = null;
  }
}

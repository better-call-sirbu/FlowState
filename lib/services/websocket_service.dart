import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The live Render server URL.
const String kWebSocketUrl = 'wss://flowstate-azq1.onrender.com';

/// Possible statuses a user can broadcast to the room.
enum UserStatus { online, studying, onBreak }

/// Overtime type — whether the user is overrunning a study split or a break.
enum OvertimeType { study, breakTime }

/// All message types supported by the FlowState WebSocket protocol.
enum MessageType {
  timerStart,
  timerPause,
  timerReset,
  statusUpdate,
  sessionConfig,
  overtime,
  roomSnapshot,
  connected,
}

/// A parsed message received from the WebSocket server.
class FlowStateMessage {
  final MessageType type;
  final Map<String, dynamic> payload;

  FlowStateMessage({required this.type, required this.payload});

  factory FlowStateMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final typeMap = {
      'timer_start':    MessageType.timerStart,
      'timer_pause':    MessageType.timerPause,
      'timer_reset':    MessageType.timerReset,
      'status_update':  MessageType.statusUpdate,
      'session_config': MessageType.sessionConfig,
      'overtime':       MessageType.overtime,
      'room_snapshot':  MessageType.roomSnapshot,
      'connected':      MessageType.connected,
    };

    return FlowStateMessage(
      type: typeMap[typeStr] ?? MessageType.connected,
      payload: json,
    );
  }
}

/// Service that manages the WebSocket connection to the FlowState server.
///
/// Usage:
///   final ws = WebSocketService();
///   ws.connect(kWebSocketUrl);
///   ws.messages.listen((msg) { ... });
///
///   // Status
///   ws.sendStatusUpdate(userId: uid, displayName: 'Victor', status: UserStatus.studying);
///
///   // Pomodoro
///   ws.sendSessionConfig(userId: uid, displayName: 'Victor', totalMinutes: 120, splitMinutes: 30, breakMinutes: 10);
///   ws.sendTimerStart(remainingSeconds: 1800);
///   ws.sendTimerPause(remainingSeconds: 843);
///   ws.sendTimerReset();
///
///   // Overtime (called by BLoC guy every few seconds when timer goes past 00:00)
///   ws.sendOvertime(userId: uid, displayName: 'Victor', overtimeType: OvertimeType.study, secondsOver: 142);
class WebSocketService {
  WebSocketChannel? _channel;
  final _controller = StreamController<FlowStateMessage>.broadcast();

  /// Stream of incoming messages from the server.
  Stream<FlowStateMessage> get messages => _controller.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// Connect to the WebSocket server at [url].
  void connect(String url) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            final message = FlowStateMessage.fromJson(json);
            _controller.add(message);
          } catch (e) {
            print('[WebSocketService] Failed to parse message: $e');
          }
        },
        onDone: () {
          _isConnected = false;
          print('[WebSocketService] Connection closed.');
        },
        onError: (error) {
          _isConnected = false;
          print('[WebSocketService] Error: $error');
        },
      );

      print('[WebSocketService] Connected to $url');
    } catch (e) {
      _isConnected = false;
      print('[WebSocketService] Could not connect: $e');
    }
  }

  /// Disconnect from the server.
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }

  /// Send a raw JSON message to the server.
  void _send(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      print('[WebSocketService] Not connected. Message dropped.');
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  // ─── Timer Events ──────────────────────────────────────────────────────────

  /// Broadcast that the Pomodoro timer has started.
  /// [remainingSeconds] is the total duration (e.g. 1800 for 30 min).
  void sendTimerStart({required int remainingSeconds}) {
    _send({
      'type': 'timer_start',
      'remaining_seconds': remainingSeconds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Broadcast that the timer has been paused.
  /// [remainingSeconds] is how much time was left when paused.
  void sendTimerPause({required int remainingSeconds}) {
    _send({
      'type': 'timer_pause',
      'remaining_seconds': remainingSeconds,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Broadcast that the timer has been reset.
  void sendTimerReset() {
    _send({
      'type': 'timer_reset',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ─── Session Config ────────────────────────────────────────────────────────

  /// Broadcast the user's Pomodoro session configuration to the room.
  /// Called when a user sets up their session before starting.
  ///
  /// [totalMinutes]  — total study goal (e.g. 120 for 2 hours)
  /// [splitMinutes]  — how long each study split lasts (e.g. 30 min)
  /// [breakMinutes]  — how long each break lasts (e.g. 10 min)
  void sendSessionConfig({
    required String userId,
    required String displayName,
    required int totalMinutes,
    required int splitMinutes,
    required int breakMinutes,
  }) {
    _send({
      'type': 'session_config',
      'user_id': userId,
      'display_name': displayName,
      'total_minutes': totalMinutes,
      'split_minutes': splitMinutes,
      'break_minutes': breakMinutes,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ─── Overtime ──────────────────────────────────────────────────────────────

  /// Broadcast that a user is in overtime (past 00:00 of a study split or break).
  /// The BLoC guy calls this every few seconds with the updated [secondsOver].
  /// Other users will see "Overtime: +MM:SS" next to this user's status.
  ///
  /// [overtimeType] — whether it's a study split or break that ran over
  /// [secondsOver]  — how many seconds past 00:00 the user is
  void sendOvertime({
    required String userId,
    required String displayName,
    required OvertimeType overtimeType,
    required int secondsOver,
  }) {
    final overtimeStr = overtimeType == OvertimeType.study ? 'study' : 'break';
    _send({
      'type': 'overtime',
      'user_id': userId,
      'display_name': displayName,
      'overtime_type': overtimeStr,
      'seconds_over': secondsOver,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ─── Presence ──────────────────────────────────────────────────────────────

  /// Broadcast a user's presence status to the room.
  /// [userId] should be the Firebase UID.
  void sendStatusUpdate({
    required String userId,
    required String displayName,
    required UserStatus status,
  }) {
    final statusStr = {
      UserStatus.online: 'online',
      UserStatus.studying: 'studying',
      UserStatus.onBreak: 'break',
    }[status];

    _send({
      'type': 'status_update',
      'user_id': userId,
      'display_name': displayName,
      'status': statusStr,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Dispose the service and close the stream.
  void dispose() {
    disconnect();
    _controller.close();
  }
}

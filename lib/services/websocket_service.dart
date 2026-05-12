import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Possible statuses a user can broadcast to the room.
enum UserStatus { online, studying, onBreak }

/// All message types supported by the FlowState WebSocket protocol.
enum MessageType { timerStart, timerPause, timerReset, statusUpdate, connected, roomSnapshot }

/// A parsed message received from the WebSocket server.
class FlowStateMessage {
  final MessageType type;
  final Map<String, dynamic> payload;

  FlowStateMessage({required this.type, required this.payload});

  factory FlowStateMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final typeMap = {
      'timer_start': MessageType.timerStart,
      'timer_pause': MessageType.timerPause,
      'timer_reset': MessageType.timerReset,
      'status_update': MessageType.statusUpdate,
      'connected': MessageType.connected,
      'room_snapshot': MessageType.roomSnapshot,
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
///   ws.connect('wss://your-render-url.onrender.com');
///   ws.messages.listen((msg) { ... });
///   ws.sendTimerStart(remainingSeconds: 1500);
///   ws.sendStatusUpdate(userId: 'abc', status: UserStatus.studying);
class WebSocketService {
  WebSocketChannel? _channel;
  final _controller = StreamController<FlowStateMessage>.broadcast();

  /// Stream of incoming messages from the server.
  Stream<FlowStateMessage> get messages => _controller.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  /// Connect to the WebSocket server at [url].
  /// Example: 'wss://flowstate.onrender.com' or 'ws://localhost:8080'
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
  /// [remainingSeconds] is the total duration (e.g. 1500 for 25 min).
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

  // ─── Presence Events ───────────────────────────────────────────────────────

  /// Broadcast a user's presence status to the room.
  /// [userId] should be the Firebase UID.
  /// [displayName] is shown to other users.
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

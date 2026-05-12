import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The live Render server URL.
const String kWebSocketUrl = 'wss://flowstate-azq1.onrender.com';

/// All message types the server can send to clients.
enum MessageType {
  // Server → Client
  roomSnapshot,
  sessionStarted,
  phaseChange,
  sessionEnded,
  userJoined,
  userLeft,
  readyUpdate,
  hostChanged,
  error,
}

/// The phase of an active session.
enum SessionPhase { study, breakTime }

/// A parsed message received from the WebSocket server.
class FlowStateMessage {
  final MessageType type;
  final Map<String, dynamic> payload;

  FlowStateMessage({required this.type, required this.payload});

  factory FlowStateMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    const typeMap = {
      'room_snapshot':   MessageType.roomSnapshot,
      'session_started': MessageType.sessionStarted,
      'phase_change':    MessageType.phaseChange,
      'session_ended':   MessageType.sessionEnded,
      'user_joined':     MessageType.userJoined,
      'user_left':       MessageType.userLeft,
      'ready_update':    MessageType.readyUpdate,
      'host_changed':    MessageType.hostChanged,
      'error':           MessageType.error,
    };

    return FlowStateMessage(
      type: typeMap[typeStr] ?? MessageType.error,
      payload: json,
    );
  }
}

/// Configuration for a study session set by the host.
class SessionConfig {
  final int sessionMinutes;
  final int splitMinutes;
  final int breakMinutes;

  const SessionConfig({
    required this.sessionMinutes,
    required this.splitMinutes,
    required this.breakMinutes,
  });

  Map<String, dynamic> toJson() => {
    'session_minutes': sessionMinutes,
    'split_minutes': splitMinutes,
    'break_minutes': breakMinutes,
  };
}

/// Service that manages the WebSocket connection to the FlowState server.
///
/// ── Typical host flow ──────────────────────────────────────────────────────
///   ws.connect(kWebSocketUrl);
///   ws.createRoom(
///     roomId: 'room_abc',
///     hostId: firebaseUid,
///     displayName: 'Victor',
///     config: SessionConfig(sessionMinutes: 120, splitMinutes: 25, breakMinutes: 5),
///   );
///   // Later, when everyone is ready:
///   ws.startSession(roomId: 'room_abc', hostId: firebaseUid);
///
/// ── Typical member flow ────────────────────────────────────────────────────
///   ws.connect(kWebSocketUrl);
///   ws.joinRoom(roomId: 'room_abc', userId: firebaseUid, displayName: 'Ana');
///   // When done writing tasks:
///   ws.setReady(roomId: 'room_abc', userId: firebaseUid);
///
/// ── Listening ─────────────────────────────────────────────────────────────
///   ws.messages.listen((msg) {
///     switch (msg.type) {
///       case MessageType.roomSnapshot:    // full room state on join / updates
///       case MessageType.sessionStarted:  // session kicked off
///       case MessageType.phaseChange:     // study ↔ break transition
///       case MessageType.sessionEnded:    // all splits done; payload has study_time_per_user
///       case MessageType.userJoined:      // someone new joined waiting room
///       case MessageType.userLeft:        // someone left; payload has study_seconds_earned
///       case MessageType.readyUpdate:     // a member hit Ready
///       case MessageType.hostChanged:     // host reassigned (original host left)
///       case MessageType.error:           // server error string
///     }
///   });
class WebSocketService {
  WebSocketChannel? _channel;
  final _controller = StreamController<FlowStateMessage>.broadcast();

  /// Stream of incoming messages from the server.
  Stream<FlowStateMessage> get messages => _controller.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // ─── Connection ────────────────────────────────────────────────────────────

  /// Connect to the WebSocket server at [url].
  void connect(String url) {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _isConnected = true;

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _controller.add(FlowStateMessage.fromJson(json));
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

  /// Disconnect from the server cleanly.
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> message) {
    if (!_isConnected || _channel == null) {
      print('[WebSocketService] Not connected. Message dropped: ${message['type']}');
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  // ─── Room Lifecycle ────────────────────────────────────────────────────────

  /// Host: create a new room with a session configuration.
  /// The server derives the number of splits from [config.sessionMinutes] / [config.splitMinutes].
  void createRoom({
    required String roomId,
    required String hostId,
    required String displayName,
    required SessionConfig config,
  }) {
    _send({
      'type': 'create_room',
      'room_id': roomId,
      'host_id': hostId,
      'display_name': displayName,
      'session_config': config.toJson(),
    });
  }

  /// Member: join an existing waiting room.
  void joinRoom({
    required String roomId,
    required String userId,
    required String displayName,
  }) {
    _send({
      'type': 'join_room',
      'room_id': roomId,
      'user_id': userId,
      'display_name': displayName,
    });
  }

  /// Member: signal that you are done writing tasks and ready to start.
  /// Only non-host members call this.
  void setReady({
    required String roomId,
    required String userId,
  }) {
    _send({
      'type': 'set_ready',
      'room_id': roomId,
      'user_id': userId,
    });
  }

  /// Host: start the session. All splits and breaks will run automatically.
  void startSession({
    required String roomId,
    required String hostId,
  }) {
    _send({
      'type': 'start_session',
      'room_id': roomId,
      'host_id': hostId,
    });
  }

  /// Any user: leave the room voluntarily.
  /// The server will calculate how much study time was earned and broadcast it.
  void leaveRoom({
    required String roomId,
    required String userId,
  }) {
    _send({
      'type': 'leave_room',
      'room_id': roomId,
      'user_id': userId,
    });
  }

  /// User: signal that they have personally paused during a study phase.
  /// The server will start counting this time as a penalty against their study seconds.
  /// Has no effect during scheduled breaks (the server ignores it).
  void personalBreakStart({
    required String roomId,
    required String userId,
  }) {
    _send({
      'type': 'personal_break_start',
      'room_id': roomId,
      'user_id': userId,
    });
  }

  /// User: signal that they have resumed from their personal pause.
  /// The server will stop the penalty timer.
  void personalBreakEnd({
    required String roomId,
    required String userId,
  }) {
    _send({
      'type': 'personal_break_end',
      'room_id': roomId,
      'user_id': userId,
    });
  }

  // ─── Dispose ───────────────────────────────────────────────────────────────

  void dispose() {
    disconnect();
    _controller.close();
  }
}

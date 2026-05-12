import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/timer_bloc.dart';
import '../services/websocket_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudyRoomScreen extends StatefulWidget {
  final WebSocketService ws;
  final String roomId;
  final String userId;
  final String displayName;
  final bool isHost;

  const StudyRoomScreen({
    super.key,
    required this.ws,
    required this.roomId,
    required this.userId,
    required this.displayName,
    required this.isHost,
  });

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  final List<String> _tasks = [];
  final TextEditingController _taskController = TextEditingController();

  Map<String, Map<String, dynamic>> _users = {};

  // Room state
  String _roomState = 'waiting';
  bool _isReady = false;
  bool _isPausedByUser = false;

  late StreamSubscription<FlowStateMessage> _wsSub;
  late TimerBloc _timerBloc;

  @override
  void initState() {
    super.initState();
    _timerBloc = TimerBloc();
    _wsSub = widget.ws.messages.listen(_onMessage);
  }

  @override
  void dispose() {
    widget.ws.leaveRoom(roomId: widget.roomId, userId: widget.userId);
    _wsSub.cancel();
    _timerBloc.close();
    widget.ws.dispose();
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _saveStudyTime(int secondsEarned) async {
    if (secondsEarned <= 0) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      await userDoc.set({
        'totalStudySeconds': FieldValue.increment(secondsEarned),
        'displayName': user.displayName ?? widget.displayName,
      }, SetOptions(merge: true));

      print(' Saved $secondsEarned seconds to Firebase!');
    } catch (e) {
      print(' Error saving study time: $e');
    }
  }

  void _onMessage(FlowStateMessage msg) {
    switch (msg.type) {
      case MessageType.roomSnapshot:
        final usersMap = msg.payload['users'] as Map<String, dynamic>? ?? {};
        setState(() {
          _roomState = msg.payload['state'] as String? ?? _roomState;
          _users = usersMap.map((uid, data) {
            final d = data as Map<String, dynamic>;
            return MapEntry(uid, {
              'displayName': d['display_name'],
              'isReady': d['is_ready'],
              'isHost': d['is_host'],
              'phase': _roomState == 'active' ? 'study' : 'waiting',
            });
          });
          _isReady = _users[widget.userId]?['isReady'] as bool? ?? _isReady;
        });
        break;

      case MessageType.sessionStarted:
        final config = msg.payload['session_config'] as Map<String, dynamic>;
        final splitMinutes = config['split_minutes'] as int;
        final breakMinutes = config['break_minutes'] as int;
        final sessionMinutes = config['session_minutes'] as int;

        setState(() {
          _roomState = 'active';
          for (final u in _users.values) {
            u['phase'] = 'study';
          }
        });

        _timerBloc.add(
          StartSession(
            totalStudySeconds: sessionMinutes * 60,
            sessionSeconds: splitMinutes * 60,
            breakSeconds: breakMinutes * 60,
          ),
        );
        break;

      case MessageType.phaseChange:
        final phase = msg.payload['phase'] as String;
        setState(() {
          for (final entry in _users.entries) {
            if (entry.key == widget.userId && _isPausedByUser) {
              entry.value['phase'] = 'break';
            } else {
              entry.value['phase'] = phase;
            }
          }
        });
        break;

      case MessageType.sessionEnded:
        setState(() => _roomState = 'ended');

        final studyTimeMap =
            msg.payload['study_time_per_user'] as Map<String, dynamic>? ?? {};
        final myEarnedSeconds = studyTimeMap[widget.userId] as int? ?? 0;
        _saveStudyTime(myEarnedSeconds);
        break;

      case MessageType.userJoined:
        break;

      case MessageType.userLeft:
        final uid = msg.payload['user_id'] as String?;
        if (uid != null) {
          setState(() => _users.remove(uid));

          if (uid == widget.userId) {
            final myEarnedSeconds =
                msg.payload['study_seconds_earned'] as int? ?? 0;
            _saveStudyTime(myEarnedSeconds);
          }
        }
        break;

      case MessageType.readyUpdate:
        break;

      case MessageType.hostChanged:
        final newHostId = msg.payload['new_host_id'] as String?;
        if (newHostId != null) {
          setState(() {
            for (final entry in _users.entries) {
              entry.value['isHost'] = entry.key == newHostId;
            }
          });
        }
        break;

      case MessageType.personalBreakUpdate:
        final uid = msg.payload['user_id'] as String?;
        final onBreak = msg.payload['on_personal_break'] as bool? ?? false;
        if (uid != null && uid != widget.userId) {
          setState(() {
            if (_users.containsKey(uid)) {
              _users[uid]!['phase'] = onBreak ? 'break' : 'study';
            }
          });
        }
        break;

      case MessageType.error:
        final errMsg = msg.payload['message'] as String? ?? 'Unknown error';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Server: $errMsg'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        break;
    }
  }

  void _addTask(String task) {
    if (task.trim().isNotEmpty) {
      setState(() => _tasks.add(task.trim()));
      _taskController.clear();
    }
  }

  void _removeTask(int index) {
    setState(() => _tasks.removeAt(index));
  }

  String _formatTime(int totalSeconds) {
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return h == '00' ? '$m:$s' : '$h:$m:$s';
  }

  Widget _buildPresenceTracker() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Who's Here",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: _users.isEmpty
                ? const Center(
                    child: Text(
                      'No users yet...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: _users.entries.map((entry) {
                      final uid = entry.key;
                      final data = entry.value;
                      final name = data['displayName'] as String? ?? uid;
                      final isThisUser = uid == widget.userId;
                      final isUserHost = data['isHost'] as bool? ?? false;
                      final isReady = data['isReady'] as bool? ?? false;
                      final phase = data['phase'] as String? ?? 'waiting';

                      Color dotColor;
                      String statusLabel;

                      if (_roomState == 'waiting') {
                        if (isUserHost) {
                          dotColor = Colors.blueAccent;
                          statusLabel = 'Host';
                        } else if (isReady) {
                          dotColor = Colors.greenAccent;
                          statusLabel = 'Ready';
                        } else {
                          dotColor = Colors.grey;
                          statusLabel = 'Not ready';
                        }
                      } else {
                        if (phase == 'study') {
                          dotColor = Colors.greenAccent;
                          statusLabel = 'Studying';
                        } else if (phase == 'break') {
                          dotColor = Colors.amber;
                          statusLabel = 'On Break';
                        } else {
                          dotColor = Colors.grey;
                          statusLabel = 'Idle';
                        }
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: dotColor,
                          radius: 6,
                        ),
                        title: Text(
                          '$name${isThisUser ? ' (You)' : ''}${isUserHost ? ' 👑' : ''}',
                        ),
                        trailing: Text(
                          statusLabel,
                          style: TextStyle(color: dotColor),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingActions() {
    if (_roomState != 'waiting') return const SizedBox.shrink();

    if (widget.isHost) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: () {
            widget.ws.startSession(
              roomId: widget.roomId,
              hostId: widget.userId,
            );
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: Colors.blueAccent,
          ),
          child: const Text(
            'START SESSION',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: () {
            widget.ws.setReady(roomId: widget.roomId, userId: widget.userId);
            setState(() => _isReady = !_isReady);
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
            backgroundColor: _isReady ? Colors.grey : Colors.greenAccent,
            foregroundColor: Colors.black,
          ),
          child: Text(
            _isReady ? 'WAITING FOR HOST...' : 'READY',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildActiveTimerUI(TimerState state) {
    if (state is TimerComplete) {
      return const Center(
        child: Text(
          'SESSION COMPLETE!',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.greenAccent,
          ),
        ),
      );
    }

    int currentDuration = 0;
    int accumulated = 0;
    int totalTarget = 1;
    bool isBreak = false;
    bool isPaused = state is TimerPaused;

    if (state is TimerActive) {
      currentDuration = state.currentDuration;
      accumulated = state.accumulatedStudy;
      totalTarget = state.totalStudyTarget;
      isBreak = state.isBreak;
    } else if (state is TimerPaused) {
      currentDuration = state.currentDuration;
      accumulated = state.accumulatedStudy;
      totalTarget = state.totalStudyTarget;
      isBreak = state.isBreak;
    }

    double progress = totalTarget > 0 ? (accumulated / totalTarget) : 0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isBreak ? 'BREAK TIME' : 'FOCUSING',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: isBreak ? Colors.amber : Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _formatTime(currentDuration),
          style: const TextStyle(
            fontSize: 90,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 80.0),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.greenAccent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Total Progress: ${_formatTime(accumulated)} / ${_formatTime(totalTarget)}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        FloatingActionButton(
          onPressed: () {
            if (_isPausedByUser) {
              widget.ws.personalBreakEnd(
                roomId: widget.roomId,
                userId: widget.userId,
              );
              setState(() {
                _isPausedByUser = false;
                if (_users.containsKey(widget.userId)) {
                  bool roomIsOnBreak = false;
                  final s = _timerBloc.state;
                  if (s is TimerActive) roomIsOnBreak = s.isBreak;
                  if (s is TimerPaused) roomIsOnBreak = s.isBreak;
                  _users[widget.userId]!['phase'] = roomIsOnBreak
                      ? 'break'
                      : 'study';
                }
              });
            } else {
              widget.ws.personalBreakStart(
                roomId: widget.roomId,
                userId: widget.userId,
              );
              setState(() {
                _isPausedByUser = true;
                if (_users.containsKey(widget.userId)) {
                  _users[widget.userId]!['phase'] = 'break';
                }
              });
            }
          },
          backgroundColor: _isPausedByUser ? Colors.greenAccent : Colors.white,
          child: Icon(
            _isPausedByUser ? Icons.play_arrow : Icons.pause,
            color: Colors.black,
            size: 32,
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingTimerPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.hourglass_empty, size: 60, color: Colors.grey),
        const SizedBox(height: 16),
        const Text(
          'Waiting for host\nto start the session…',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, color: Colors.grey),
        ),
        if (widget.isHost) ...[
          const SizedBox(height: 8),
          const Text(
            'Press START SESSION when everyone is ready.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _timerBloc,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (_roomState == 'active') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Leave the room?'),
                content: const Text(
                  'The session is running. If you leave now you will not be able to rejoin.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Stay'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      'Leave',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              Navigator.of(context).pop();
            }
          } else {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text('FlowState — Room #${widget.roomId}'),
            centerTitle: true,
            elevation: 0,
          ),
          body: Column(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: Colors.white12),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Session Tasks',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _taskController,
                                    decoration: const InputDecoration(
                                      hintText: 'Add a task...',
                                      isDense: true,
                                    ),
                                    onSubmitted: _addTask,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.add_circle,
                                    color: Colors.greenAccent,
                                  ),
                                  onPressed: () =>
                                      _addTask(_taskController.text),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _tasks.length,
                                itemBuilder: (context, index) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.radio_button_unchecked,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  title: Text(_tasks[index]),
                                  onTap: () => _removeTask(index),
                                ),
                              ),
                            ),
                            _buildWaitingActions(),
                          ],
                        ),
                      ),
                    ),

                    Expanded(
                      flex: 2,
                      child: BlocBuilder<TimerBloc, TimerState>(
                        builder: (context, state) {
                          if (_roomState == 'waiting') {
                            return _buildWaitingTimerPlaceholder();
                          }
                          return _buildActiveTimerUI(state);
                        },
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(flex: 2, child: _buildPresenceTracker()),
            ],
          ),
        ),
      ),
    );
  }
}

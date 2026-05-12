import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/websocket_service.dart';
import 'login_screen.dart';
import 'room_screen.dart';
import 'create_room_dialog.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  Future<void> _handleHostRoom(BuildContext context) async {
    final result = await showDialog<CreateRoomResult>(
      context: context,
      builder: (_) => const CreateRoomDialog(),
    );

    if (result == null || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ws = WebSocketService();
    ws.connect(kWebSocketUrl);
    ws.createRoom(
      roomId: result.roomId,
      hostId: user.uid,
      displayName: user.displayName ?? 'Host',
      config: SessionConfig(
        sessionMinutes: result.sessionMinutes,
        splitMinutes: result.splitMinutes,
        breakMinutes: result.breakMinutes,
      ),
    );

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyRoomScreen(
          ws: ws,
          roomId: result.roomId,
          userId: user.uid,
          displayName: user.displayName ?? 'Host',
          isHost: true,
        ),
      ),
    );
  }

  Future<void> _handleJoinRoom(BuildContext context) async {
    final roomIdController = TextEditingController();

    final roomId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Join a Room'),
        content: TextField(
          controller: roomIdController,
          decoration: const InputDecoration(
            labelText: 'Room Code',
            hintText: 'Enter 5-digit room code',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(roomIdController.text.trim()),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (roomId == null || roomId.isEmpty || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ws = WebSocketService();
    ws.connect(kWebSocketUrl);
    ws.joinRoom(
      roomId: roomId,
      userId: user.uid,
      displayName: user.displayName ?? 'Member',
    );

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyRoomScreen(
          ws: ws,
          roomId: roomId,
          userId: user.uid,
          displayName: user.displayName ?? 'Member',
          isHost: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'Student';
    final email = user?.email ?? 'No email';

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowState Lobby'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline,
                size: 60,
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to the Zone,\n$displayName',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                email,
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),

              const SizedBox(height: 20),

              if (user != null)
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    int totalSeconds = 0;
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      totalSeconds = data['totalStudySeconds'] ?? 0;
                    }

                    // Convert seconds to a readable format
                    final int totalMinutes = (totalSeconds / 60).floor();
                    final int displayHours = (totalMinutes / 60).floor();
                    final int displayMins = totalMinutes % 60;

                    String timeString = displayHours > 0
                        ? '$displayHours hr $displayMins min'
                        : '$totalMinutes min';

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber, width: 2),
                      ),
                      child: Text(
                        'Total Focus: $timeString',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),

              const SizedBox(height: 40),

              ElevatedButton.icon(
                icon: const Icon(Icons.add_box, size: 28),
                label: const Text(
                  'Host New Room',
                  style: TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 65),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _handleHostRoom(context),
              ),
              const SizedBox(height: 20),

              OutlinedButton.icon(
                icon: const Icon(Icons.group_add, size: 28),
                label: const Text(
                  'Join Existing Room',
                  style: TextStyle(fontSize: 20),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 65),
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.grey, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _handleJoinRoom(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

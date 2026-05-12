import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? "Student";
    final email = user?.email ?? "No email";

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlowState Lobby'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
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
              const SizedBox(height: 50),

              // HOST BUTTON
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
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Host Room logic coming soon! 🚀'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // JOIN BUTTON
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
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Join Room dialog coming soon! 🚀'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

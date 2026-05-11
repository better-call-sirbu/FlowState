import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; 
import 'firebase_options.dart';
import 'screens/room_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Turn on the local database
  await Hive.initFlutter();
  await Hive.openBox('tasksBox');

  runApp(const FlowStateApp());
}

class FlowStateApp extends StatelessWidget {
  const FlowStateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowState',
      theme: ThemeData.dark(),
      home: const StudyRoomScreen(),
    );
  }
}
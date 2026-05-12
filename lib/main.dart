import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Turn on the Cloud (Person 1's code)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // 2. Turn on the Local Database (Your code)
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
      home: const LoginScreen(), // App now officially starts at the Login Screen!
    );
  }
}
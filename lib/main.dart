import 'package:flutter/material.dart';
import 'package:greenmind/chat_screen.dart';
import 'package:greenmind/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GreenMindApp());
}

class GreenMindApp extends StatelessWidget {
  const GreenMindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GreenMind AI',
      debugShowCheckedModeBanner: false,
      theme: greenMindTheme,
      home: const ChatScreen(),
    );
  }
}

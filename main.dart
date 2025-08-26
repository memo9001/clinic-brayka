import 'package:flutter/material.dart';

void main() {
  runApp(const ClinicBraykaApp());
}

class ClinicBraykaApp extends StatelessWidget {
  const ClinicBraykaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clinic Brayka',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinic Brayka'),
      ),
      body: const Center(
        child: Text(
          'Welcome to Clinic Brayka App\nDeveloped by MR. Mohamed Emad',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}

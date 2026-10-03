import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

void main() => runApp(const BootApp());

class BootApp extends StatelessWidget {
  const BootApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(fontFamily: 'Pretendard'),
      home: Scaffold(
        body: Center(child: Math.tex(r'\frac{1}{2}at^2', textStyle: const TextStyle(fontSize: 32))),
      ),
    );
  }
}

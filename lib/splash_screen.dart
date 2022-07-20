import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as Path;
import 'package:video_player/video_player.dart';
import 'package:sqflite/sqflite.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // video controller
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset(
      'media/splash.mp4',
    )
      ..initialize().then((_) {
        setState(() {});
      })
      ..setVolume(0.0);

    _checkDB();
  }

  void _checkDB() async {
    // playing video
    var databasesPath = await getDatabasesPath();
    var path = Path.join(databasesPath, "arujisho.db");
    var exists = await databaseExists(path);

    if (!exists) {
      try {
        await Directory(Path.dirname(path)).create(recursive: true);
      } catch (_) {}

      ByteData data = await rootBundle.load("db/arujisho.db");
      List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      _controller.play();
      var f =  Future.delayed(const Duration(seconds: 8));
      await File(path).writeAsBytes(bytes, flush: true);
      await f;
    }

    if (!mounted) return;
    Navigator.pop(context);
    Navigator.pushReplacementNamed(context, '/');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(
                  _controller,
                ),
              )
            : Container(),
      ),
    );
  }
}

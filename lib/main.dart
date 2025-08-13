import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logger/web.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

final logger = Logger(printer: SimplePrinter(printTime: true));

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, home: MyHomePage());
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? _mediaPath;
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'mp4',
        'avi',
        'mov',
        'mkv',
        'wmv',
      ],
      allowMultiple: false, // 단일 파일만 선택 가능
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final path = file.path;
      logger.d('_pickFile: $path');
      if (path != null) {
        setState(() {
          _mediaPath = path;
        });
        _player.open(Media(path));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          DropTarget(
            onDragDone: (details) {
              if (details.files.isNotEmpty) {
                final file = details.files.first;
                final path = file.path;
                logger.d('onDragDone: $path');

                setState(() {
                  _mediaPath = path;
                });
                _player.open(Media(path));
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload, size: 64, color: Colors.blue),
                    Text('파일을 여기에 드래그하세요.'),
                  ],
                ),
                Video(
                  controller: _controller,
                  fit: BoxFit.contain,
                  fill: Colors.transparent,
                ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: IconButton(
              onPressed: () {
                _pickFile();
              },
              icon: Icon(Icons.folder_open),
            ),
          ),
        ],
      ),
    );
  }
}

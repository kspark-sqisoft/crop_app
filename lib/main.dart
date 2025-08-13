import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/web.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as media_kit_video_controls;

final logger = Logger(printer: SimplePrinter(printTime: true));

enum FileType { image, video, unSupport }

final showVideoControl = false;

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
  late final Player _player;
  late final VideoController _controller;
  late final ImagePicker _picker;
  Uint8List? _imageBytes;

  FileType? _fileType;
  Size? _mediaSize;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _picker = ImagePicker();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  //파일 탐색기 파일 선택
  Future<void> _pickFile() async {
    final XFile? file = await _picker.pickMedia(requestFullMetadata: false);

    if (file != null) {
      logger.d('Pick File #########');
      logger.d('file:$file');
      logger.d('file.name:${file.name}');
      logger.d('file.mimeType:${file.mimeType}');
      logger.d('file.path: ${file.path}');
      final bytes = await file.readAsBytes();

      if (_isImage(file.mimeType, file.path)) {
        _fileType = FileType.image;
        _imageBytes = bytes;

        // 이미지 크기 얻기
        final ui.Image image = await _loadUiImage(bytes);
        _mediaSize = Size(image.width.toDouble(), image.height.toDouble());
        logger.d('Media(Video) Size: $_mediaSize');
      } else if (_isVideo(file.mimeType, file.path)) {
        _fileType = FileType.video;
        final playable = await Media.memory(bytes);
        await _player.setPlaylistMode(PlaylistMode.single);
        await _player.open(playable);
        await _controller.waitUntilFirstFrameRendered;
        if (_player.state.width != null && _player.state.height != null) {
          _mediaSize = Size(
            _player.state.width!.toDouble(),
            _player.state.height!.toDouble(),
          );
          logger.d('Media(Video) Size: $_mediaSize');
        }
        await _player.play();
      } else {
        _fileType = FileType.unSupport;
        logger.e('지원하지 않는 파일 포맷입니다.');
      }
      logger.d('_fileType:$_fileType');
      setState(() {});
    }
  }

  //이미지인 경우 이미지 사이즈 구하기 위해
  Future<ui.Image> _loadUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  bool _isImage(String? mimeType, String? path) {
    final effectiveMimeType = mimeType ?? getMimeTypeFromPath(path ?? '');
    final ext = effectiveMimeType?.split('/').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(ext);
  }

  bool _isVideo(String? mimeType, String? path) {
    final effectiveMimeType = mimeType ?? getMimeTypeFromPath(path ?? '');
    final ext = effectiveMimeType?.split('/').last.toLowerCase();
    return ['mp4', 'avi', 'mov', 'mkv', 'wmv'].contains(ext);
  }

  //웹에서 mimeType가 null 인경우 path를 통해서 mimeType 결정
  String? getMimeTypeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'mp4':
        return 'video/mp4';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'wmv':
        return 'video/x-ms-wmv';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Stack(
          children: [
            //드랍 영역
            DropTarget(
              onDragDone: (details) async {
                if (details.files.isNotEmpty) {
                  final DropItemFile file = details.files.first as DropItemFile;
                  logger.d('Drop File #########');
                  logger.d('file:$file');
                  logger.d('file.name:${file.name}');
                  logger.d('file.mimeType:${file.mimeType}');
                  logger.d('file.path: ${file.path}');

                  final bytes = await file.readAsBytes();

                  if (_isImage(file.mimeType, file.path)) {
                    _fileType = FileType.image;
                    _imageBytes = bytes;
                    // 이미지 크기 얻기
                    final ui.Image image = await _loadUiImage(bytes);
                    _mediaSize = Size(
                      image.width.toDouble(),
                      image.height.toDouble(),
                    );
                    logger.d('Media(Image) Size: $_mediaSize');
                  } else if (_isVideo(file.mimeType, file.path)) {
                    _fileType = FileType.video;
                    final playable = await Media.memory(bytes);
                    await _player.setPlaylistMode(PlaylistMode.single);
                    await _player.open(playable);
                    await _controller.waitUntilFirstFrameRendered;

                    if (_player.state.width != null &&
                        _player.state.height != null) {
                      _mediaSize = Size(
                        _player.state.width!.toDouble(),
                        _player.state.height!.toDouble(),
                      );
                      logger.d('Media(Video) Size: $_mediaSize');
                    }

                    await _player.play();
                  } else {
                    _fileType = FileType.unSupport;
                    logger.e('지원하지 않는 파일 포맷입니다.');
                  }
                  logger.d('_fileType:$_fileType');
                  setState(() {});
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
                  //이미지, 비디오 영역
                  _fileType != null
                      ? _fileType == FileType.video
                            ? Video(
                                controller: _controller,
                                fit: BoxFit.contain,
                                fill: Colors.transparent,
                                controls: showVideoControl
                                    ? media_kit_video_controls
                                          .AdaptiveVideoControls
                                    : media_kit_video_controls.NoVideoControls,
                              )
                            : _fileType == FileType.image
                            ? SizedBox.expand(
                                child: Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Center(child: Text('지원하지 않는 파일 포맷입니다.'))
                      : SizedBox.expand(),
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
      ),
    );
  }
}

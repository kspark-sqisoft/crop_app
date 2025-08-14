import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:crop_app/crop_region.dart';
import 'package:crop_app/utils.dart';
import 'package:crop_app/ffmpeg_crop_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/web.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_box_transform/flutter_box_transform.dart';

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
  Uint8List? _videoBytes; // 비디오 파일용 별도 변수 추가
  String? _fileName;
  FileType? _fileType;
  Size? _mediaSize;

  final List<CropRegion> _cropRegions = [];
  int _nextRegionId = 1;
  int? _selectedRegionId;

  bool _isSettingsPanelOpen = false;

  // 임시 입력값을 저장할 변수들
  final Map<int, Map<String, String>> _tempInputValues = {};
  // 임시 이름 값을 저장할 변수들
  final Map<int, String> _tempNameValues = {};

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.setPlaylistMode(PlaylistMode.single);
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

      // 새로운 파일 로드 시 기존 크롭 영역들 초기화
      _clearCropRegions();

      final bytes = await file.readAsBytes();
      _fileName = file.name;
      if (_isImage(file.mimeType, file.path)) {
        _fileType = FileType.image;
        _imageBytes = bytes;
        _videoBytes = null; // 이미지일 때 비디오 바이트 초기화

        // 이미지 크기 얻기
        final ui.Image image = await _loadUiImage(bytes);
        _mediaSize = Size(image.width.toDouble(), image.height.toDouble());
        logger.d('Media(Image) Size: $_mediaSize');
      } else if (_isVideo(file.mimeType, file.path)) {
        _fileType = FileType.video;
        _videoBytes = bytes; // 비디오 바이트 저장
        _imageBytes = null; // 비디오일 때 이미지 바이트 초기화

        final playable = await Media.memory(bytes);

        await _player.open(playable, play: true);
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

  // 크롭 영역들만 초기화하는 메서드
  void _clearCropRegions() {
    setState(() {
      _cropRegions.clear();
      _nextRegionId = 1;
      _selectedRegionId = null;
      _tempInputValues.clear(); // 임시 입력값들도 초기화
      _tempNameValues.clear(); // 임시 이름 값들도 초기화
      // _videoBytes는 유지 (미디어는 그대로 두고 영역만 초기화)
    });
  }

  // 완전 초기화 (모든 것을 리셋)
  void _reset() {
    logger.d('reset');
    setState(() {
      _cropRegions.clear();
      _nextRegionId = 1;
      _selectedRegionId = null;
      _mediaSize = null;
      _fileType = null;
      _isSettingsPanelOpen = false;
      _fileName = null;
      _imageBytes = null;
      _videoBytes = null; // 비디오 바이트도 초기화
      _tempInputValues.clear(); // 임시 입력값들도 초기화
      _tempNameValues.clear(); // 임시 이름 값들도 초기화
    });
    _player.stop();
  }

  void _addCropRegion() {
    final newCropRegion = CropRegion(
      id: _nextRegionId,
      name: '영역 $_nextRegionId',
      x: 0,
      y: 0,
      width: 200,
      height: 200,
      color: Utils.generateRandomColor(),
    );

    setState(() {
      _cropRegions.add(newCropRegion);
      _nextRegionId++;
      _selectedRegionId = newCropRegion.id;
    });
  }

  void _updateCropRegion(int index, CropRegion newRegion) {
    setState(() {
      // 지정된 인덱스의 크롭 영역을 새로운 값으로 교체
      _cropRegions[index] = newRegion;
    });
  }

  void _updateCropRegionFromList(int index, String value, String field) {
    final region = _cropRegions[index];

    // 문자열을 double로 변환
    double? newValue;

    // ==================== X 좌표 업데이트 ====================
    if (field == 'x') {
      newValue = double.tryParse(value);
      if (newValue != null) {
        // 입력된 픽셀 값을 상대 좌표로 변환
        // 상대 좌표 = 픽셀 값 / 원본 미디어 너비
        _updateCropRegion(index, region.copyWith(x: newValue));
      }
    }
    // ==================== Y 좌표 업데이트 ====================
    else if (field == 'y') {
      newValue = double.tryParse(value);
      if (newValue != null) {
        // 입력된 픽셀 값을 상대 좌표로 변환
        // 상대 좌표 = 픽셀 값 / 원본 미디어 높이
        _updateCropRegion(index, region.copyWith(y: newValue));
      }
    }
    // ==================== 너비 업데이트 ====================
    else if (field == 'width') {
      newValue = double.tryParse(value);
      if (newValue != null && newValue > 0) {
        // 입력된 픽셀 값을 상대 좌표로 변환
        // 상대 너비 = 픽셀 너비 / 원본 미디어 너비
        _updateCropRegion(index, region.copyWith(width: newValue));
      }
    }
    // ==================== 높이 업데이트 ====================
    else if (field == 'height') {
      newValue = double.tryParse(value);
      if (newValue != null && newValue > 0) {
        // 입력된 픽셀 값을 상대 좌표로 변환
        // 상대 높이 = 픽셀 높이 / 원본 미디어 높이
        _updateCropRegion(index, region.copyWith(height: newValue));
      }
    }
  }

  void _updateCropRegionName(int index, String newName) {
    if (newName.trim().isNotEmpty) {
      final region = _cropRegions[index];
      _updateCropRegion(index, region.copyWith(name: newName.trim()));
    }
  }

  void _updateTempInputValue(int index, String field, String value) {
    if (!_tempInputValues.containsKey(index)) {
      _tempInputValues[index] = {};
    }
    _tempInputValues[index]![field] = value;
  }

  void _updateTempNameValue(int index, String value) {
    _tempNameValues[index] = value;
  }

  void _applyAllChanges(int index) {
    final tempValues = _tempInputValues[index];
    final tempName = _tempNameValues[index];
    if (tempValues == null && tempName == null) return;

    final region = _cropRegions[index];
    double? newX, newY, newWidth, newHeight;
    String? newName;
    bool hasChanges = false;

    // 이름 처리
    if (tempName != null && tempName.trim().isNotEmpty) {
      newName = tempName.trim();
      hasChanges = true;
    }

    // X 좌표 처리
    if (tempValues?.containsKey('x') == true) {
      newX = double.tryParse(tempValues!['x']!);
      if (newX != null) hasChanges = true;
    }

    // Y 좌표 처리
    if (tempValues?.containsKey('y') == true) {
      newY = double.tryParse(tempValues!['y']!);
      if (newY != null) hasChanges = true;
    }

    // Width 처리
    if (tempValues?.containsKey('width') == true) {
      newWidth = double.tryParse(tempValues!['width']!);
      if (newWidth != null && newWidth > 0) hasChanges = true;
    }

    // Height 처리
    if (tempValues?.containsKey('height') == true) {
      newHeight = double.tryParse(tempValues!['height']!);
      if (newHeight != null && newHeight > 0) hasChanges = true;
    }

    if (hasChanges) {
      final updatedRegion = region.copyWith(
        name: newName ?? region.name,
        x: newX ?? region.x,
        y: newY ?? region.y,
        width: newWidth ?? region.width,
        height: newHeight ?? region.height,
      );
      _updateCropRegion(index, updatedRegion);

      // 임시 값들 초기화
      _tempInputValues.remove(index);
      _tempNameValues.remove(index);
      setState(() {});
    }
  }

  void _resetTempValues(int index) {
    _tempInputValues.remove(index);
    _tempNameValues.remove(index);
    setState(() {});
  }

  void _selectCropRegion(int regionId) {
    setState(() {
      _selectedRegionId = regionId;
    });
  }

  void _toggleSettingsPanel() {
    setState(() {
      // 현재 상태의 반대값으로 설정
      // true면 false로, false면 true로 변경
      _isSettingsPanelOpen = !_isSettingsPanelOpen;
    });
  }

  // 크롭 서비스 관련 변수들
  FFMpegCropService? _cropService;
  bool _isCropping = false;
  double _totalProgress = 0.0;
  String _currentEta = '';
  final Map<String, double> _regionProgress = {};

  void _cropAllRegions() async {
    if (_cropRegions.isEmpty) {
      _showSnackBar('크롭할 영역이 없습니다.');
      return;
    }

    if (_isCropping) {
      _showSnackBar('이미 크롭이 진행 중입니다.');
      return;
    }

    try {
      await _startCropProcess();
    } catch (e) {
      _showSnackBar('크롭 실패: $e');
      _isCropping = false;
      setState(() {});
    }
  }

  void _cropRegion() async {
    if (_selectedRegionId == null) {
      _showSnackBar('크롭할 영역을 선택해주세요.');
      return;
    }

    if (_isCropping) {
      _showSnackBar('이미 크롭이 진행 중입니다.');
      return;
    }

    final selectedRegion = _cropRegions.firstWhere(
      (r) => r.id == _selectedRegionId,
    );
    try {
      await _startCropProcess(regions: [selectedRegion]);
    } catch (e) {
      _showSnackBar('크롭 실패: $e');
      _isCropping = false;
      setState(() {});
    }
  }

  Future<void> _startCropProcess({List<CropRegion>? regions}) async {
    if (_fileName == null || _fileType == null) {
      _showSnackBar('파일이 로드되지 않았습니다.');
      return;
    }

    // D 드라이브의 temp 폴더에 저장
    final outputDir = r'D:\temp';
    final outputDirectory = Directory(outputDir);
    if (!await outputDirectory.exists()) {
      await outputDirectory.create(recursive: true);
    }

    // 임시 파일 경로 생성 (입력용)
    final tempDir = await Directory.systemTemp.createTemp('crop_app');
    final inputPath = '${tempDir.path}/$_fileName';

    print('크롭 시작 - 입력 파일: $inputPath');
    print('크롭 시작 - 출력 폴더: $outputDir');
    print('크롭 시작 - 파일 타입: $_fileType');

    // 현재 메모리의 데이터를 임시 파일로 저장
    if (_fileType == FileType.image && _imageBytes != null) {
      final file = File(inputPath);
      await file.writeAsBytes(_imageBytes!);
      print('이미지 파일 저장 완료: ${file.path}, 크기: ${await file.length()} bytes');
    } else if (_fileType == FileType.video && _videoBytes != null) {
      // 비디오 파일을 임시 파일로 저장
      final file = File(inputPath);
      await file.writeAsBytes(_videoBytes!);
      print('비디오 파일 저장 완료: ${file.path}, 크기: ${await file.length()} bytes');

      // 비디오 파일이 제대로 저장되었는지 확인
      if (await file.length() < 1000) {
        // 1KB 미만이면 문제가 있을 수 있음
        print('경고: 비디오 파일이 너무 작습니다. 크기: ${await file.length()} bytes');
      }
    } else {
      _showSnackBar('파일 데이터를 찾을 수 없습니다. 파일을 다시 로드해주세요.');
      return;
    }

    final cropRegions = regions ?? _cropRegions;

    setState(() {
      _isCropping = true;
      _totalProgress = 0.0;
      _currentEta = '';
      _regionProgress.clear();
      for (var region in cropRegions) {
        _regionProgress[region.name] = 0.0;
      }
    });

    try {
      // FFmpeg 경로 확인
      final ffmpegFile = File(r'C:\ffmpeg\bin\ffmpeg.exe');
      if (!await ffmpegFile.exists()) {
        throw Exception('FFmpeg를 찾을 수 없습니다: C:\\ffmpeg\\bin\\ffmpeg.exe');
      }
      print('FFmpeg 경로 확인 완료: ${ffmpegFile.path}');

      print('FFmpegCropService 생성 시작');
      _cropService = FFMpegCropService(
        ffmpegPath: r'C:\ffmpeg\bin\ffmpeg.exe', // FFmpeg 실제 경로
        inputMedia: inputPath,
        outputDir: outputDir, // D 드라이브의 temp 폴더에 저장
      );
      print('FFmpegCropService 생성 완료');

      print('크롭 실행 시작 - 영역 수: ${cropRegions.length}');
      await _cropService!.runParallel(
        regions: cropRegions,
        onProgress: (regionName, progress, totalProgress, eta) {
          print(
            '진행률 업데이트: $regionName - $progress, 전체: $totalProgress, ETA: $eta',
          );
          print('현재 _regionProgress 상태: $_regionProgress');
          print('현재 _totalProgress 상태: $_totalProgress');

          setState(() {
            _regionProgress[regionName] = progress;
            _totalProgress = totalProgress;
            _currentEta = eta;
          });

          print('업데이트 후 _regionProgress 상태: $_regionProgress');
          print('업데이트 후 _totalProgress 상태: $_totalProgress');
        },
        onRegionComplete: (regionName) {
          print('영역 크롭 완료: $regionName');
          _showSnackBar('$regionName 크롭 완료!');
        },
        onAllComplete: () async {
          print('모든 크롭 완료');
          setState(() {
            _isCropping = false;
          });

          // 결과 파일들을 사용자에게 보여주거나 다운로드 폴더로 이동
          await _showCropResults(outputDir, cropRegions);

          _showSnackBar('모든 크롭이 완료되었습니다!');
        },
      );
    } catch (e) {
      print('크롭 실행 중 에러 발생: $e');
      setState(() {
        _isCropping = false;
      });
      _showSnackBar('크롭 실패: $e');
    } finally {
      // 임시 파일 정리
      try {
        await tempDir.delete(recursive: true);
      } catch (e) {
        print('임시 파일 정리 실패: $e');
      }
    }
  }

  Future<void> _showCropResults(
    String outputDir,
    List<CropRegion> regions,
  ) async {
    // 결과 파일들을 확인하고 사용자에게 알림
    final dir = Directory(outputDir);
    if (await dir.exists()) {
      final files = await dir.list().toList();
      final cropFiles = files
          .where((f) => f is File && f.path.contains('.'))
          .toList();

      if (cropFiles.isNotEmpty) {
        _showSnackBar('${cropFiles.length}개의 크롭된 파일이 D:\\temp 폴더에 저장되었습니다.');
        // 결과 파일들을 D 드라이브의 temp 폴더에 저장 완료
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 2)),
    );
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

                  // 새로운 파일 드롭 시 기존 크롭 영역들 초기화
                  _clearCropRegions();

                  _fileName = file.name;
                  final bytes = await file.readAsBytes();

                  if (_isImage(file.mimeType, file.path)) {
                    _fileType = FileType.image;
                    _imageBytes = bytes;
                    _videoBytes = null; // 이미지일 때 비디오 바이트 초기화
                    // 이미지 크기 얻기
                    final ui.Image image = await _loadUiImage(bytes);
                    _mediaSize = Size(
                      image.width.toDouble(),
                      image.height.toDouble(),
                    );
                    logger.d('Media(Image) Size: $_mediaSize');
                  } else if (_isVideo(file.mimeType, file.path)) {
                    _fileType = FileType.video;
                    _videoBytes = bytes; // 비디오 바이트 저장
                    _imageBytes = null; // 비디오일 때 이미지 바이트 초기화

                    final playable = await Media.memory(bytes);

                    await _player.open(playable, play: true);
                    await _controller.waitUntilFirstFrameRendered;
                    await Future.delayed(
                      Duration(seconds: 1),
                    ); // 스테이트가 안들어 오는 문제
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
                fit: StackFit.expand,
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
                      ? FittedBox(
                          child: Stack(
                            children: [
                              //미디어 영역
                              if (_mediaSize != null)
                                SizedBox(
                                  width: _mediaSize!.width,
                                  height: _mediaSize!.height,
                                  child: _fileType == FileType.video
                                      ? Video(controller: _controller)
                                      : _fileType == FileType.image
                                      ? SizedBox.expand(
                                          child: Image.memory(
                                            _imageBytes!,
                                            fit: BoxFit.contain,
                                          ),
                                        )
                                      : Center(
                                          child: Text('지원하지 않는 파일 포맷입니다.'),
                                        ),
                                ),
                              //크롭 영역들
                              if (_mediaSize != null)
                                SizedBox(
                                  width: _mediaSize!.width,
                                  height: _mediaSize!.height,
                                  child: Stack(
                                    children: [
                                      ...(() {
                                        final sortedEntries = _cropRegions
                                            .asMap()
                                            .entries
                                            .toList();

                                        sortedEntries.sort((a, b) {
                                          // 선택된 영역을 마지막에 배치하여 Stack에서 최상위가 되도록 함
                                          final aIsSelected =
                                              _selectedRegionId == a.value.id;
                                          final bIsSelected =
                                              _selectedRegionId == b.value.id;

                                          if (aIsSelected && !bIsSelected) {
                                            return 1; // a가 선택됨, b가 선택되지 않음 -> a를 뒤로
                                          }

                                          if (!aIsSelected && bIsSelected) {
                                            return -1; // a가 선택되지 않음, b가 선택됨 -> b를 뒤로
                                          }
                                          return 0; // 둘 다 선택되거나 둘 다 선택되지 않음 -> 순서 유지
                                        });

                                        return sortedEntries.map((entry) {
                                          final index = entry.key;
                                          final region = entry.value;
                                          final isSelected =
                                              _selectedRegionId == region.id;

                                          return TransformableBox(
                                            key: ValueKey(
                                              'crop_region_${region.id}',
                                            ),
                                            rect: Rect.fromLTWH(
                                              // 상대 좌표를 실제 화면 좌표로 변환
                                              region.x,
                                              region.y,
                                              region.width,
                                              region.height,
                                            ),
                                            clampingRect: Rect.fromLTWH(
                                              0,
                                              0,
                                              _mediaSize!.width,
                                              _mediaSize!.height,
                                            ),
                                            onChanged: (result, event) {
                                              final updatedRegion = region
                                                  .copyWith(
                                                    x: result.rect.left,
                                                    y: result.rect.top,
                                                    width: result.rect.width,
                                                    height: result.rect.height,
                                                  );
                                              _updateCropRegion(
                                                index,
                                                updatedRegion,
                                              );
                                            },
                                            contentBuilder: (context, rect, flip) {
                                              return DecoratedBox(
                                                decoration: BoxDecoration(
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? Colors.yellow
                                                        : region.color,
                                                    width: isSelected ? 3 : 2,
                                                  ),
                                                  color: region.color.withValues(
                                                    alpha: isSelected
                                                        ? 0.3
                                                        : 0.2, // 선택된 경우 더 진한 색상
                                                  ),
                                                  boxShadow: isSelected
                                                      ? [
                                                          BoxShadow(
                                                            color: Colors.yellow
                                                                .withValues(
                                                                  alpha: 0.5,
                                                                ),
                                                            blurRadius: 8,
                                                            offset:
                                                                const Offset(
                                                                  0,
                                                                  4,
                                                                ),
                                                          ),
                                                        ]
                                                      : null,
                                                ),
                                                child: SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.vertical,
                                                  child: SingleChildScrollView(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: Padding(
                                                      padding:
                                                          EdgeInsetsGeometry.all(
                                                            8,
                                                          ),
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .start,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          //영역 이름 (편집 가능)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.all(
                                                                  4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color: region
                                                                  .color
                                                                  .withValues(
                                                                    alpha: 0.8,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: SizedBox(
                                                              width: 80,
                                                              height: 20,
                                                              child: TextField(
                                                                controller: TextEditingController(
                                                                  text:
                                                                      _tempNameValues[index] ??
                                                                      region
                                                                          .name,
                                                                ),
                                                                style: const TextStyle(
                                                                  color: Colors
                                                                      .red,
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                                decoration: const InputDecoration(
                                                                  contentPadding:
                                                                      EdgeInsets.all(
                                                                        2,
                                                                      ),
                                                                  border:
                                                                      InputBorder
                                                                          .none,
                                                                  isDense: true,
                                                                ),
                                                                onChanged: (value) {
                                                                  _updateTempNameValue(
                                                                    index,
                                                                    value,
                                                                  );
                                                                },
                                                                onSubmitted: (value) {
                                                                  final index =
                                                                      _cropRegions.indexWhere(
                                                                        (r) =>
                                                                            r.id ==
                                                                            region.id,
                                                                      );
                                                                  if (index !=
                                                                      -1) {
                                                                    _updateCropRegionName(
                                                                      index,
                                                                      value,
                                                                    );
                                                                    _resetTempValues(
                                                                      index,
                                                                    );
                                                                  }
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          // 좌표와 크기 정보
                                                          Text(
                                                            'X: ${region.x.toInt()}, Y: ${region.y.toInt()}',
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .red,
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                          ),
                                                          Text(
                                                            'W: ${region.width.toInt()}, H: ${region.height.toInt()}',
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .red,
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          //입력 필드들
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              // X 좌표 입력
                                                              SizedBox(
                                                                width: 49,
                                                                height: 34,
                                                                child: TextField(
                                                                  controller: TextEditingController(
                                                                    text:
                                                                        _tempInputValues[index]?['x'] ??
                                                                        (region.x)
                                                                            .toInt()
                                                                            .toString(),
                                                                  ),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .red,
                                                                  ),
                                                                  decoration: InputDecoration(
                                                                    labelText:
                                                                        'X',
                                                                    labelStyle:
                                                                        TextStyle(
                                                                          fontSize:
                                                                              7,
                                                                        ),
                                                                    contentPadding:
                                                                        const EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    border: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            3,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  onChanged:
                                                                      (value) {
                                                                        _updateTempInputValue(
                                                                          index,
                                                                          'x',
                                                                          value,
                                                                        );
                                                                      },
                                                                  onSubmitted: (value) {
                                                                    final newX =
                                                                        double.tryParse(
                                                                          value,
                                                                        );
                                                                    if (newX !=
                                                                        null) {
                                                                      final updatedRegion =
                                                                          region.copyWith(
                                                                            x: newX,
                                                                          );
                                                                      _updateCropRegion(
                                                                        index,
                                                                        updatedRegion,
                                                                      );
                                                                      _resetTempValues(
                                                                        index,
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              // Y 좌표 입력
                                                              SizedBox(
                                                                width: 49,
                                                                height: 34,
                                                                child: TextField(
                                                                  controller: TextEditingController(
                                                                    text:
                                                                        _tempInputValues[index]?['y'] ??
                                                                        (region.y)
                                                                            .toInt()
                                                                            .toString(),
                                                                  ),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .red,
                                                                  ),
                                                                  decoration: InputDecoration(
                                                                    labelText:
                                                                        'Y',
                                                                    labelStyle:
                                                                        TextStyle(
                                                                          fontSize:
                                                                              7,
                                                                        ),
                                                                    contentPadding:
                                                                        const EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    border: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            3,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  onChanged:
                                                                      (value) {
                                                                        _updateTempInputValue(
                                                                          index,
                                                                          'y',
                                                                          value,
                                                                        );
                                                                      },
                                                                  onSubmitted: (value) {
                                                                    final newY =
                                                                        double.tryParse(
                                                                          value,
                                                                        );
                                                                    if (newY !=
                                                                        null) {
                                                                      final updatedRegion =
                                                                          region.copyWith(
                                                                            y: newY,
                                                                          );
                                                                      _updateCropRegion(
                                                                        index,
                                                                        updatedRegion,
                                                                      );
                                                                      _resetTempValues(
                                                                        index,
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              // Width 입력
                                                              SizedBox(
                                                                width: 49,
                                                                height: 34,
                                                                child: TextField(
                                                                  controller: TextEditingController(
                                                                    text:
                                                                        _tempInputValues[index]?['width'] ??
                                                                        (region.width)
                                                                            .toInt()
                                                                            .toString(),
                                                                  ),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .red,
                                                                  ),
                                                                  decoration: InputDecoration(
                                                                    labelText:
                                                                        'W',
                                                                    labelStyle:
                                                                        TextStyle(
                                                                          fontSize:
                                                                              7,
                                                                        ),
                                                                    contentPadding:
                                                                        const EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    border: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            3,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  onChanged: (value) {
                                                                    _updateTempInputValue(
                                                                      index,
                                                                      'width',
                                                                      value,
                                                                    );
                                                                  },
                                                                  onSubmitted: (value) {
                                                                    final newWidth =
                                                                        double.tryParse(
                                                                          value,
                                                                        );
                                                                    if (newWidth !=
                                                                            null &&
                                                                        newWidth >
                                                                            0) {
                                                                      final updatedRegion =
                                                                          region.copyWith(
                                                                            width:
                                                                                newWidth,
                                                                          );
                                                                      _updateCropRegion(
                                                                        index,
                                                                        updatedRegion,
                                                                      );
                                                                      _resetTempValues(
                                                                        index,
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              // Height 입력
                                                              SizedBox(
                                                                width: 49,
                                                                height: 34,
                                                                child: TextField(
                                                                  controller: TextEditingController(
                                                                    text:
                                                                        _tempInputValues[index]?['height'] ??
                                                                        (region.height)
                                                                            .toInt()
                                                                            .toString(),
                                                                  ),
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .red,
                                                                  ),
                                                                  decoration: InputDecoration(
                                                                    labelText:
                                                                        'H',
                                                                    labelStyle:
                                                                        TextStyle(
                                                                          fontSize:
                                                                              7,
                                                                        ),
                                                                    contentPadding:
                                                                        const EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    border: OutlineInputBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            3,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                  onChanged: (value) {
                                                                    _updateTempInputValue(
                                                                      index,
                                                                      'height',
                                                                      value,
                                                                    );
                                                                  },
                                                                  onSubmitted: (value) {
                                                                    final newHeight =
                                                                        double.tryParse(
                                                                          value,
                                                                        );
                                                                    if (newHeight !=
                                                                            null &&
                                                                        newHeight >
                                                                            0) {
                                                                      final updatedRegion = region.copyWith(
                                                                        height:
                                                                            newHeight,
                                                                      );
                                                                      _updateCropRegion(
                                                                        index,
                                                                        updatedRegion,
                                                                      );
                                                                      _resetTempValues(
                                                                        index,
                                                                      );
                                                                    }
                                                                  },
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          // 적용하기 버튼
                                                          SizedBox(
                                                            width: 120,
                                                            height: 28,
                                                            child: ElevatedButton(
                                                              onPressed: () {
                                                                _applyAllChanges(
                                                                  index,
                                                                );
                                                              },
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    Colors
                                                                        .blue[600],
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          4,
                                                                    ),
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        3,
                                                                      ),
                                                                ),
                                                              ),
                                                              child: const Text(
                                                                '적용하기',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            onTap: () {
                                              // TransformableBox를 탭했을 때 해당 영역을 선택
                                              _selectCropRegion(region.id);
                                            },
                                            cornerHandleBuilder:
                                                (context, handle) {
                                                  return DefaultCornerHandle(
                                                    handle: handle,
                                                    size: isSelected
                                                        ? 12
                                                        : 8, // 선택된 경우 더 큰 핸들
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Colors.yellow
                                                            : Colors.blue,
                                                        width: isSelected
                                                            ? 2
                                                            : 1,
                                                      ),
                                                      color: Colors.white,
                                                      shape: BoxShape.rectangle,
                                                    ),
                                                  );
                                                },
                                            sideHandleBuilder:
                                                (context, handle) {
                                                  return DefaultSideHandle(
                                                    handle: handle,
                                                    length: isSelected
                                                        ? 12
                                                        : 8, // 선택된 경우 더 큰 핸들
                                                    thickness: isSelected
                                                        ? 12
                                                        : 8,
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Colors.yellow
                                                            : Colors.blue,
                                                        width: isSelected
                                                            ? 2
                                                            : 1,
                                                      ),
                                                      color: Colors.white,
                                                      shape: BoxShape.rectangle,
                                                    ),
                                                  );
                                                },
                                          );
                                        });
                                      })(),
                                    ],
                                  ),
                                ),
                              //비디오 이미지 정보 영역
                              if (_mediaSize != null)
                                SizedBox(
                                  width: _mediaSize!.width,
                                  height: _mediaSize!.height,
                                  child: Align(
                                    alignment: Alignment.bottomRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Container(
                                        // 박스 내부 패딩 (8픽셀)
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.9,
                                          ), // 90% 불투명도의 흰색 배경
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ), // 8픽셀 반지름의 둥근 모서리
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.1,
                                              ), // 10% 불투명도의 검은색 그림자
                                              blurRadius: 5, // 5픽셀 블러 효과
                                              offset: const Offset(
                                                0,
                                                2,
                                              ), // 아래쪽으로 2픽셀 이동
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start, // 왼쪽 정렬
                                          mainAxisSize:
                                              MainAxisSize.min, // 필요한 최소 크기만 사용
                                          children: [
                                            Text(
                                              '원본 크기 : ${_mediaSize!.width} x ${_mediaSize!.height}',
                                              style: TextStyle(
                                                fontSize: 10, // 작은 글씨 크기
                                                color:
                                                    Colors.grey[600], // 회색 텍스트
                                                fontWeight:
                                                    FontWeight.w500, // 중간 굵기
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : SizedBox.shrink(),
                ],
              ),
            ),
            //파일 선택창 띄우기 버튼
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
            //설정 패널
            if (_mediaSize != null)
              Positioned(
                top: 20, // 상단에서 20픽셀 아래
                right: 20, // 오른쪽에서 20픽셀 왼쪽
                width: _isSettingsPanelOpen ? 400 : null, // 열린 상태일 때 너비 400
                height: _isSettingsPanelOpen ? 800 : null, // 열린 상태일 때 높이 800
                child: _isSettingsPanelOpen
                    ? _buildSettingsPanel() // 설정 패널이 열린 경우
                    : _buildToggleButton(), // 설정 패널이 닫힌 경우 (토글 버튼만)
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //파일 이름 + 리셋
              Row(
                children: [
                  Icon(
                    _fileType == FileType.video
                        ? Icons.video_file
                        : Icons.image,
                    color: Colors.blue[600],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '파일 이름 : $_fileName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 영역 초기화 버튼
                  IconButton(
                    onPressed: _clearCropRegions,
                    icon: const Icon(Icons.refresh, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    tooltip: '영역 초기화',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.orange[100],
                      foregroundColor: Colors.orange[700],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 완전 초기화 버튼
                  IconButton(
                    onPressed: _reset,
                    icon: const Icon(Icons.delete_forever, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    tooltip: '완전 초기화',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red[100],
                      foregroundColor: Colors.red[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // CropRegion 관리 섹션
              // 크롭 영역 + 추가 버튼
              Row(
                children: [
                  Icon(Icons.crop_square, size: 16, color: Colors.green[600]),
                  const SizedBox(width: 4),
                  Text(
                    '크롭 영역',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _addCropRegion,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('추가', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[100],
                      foregroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: const Size(0, 24),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
          //리스트뷰
          Expanded(
            child: _cropRegions.isNotEmpty
                ? ListView.builder(
                    //shrinkWrap: true,
                    itemCount: _cropRegions.length,
                    itemBuilder: (context, index) {
                      final region = _cropRegions[index];
                      final isSelected = _selectedRegionId == region.id;

                      return GestureDetector(
                        onTap: () => _selectCropRegion(region.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? region.color.withValues(
                                    alpha: 0.4,
                                  ) // 선택된 경우 더 진한 색상
                                : region.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected
                                  ? region
                                        .color // 선택된 경우 더 진한 테두리
                                  : region.color.withValues(alpha: 0.6),
                              width: isSelected ? 2 : 1, // 선택된 경우 더 두꺼운 테두리
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: region.color.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 영역 이름과 삭제 버튼
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        if (isSelected)
                                          Icon(
                                            Icons.check_circle,
                                            color: region.color,
                                            size: 16,
                                          ),
                                        if (isSelected)
                                          const SizedBox(width: 4),
                                        Expanded(
                                          child: TextField(
                                            controller: TextEditingController(
                                              text:
                                                  _tempNameValues[index] ??
                                                  region.name,
                                            ),
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            decoration: const InputDecoration(
                                              contentPadding: EdgeInsets.all(4),
                                              border: InputBorder.none,
                                              isDense: true,
                                            ),
                                            onChanged: (value) {
                                              _updateTempNameValue(
                                                index,
                                                value,
                                              );
                                            },
                                            onSubmitted: (value) {
                                              _updateCropRegionName(
                                                index,
                                                value,
                                              );
                                              _resetTempValues(index);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: region.color,
                                      size: 16,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        // 선택된 영역이 삭제되는 경우 선택 상태 해제
                                        if (_selectedRegionId == region.id) {
                                          _selectedRegionId = null;
                                        }
                                        _cropRegions.removeAt(index);
                                      });
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 24,
                                      minHeight: 24,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 입력 필드들
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // X 좌표 입력
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'X',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          height: 28,
                                          child: TextField(
                                            controller: TextEditingController(
                                              text:
                                                  _tempInputValues[index]?['x'] ??
                                                  (region.x).toInt().toString(),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.red,
                                            ),
                                            decoration: InputDecoration(
                                              contentPadding:
                                                  const EdgeInsets.all(6),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              isDense: true,
                                            ),
                                            onChanged: (value) {
                                              _updateTempInputValue(
                                                index,
                                                'x',
                                                value,
                                              );
                                            },
                                            onSubmitted: (value) {
                                              _updateCropRegionFromList(
                                                index,
                                                value,
                                                'x',
                                              );
                                              _resetTempValues(index);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Y 좌표 입력
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Y',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          height: 28,
                                          child: TextField(
                                            controller: TextEditingController(
                                              text:
                                                  _tempInputValues[index]?['y'] ??
                                                  (region.y).toInt().toString(),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.red,
                                            ),
                                            decoration: InputDecoration(
                                              contentPadding:
                                                  const EdgeInsets.all(6),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              isDense: true,
                                            ),
                                            onChanged: (value) {
                                              _updateTempInputValue(
                                                index,
                                                'y',
                                                value,
                                              );
                                            },
                                            onSubmitted: (value) {
                                              _updateCropRegionFromList(
                                                index,
                                                value,
                                                'y',
                                              );
                                              _resetTempValues(index);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Width 입력
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'W',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          height: 28,
                                          child: TextField(
                                            controller: TextEditingController(
                                              text:
                                                  _tempInputValues[index]?['width'] ??
                                                  (region.width)
                                                      .toInt()
                                                      .toString(),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.red,
                                            ),
                                            decoration: InputDecoration(
                                              contentPadding:
                                                  const EdgeInsets.all(6),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              isDense: true,
                                            ),
                                            onChanged: (value) {
                                              _updateTempInputValue(
                                                index,
                                                'width',
                                                value,
                                              );
                                            },
                                            onSubmitted: (value) {
                                              _updateCropRegionFromList(
                                                index,
                                                value,
                                                'width',
                                              );
                                              _resetTempValues(index);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Height 입력
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'H',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          height: 28,
                                          child: TextField(
                                            controller: TextEditingController(
                                              text:
                                                  _tempInputValues[index]?['height'] ??
                                                  (region.height)
                                                      .toInt()
                                                      .toString(),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              color: Colors.red,
                                            ),
                                            decoration: InputDecoration(
                                              contentPadding:
                                                  const EdgeInsets.all(6),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              isDense: true,
                                            ),
                                            onChanged: (value) {
                                              _updateTempInputValue(
                                                index,
                                                'height',
                                                value,
                                              );
                                            },
                                            onSubmitted: (value) {
                                              _updateCropRegionFromList(
                                                index,
                                                value,
                                                'height',
                                              );
                                              _resetTempValues(index);
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 적용하기 버튼과 크롭하기 버튼
                              Row(
                                children: [
                                  // 적용하기 버튼
                                  Expanded(
                                    child: SizedBox(
                                      height: 28,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          _applyAllChanges(index);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.blue[600],
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          '적용하기',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 크롭하기 버튼
                                  SizedBox(
                                    width: 80,
                                    height: 28,
                                    child: ElevatedButton(
                                      onPressed: _isCropping
                                          ? null
                                          : () {
                                              _cropRegion();
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isCropping
                                            ? Colors.grey[400]
                                            : Colors.green[600],
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        _isCropping ? '대기중' : '크롭하기',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : Container(),
          ),
          // 크롭 진행 상황 표시
          if (_isCropping)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.crop, size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 8),
                      Text(
                        '크롭 진행 중...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                      const Spacer(),
                      if (_currentEta.isNotEmpty)
                        Text(
                          '예상 완료: $_currentEta',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue[600],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 전체 진행률
                  LinearProgressIndicator(
                    value: _totalProgress,
                    backgroundColor: Colors.blue[100],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blue[600]!,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 개별 영역 진행률
                  ..._regionProgress.entries.map((entry) {
                    final regionName = entry.key;
                    final progress = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              regionName,
                              style: const TextStyle(fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 7,
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.green[600]!,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          // 모두 크롭 하기 버튼
          if (_cropRegions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isCropping ? null : _cropAllRegions,
                      icon: _isCropping
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.crop, size: 16),
                      label: Text(
                        _isCropping ? '크롭 중...' : '모두 크롭 하기',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCropping
                            ? Colors.grey[400]
                            : Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // 하단 닫기 버튼 (항상 하단에 고정)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _toggleSettingsPanel,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey[100],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      '닫기',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return Container(
      // 버튼 주변의 패딩 (4픽셀)
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // 반투명 흰색 배경 (95% 불투명도)
        color: Colors.white.withValues(alpha: 0.95),
        // 둥근 모서리 (6픽셀 반지름)
        borderRadius: BorderRadius.circular(6),
        // 그림자 효과
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2), // 20% 불투명도의 검은색
            blurRadius: 8, // 8픽셀 블러 효과
            offset: const Offset(0, 2), // 아래쪽으로 2픽셀 이동
          ),
        ],
        // 회색 테두리 (1픽셀 두께)
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: IconButton(
        // 버튼 클릭 시 설정 패널 토글
        onPressed: _toggleSettingsPanel,
        // 설정 아이콘 (16픽셀 크기)
        icon: const Icon(Icons.settings, size: 16),
        // 마우스 호버 시 표시되는 툴팁
        tooltip: '설정 패널 열기',
        // 버튼 내부 패딩 제거
        padding: EdgeInsets.zero,
        // 버튼의 최소 크기 제한
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        // 버튼 스타일 설정
        style: IconButton.styleFrom(
          backgroundColor: Colors.blue[100], // 연한 파란색 배경
          foregroundColor: Colors.blue[700], // 진한 파란색 아이콘
        ),
      ),
    );
  }
}

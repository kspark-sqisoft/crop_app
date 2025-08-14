import 'dart:convert';
import 'dart:io';
import 'crop_region.dart';

typedef ProgressCallback =
    void Function(
      String regionName,
      double progress,
      double totalProgress,
      String eta,
    );

typedef RegionCompleteCallback = void Function(String regionName);
typedef AllCompleteCallback = void Function();

enum MediaType { image, video, unknown }

class FFMpegCropService {
  final String ffmpegPath;
  final String inputMedia;
  final String outputDir;

  double _videoDuration = 0.0;
  DateTime? _startTime;
  final Map<String, double> _progressMap = {};
  MediaType _mediaType = MediaType.unknown;

  FFMpegCropService({
    required this.ffmpegPath,
    required this.inputMedia,
    required this.outputDir,
  });

  /// 미디어 타입을 감지합니다
  Future<MediaType> _detectMediaType() async {
    try {
      print('미디어 타입 감지 시작: $inputMedia');
      final result = await Process.run(ffmpegPath, ['-i', inputMedia]);
      final stderr = result.stderr.toString().toLowerCase();
      print('FFmpeg 출력 (소문자): $stderr');

      // 이미지 포맷 감지
      if (stderr.contains('image2') ||
          stderr.contains('mjpeg') ||
          stderr.contains('png') ||
          stderr.contains('jpeg') ||
          stderr.contains('bmp') ||
          stderr.contains('gif')) {
        print('이미지로 감지됨');
        return MediaType.image;
      }

      // 비디오 포맷 감지
      if (stderr.contains('video:') ||
          stderr.contains('duration:') ||
          stderr.contains('time=')) {
        print('비디오로 감지됨');
        return MediaType.video;
      }

      // 파일 확장자로 판단
      final extension = inputMedia.split('.').last.toLowerCase();
      print('파일 확장자: $extension');

      if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension)) {
        print('확장자로 이미지로 감지됨');
        return MediaType.image;
      } else if ([
        'mp4',
        'avi',
        'mov',
        'mkv',
        'wmv',
        'flv',
        'webm',
      ].contains(extension)) {
        print('확장자로 비디오로 감지됨');
        return MediaType.video;
      }

      print('미디어 타입을 감지할 수 없음');
      return MediaType.unknown;
    } catch (e) {
      print('미디어 타입 감지 실패: $e');
      return MediaType.unknown;
    }
  }

  /// 비디오 길이를 가져옵니다
  Future<double> _getVideoDuration() async {
    try {
      print('비디오 길이 확인 시작: $inputMedia');
      final result = await Process.run(ffmpegPath, ['-i', inputMedia]);
      print('FFmpeg 정보 출력: ${result.stderr}');

      final regex = RegExp(r'Duration: (\d+):(\d+):(\d+\.\d+)');
      final match = regex.firstMatch(result.stderr);
      if (match != null) {
        final hours = double.parse(match.group(1)!);
        final minutes = double.parse(match.group(2)!);
        final seconds = double.parse(match.group(3)!);
        final duration = hours * 3600 + minutes * 60 + seconds;
        print('비디오 길이 확인 완료: $duration초 ($hours:$minutes:$seconds)');
        return duration;
      }

      print('비디오 길이를 찾을 수 없습니다. stderr: ${result.stderr}');
      return 0.0;
    } catch (e) {
      print('비디오 길이 확인 실패: $e');
      return 0.0;
    }
  }

  double _parseTimeToSeconds(String timeStr) {
    final parts = timeStr.split(':');
    final hours = double.parse(parts[0]);
    final minutes = double.parse(parts[1]);
    final seconds = double.parse(parts[2]);
    return hours * 3600 + minutes * 60 + seconds;
  }

  String _formatSeconds(double seconds) {
    final int sec = seconds.round();
    final int h = sec ~/ 3600;
    final int m = (sec % 3600) ~/ 60;
    final int s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
  }

  /// 이미지 크롭을 실행합니다
  Future<int> _runImageCrop(
    CropRegion region,
    ProgressCallback onProgress,
    RegionCompleteCallback onRegionComplete,
  ) async {
    final extension = inputMedia.split('.').last.toLowerCase();
    final outputImage = '$outputDir/${region.name}.$extension';

    final args = [
      '-y',
      '-i',
      inputMedia,
      '-filter:v',
      'crop=${region.width.toInt()}:${region.height.toInt()}:${region.x.toInt()}:${region.y.toInt()}',
      outputImage,
    ];

    try {
      print('이미지 크롭 실행: $ffmpegPath ${args.join(' ')}');

      final process = await Process.start(ffmpegPath, args);

      // FFmpeg 출력을 모니터링
      process.stderr.transform(utf8.decoder).listen((data) {
        print('FFmpeg stderr: $data');
      });

      process.stdout.transform(utf8.decoder).listen((data) {
        print('FFmpeg stdout: $data');
      });

      // 이미지는 즉시 완료되므로 진행률을 바로 100%로 설정
      _progressMap[region.name] = 1.0;
      double totalProgress =
          _progressMap.values.fold(0.0, (a, b) => a + b) / _progressMap.length;

      onProgress(region.name, 1.0, totalProgress, "00:00");

      final exitCode = await process.exitCode;
      print('이미지 크롭 완료, exitCode: $exitCode');

      if (exitCode == 0) {
        onRegionComplete(region.name);
      }
      return exitCode;
    } catch (e) {
      print('이미지 크롭 실패: $e');
      return -1;
    }
  }

  /// 비디오 크롭을 실행합니다
  Future<int> _runVideoCrop(
    CropRegion region,
    ProgressCallback onProgress,
    RegionCompleteCallback onRegionComplete,
  ) async {
    // 원본 파일의 확장자 가져오기
    final extension = inputMedia.split('.').last.toLowerCase();
    final outputVideo = '$outputDir/${region.name}.$extension';

    final args = [
      '-y',
      '-i',
      inputMedia,
      '-filter:v',
      'crop=${region.width.toInt()}:${region.height.toInt()}:${region.x.toInt()}:${region.y.toInt()}',
      '-c:v', 'libx264', // 비디오 코덱 명시
      '-preset', 'medium', // 인코딩 품질 설정
      '-crf', '23', // 품질 설정 (낮을수록 고품질)
      outputVideo,
    ];

    try {
      print('비디오 크롭 실행: $ffmpegPath ${args.join(' ')}');

      final process = await Process.start(ffmpegPath, args);

      // FFmpeg 출력을 모니터링
      process.stderr.transform(utf8.decoder).listen((data) {
        print('FFmpeg stderr: $data');
      });

      process.stdout.transform(utf8.decoder).listen((data) {
        print('FFmpeg stdout: $data');
      });

      // 비디오 진행률 모니터링
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            print('FFmpeg line: $line');

            // 시간 정보 추출 (여러 형식 지원)
            RegExp? timeRegex;
            if (line.contains('time=')) {
              timeRegex = RegExp(r'time=(\d+:\d+:\d+\.\d+)');
            } else if (line.contains('frame=')) {
              // frame 기반 진행률도 지원
              final frameMatch = RegExp(r'frame=\s*(\d+)').firstMatch(line);
              if (frameMatch != null && _videoDuration > 0) {
                // 프레임 기반 진행률 계산 (대략적)
                final currentFrame = int.parse(frameMatch.group(1)!);
                final totalFrames = (_videoDuration * 30).round(); // 30fps 가정
                final progress = (currentFrame / totalFrames).clamp(0.0, 1.0);

                _progressMap[region.name] = progress;
                double totalProgress =
                    _progressMap.values.fold(0.0, (a, b) => a + b) /
                    _progressMap.length;

                String eta = "";
                if (_startTime != null && totalProgress > 0) {
                  final elapsed = DateTime.now()
                      .difference(_startTime!)
                      .inSeconds;
                  final estimatedTotal = elapsed / totalProgress;
                  final remaining = estimatedTotal - elapsed;
                  eta = _formatSeconds(remaining);
                }

                onProgress(region.name, progress, totalProgress, eta);
              }
              return;
            }

            if (timeRegex != null) {
              final timeMatch = timeRegex.firstMatch(line);
              if (timeMatch != null && _videoDuration > 0) {
                final currentTime = _parseTimeToSeconds(timeMatch.group(1)!);
                final progress = (currentTime / _videoDuration).clamp(0.0, 1.0);

                _progressMap[region.name] = progress;
                double totalProgress =
                    _progressMap.values.fold(0.0, (a, b) => a + b) /
                    _progressMap.length;

                String eta = "";
                if (_startTime != null && totalProgress > 0) {
                  final elapsed = DateTime.now()
                      .difference(_startTime!)
                      .inSeconds;
                  final estimatedTotal = elapsed / totalProgress;
                  final remaining = estimatedTotal - elapsed;
                  eta = _formatSeconds(remaining);
                }

                onProgress(region.name, progress, totalProgress, eta);
              }
            }
          });

      final exitCode = await process.exitCode;
      print('비디오 크롭 완료, exitCode: $exitCode');

      if (exitCode == 0) {
        _progressMap[region.name] = 1.0;
        double totalProgress =
            _progressMap.values.fold(0.0, (a, b) => a + b) /
            _progressMap.length;

        onProgress(region.name, 1.0, totalProgress, "00:00");
        onRegionComplete(region.name);
      }
      return exitCode;
    } catch (e) {
      print('비디오 크롭 실패: $e');
      return -1;
    }
  }

  /// 병렬로 크롭을 실행합니다
  Future<void> runParallel({
    required List<CropRegion> regions,
    required ProgressCallback onProgress,
    required RegionCompleteCallback onRegionComplete,
    required AllCompleteCallback onAllComplete,
  }) async {
    // 미디어 타입 감지
    _mediaType = await _detectMediaType();
    if (_mediaType == MediaType.unknown) {
      throw Exception("지원하지 않는 미디어 타입입니다");
    }

    // 비디오인 경우 길이 확인
    if (_mediaType == MediaType.video) {
      _videoDuration = await _getVideoDuration();
      if (_videoDuration == 0) {
        throw Exception("비디오 길이 확인 실패");
      }
    }

    _progressMap.clear();
    for (var region in regions) {
      _progressMap[region.name] = 0.0;
    }
    _startTime = DateTime.now();

    List<Future<int>> futures = [];
    for (var region in regions) {
      if (_mediaType == MediaType.image) {
        futures.add(_runImageCrop(region, onProgress, onRegionComplete));
      } else {
        futures.add(_runVideoCrop(region, onProgress, onRegionComplete));
      }
    }

    await Future.wait(futures);
    onAllComplete();
  }

  /// 단일 크롭을 실행합니다 (하위 호환성을 위해 유지)
  Future<int> _runSingleCrop(
    CropRegion region,
    ProgressCallback onProgress,
    RegionCompleteCallback onRegionComplete,
  ) async {
    if (_mediaType == MediaType.image) {
      return await _runImageCrop(region, onProgress, onRegionComplete);
    } else {
      return await _runVideoCrop(region, onProgress, onRegionComplete);
    }
  }

  /// 미디어 타입을 반환합니다
  MediaType get mediaType => _mediaType;

  /// 비디오 길이를 반환합니다 (비디오인 경우에만 유효)
  double get videoDuration => _videoDuration;
}

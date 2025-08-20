import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'crop_region.dart';
import 'package:flutter/foundation.dart';

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
      final stderr = result.stderr.toString();
      print('FFmpeg 원본 출력: $stderr');

      final stderrLower = stderr.toLowerCase();
      print('FFmpeg 출력 (소문자): $stderrLower');

      // 파일 확장자로 먼저 판단 (더 신뢰할 수 있는 방법)
      final extension = inputMedia.split('.').last.toLowerCase();
      print('파일 확장자: $extension');

      if ([
        'jpg',
        'jpeg',
        'png',
        'gif',
        'bmp',
        'webp',
        'tiff',
        'tga',
      ].contains(extension)) {
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
        'm4v',
        '3gp',
        'ts',
        'mts',
        'm2ts',
      ].contains(extension)) {
        print('확장자로 비디오로 감지됨');
        return MediaType.video;
      }

      // FFmpeg 출력 기반 감지 (백업 방법)
      // 비디오 포맷 감지
      if (stderrLower.contains('stream #0:0: video') ||
          stderrLower.contains('video:') && stderrLower.contains('stream') ||
          stderrLower.contains('duration:') && stderrLower.contains('video:')) {
        print('비디오로 감지됨 (FFmpeg 출력 기반)');
        return MediaType.video;
      }

      // 이미지 포맷 감지
      if (stderrLower.contains('image2') ||
          stderrLower.contains('mjpeg') ||
          stderrLower.contains('png') ||
          stderrLower.contains('jpeg') ||
          stderrLower.contains('bmp') ||
          stderrLower.contains('gif') ||
          stderrLower.contains('image:') ||
          stderrLower.contains('image ')) {
        print('이미지로 감지됨 (FFmpeg 출력 기반)');
        return MediaType.image;
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
      '-vf',
      'crop=${region.width.toInt()}:${region.height.toInt()}:${region.x.toInt()}:${region.y.toInt()}',
      outputImage,
    ];

    try {
      print('이미지 크롭 실행: $ffmpegPath ${args.join(' ')}');

      // 이미지 크롭 시작 시 0%로 설정
      _progressMap[region.name] = 0.0;
      double totalProgress =
          _progressMap.values.fold(0.0, (a, b) => a + b) / _progressMap.length;
      onProgress(region.name, 0.0, totalProgress, "00:00");
      print('이미지 크롭 시작: ${region.name} - 0%');

      // 이미지 크롭 진행률 시뮬레이션
      await Future.delayed(Duration(milliseconds: 100));
      _progressMap[region.name] = 0.5;
      totalProgress =
          _progressMap.values.fold(0.0, (a, b) => a + b) / _progressMap.length;
      onProgress(region.name, 0.5, totalProgress, "00:00");
      print('이미지 크롭 진행 중: ${region.name} - 50%');

      // FFmpeg 실행 (동기 방식으로 변경)
      print('FFmpeg 실행 중...');
      final result = await Process.run(ffmpegPath, args);
      final exitCode = result.exitCode;
      print('FFmpeg 실행 완료, exitCode: $exitCode');
      print('FFmpeg stderr: ${result.stderr}');
      print('FFmpeg stdout: ${result.stdout}');
      print('이미지 크롭 완료, exitCode: $exitCode, 출력 파일: $outputImage');

      if (exitCode == 0) {
        // 출력 파일 존재 여부 확인
        final outputFile = File(outputImage);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          print('이미지 크롭 성공: $outputImage (크기: $fileSize bytes)');

          // 크롭 완료 후 진행률을 100%로 설정
          _progressMap[region.name] = 1.0;
          totalProgress =
              _progressMap.values.fold(0.0, (a, b) => a + b) /
              _progressMap.length;
          onProgress(region.name, 1.0, totalProgress, "00:00");
        } else {
          print('경고: 출력 파일이 생성되지 않음: $outputImage');
        }

        // 크롭 완료 신호 전송 (성공/실패 상관없이)
        print('이미지 크롭 완료 신호 전송: ${region.name}');
        onRegionComplete(region.name);
      } else {
        print('이미지 크롭 실패: exitCode $exitCode');
      }
      return exitCode;
    } catch (e) {
      print('이미지 크롭 실패: $e');
      return -1;
    }
  }

  /// 비디오 크롭을 실행합니다 (진행률 모니터링 포함)
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

      // 비디오 크롭 시작 시 0%로 설정
      _progressMap[region.name] = 0.0;
      double totalProgress =
          _progressMap.values.fold(0.0, (a, b) => a + b) / _progressMap.length;
      onProgress(region.name, 0.0, totalProgress, "00:00");

      // FFmpeg를 메인 스레드에서 실행하되, 진행률을 실시간으로 모니터링
      final process = await Process.start(ffmpegPath, args);

      // 진행률 모니터링을 위한 변수들
      double lastProgress = 0.0;
      final startTime = _startTime ?? DateTime.now();

      // stderr 스트림 모니터링 (진행률 파싱)
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // 시간 정보 추출 (time= 형식)
            final timeMatch = RegExp(
              r'time=(\d+:\d+:\d+\.\d+)',
            ).firstMatch(line);
            if (timeMatch != null && _videoDuration > 0) {
              final currentTime = _parseTimeToSecondsStatic(
                timeMatch.group(1)!,
              );
              final progress = (currentTime / _videoDuration).clamp(0.0, 1.0);

              // 진행률이 이전보다 증가한 경우에만 UI 업데이트
              if (progress > lastProgress) {
                lastProgress = progress;
                _progressMap[region.name] = progress;
                totalProgress =
                    _progressMap.values.fold(0.0, (a, b) => a + b) /
                    _progressMap.length;

                // UI 업데이트를 메인 스레드에서 실행
                onProgress(region.name, progress, totalProgress, "00:00");
                print(
                  '비디오 크롭 진행률 UI 업데이트: ${region.name} - ${(progress * 100).toStringAsFixed(1)}%',
                );
              }
            }
          });

      // 프로세스 완료 대기
      final exitCode = await process.exitCode;

      print('비디오 크롭 완료: ${region.name}, exitCode: $exitCode');

      if (exitCode == 0) {
        // 출력 파일 존재 여부 확인
        final outputFile = File(outputVideo);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          print('비디오 크롭 성공: $outputVideo (크기: $fileSize bytes)');
        } else {
          print('경고: 출력 파일이 생성되지 않음: $outputVideo');
        }

        _progressMap[region.name] = 1.0;
        double totalProgress =
            _progressMap.values.fold(0.0, (a, b) => a + b) /
            _progressMap.length;

        onProgress(region.name, 1.0, totalProgress, "00:00");
        onRegionComplete(region.name);
      } else {
        print('비디오 크롭 실패: exitCode $exitCode');
      }

      return exitCode;
    } catch (e) {
      print('비디오 크롭 실패: $e');
      return -1;
    }
  }

  /// 정적 함수로 시간 파싱 (별도 스레드에서 사용)
  static double _parseTimeToSecondsStatic(String timeStr) {
    final parts = timeStr.split(':');
    final hours = double.parse(parts[0]);
    final minutes = double.parse(parts[1]);
    final seconds = double.parse(parts[2]);
    return hours * 3600 + minutes * 60 + seconds;
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

    // 초기 진행률을 모든 영역에 대해 0%로 설정
    for (var region in regions) {
      double totalProgress =
          _progressMap.values.fold(0.0, (a, b) => a + b) / regions.length;
      onProgress(region.name, 0.0, totalProgress, "00:00");
    }

    List<Future<int>> futures = [];
    for (var region in regions) {
      if (_mediaType == MediaType.image) {
        futures.add(_runImageCrop(region, onProgress, onRegionComplete));
      } else {
        futures.add(_runVideoCrop(region, onProgress, onRegionComplete));
      }
    }

    print('모든 크롭 작업 완료 대기 중...');
    await Future.wait(futures);
    print('모든 크롭 작업 완료됨. 전체 완료 신호 전송');
    onAllComplete();
  }

  /// 미디어 타입을 반환합니다
  MediaType get mediaType => _mediaType;

  /// 비디오 길이를 반환합니다 (비디오인 경우에만 유효)
  double get videoDuration => _videoDuration;
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/photo/data/services/face_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// 人脸识别服务
/// 负责人脸检测、特征提取和聚类分组
class FaceRecognitionService {
  factory FaceRecognitionService() => _instance ??= FaceRecognitionService._();
  FaceRecognitionService._();

  static FaceRecognitionService? _instance;

  final FaceDatabaseService _faceDb = FaceDatabaseService();
  final PhotoDatabaseService _photoDb = PhotoDatabaseService();

  // TFLite 模型
  Interpreter? _faceDetector;
  Interpreter? _faceEmbedder;

  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _shouldCancel = false;

  // 模型配置
  static const int _detectorInputSize = 128; // BlazeFace 输入尺寸
  static const int _embedderInputSize = 112; // MobileFaceNet 输入尺寸
  static const int _embeddingSize = 128; // 特征向量维度
  static const int _maxImageBytes = 30 * 1024 * 1024;

  // 进度流
  final _progressController = StreamController<FaceProcessProgress>.broadcast();
  Stream<FaceProcessProgress> get progressStream => _progressController.stream;

  bool get isProcessing => _isProcessing;

  /// 初始化服务
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      await _faceDb.init();
      await _loadModels();
      _isInitialized = true;
      logger.i('FaceRecognitionService: 初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'FaceRecognitionService.init');
      rethrow;
    }
  }

  /// 加载 TFLite 模型
  Future<void> _loadModels() async {
    try {
      // 获取模型文件路径
      final modelDir = await _getModelDirectory();

      // 检查模型文件是否存在，不存在则从 assets 复制
      await _ensureModelExists(modelDir, 'blazeface.tflite');
      await _ensureModelExists(modelDir, 'mobilefacenet.tflite');

      final detectorPath = '${modelDir.path}/blazeface.tflite';
      final embedderPath = '${modelDir.path}/mobilefacenet.tflite';

      // 加载人脸检测模型
      if (await File(detectorPath).exists()) {
        _faceDetector = Interpreter.fromFile(File(detectorPath));
        logger.i('FaceRecognitionService: 人脸检测模型加载成功');
      }

      // 加载人脸特征提取模型
      if (await File(embedderPath).exists()) {
        _faceEmbedder = Interpreter.fromFile(File(embedderPath));
        logger.i('FaceRecognitionService: 人脸特征模型加载成功');
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '模型加载失败，将使用备用方案');
    }
  }

  Future<Directory> _getModelDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${appDir.path}/ml_models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  Future<void> _ensureModelExists(Directory modelDir, String modelName) async {
    final modelFile = File('${modelDir.path}/$modelName');
    if (!await modelFile.exists()) {
      try {
        // 尝试从 assets 复制
        final data = await rootBundle.load('assets/ml_models/$modelName');
        await modelFile.writeAsBytes(data.buffer.asUint8List());
        logger.i('FaceRecognitionService: 模型 $modelName 复制成功');
      } on Exception {
        logger.w('FaceRecognitionService: 模型 $modelName 不存在，需要手动下载');
      }
    }
  }

  /// 处理所有照片，检测人脸并提取特征
  Future<void> processAllPhotos(
    NasFileSystem fileSystem, {
    int batchSize = 10,
  }) async {
    if (_isProcessing) {
      logger.w('FaceRecognitionService: 已有任务在处理中');
      return;
    }

    if (!_isInitialized) await init();

    _isProcessing = true;
    _shouldCancel = false;

    try {
      // 获取所有照片
      final photos = await _photoDb.getAll();
      final total = photos.length;
      var processed = 0;
      var facesFound = 0;

      _progressController.add(
        FaceProcessProgress(
          processed: 0,
          total: total,
          facesFound: 0,
          status: FaceProcessStatus.processing,
        ),
      );

      for (final photo in photos) {
        if (_shouldCancel) break;

        // 检查是否已处理
        if (await _faceDb.isPhotoProcessed(photo.sourceId, photo.filePath)) {
          processed++;
          continue;
        }

        try {
          // 读取照片
          final stream = await fileSystem.getFileStream(photo.filePath);
          final chunks = <List<int>>[];
          var totalBytes = 0;
          var tooLarge = false;
          await for (final chunk in stream) {
            totalBytes += chunk.length;
            if (totalBytes > _maxImageBytes) {
              tooLarge = true;
              break;
            }
            chunks.add(chunk);
          }
          if (tooLarge) {
            logger.w('FaceRecognitionService: 图片过大，跳过 ${photo.filePath}');
            processed++;
            continue;
          }
          final bytes = Uint8List.fromList(chunks.expand((c) => c).toList());

          if (bytes.isEmpty) {
            processed++;
            continue;
          }

          // 检测人脸并提取特征
          final faces = await _processImage(
            bytes,
            photo.sourceId,
            photo.filePath,
          );

          if (faces.isNotEmpty) {
            await _faceDb.insertFacesBatch(faces);
            facesFound += faces.length;
          }
        } on Exception catch (e, st) {
          AppError.ignore(e, st, '处理照片失败: ${photo.filePath}');
        }

        processed++;
        _progressController.add(
          FaceProcessProgress(
            processed: processed,
            total: total,
            facesFound: facesFound,
            currentFile: photo.fileName,
            status: FaceProcessStatus.processing,
          ),
        );
      }

      _progressController.add(
        FaceProcessProgress(
          processed: processed,
          total: total,
          facesFound: facesFound,
          status: _shouldCancel
              ? FaceProcessStatus.cancelled
              : FaceProcessStatus.completed,
        ),
      );

      logger.i('FaceRecognitionService: 处理完成，共发现 $facesFound 张人脸');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'FaceRecognitionService.processAllPhotos');
      _progressController.add(
        FaceProcessProgress(
          processed: 0,
          total: 0,
          facesFound: 0,
          status: FaceProcessStatus.error,
          error: e.toString(),
        ),
      );
    } finally {
      _isProcessing = false;
      _shouldCancel = false;
    }
  }

  /// 处理单张图片
  Future<List<FaceEntity>> _processImage(
    Uint8List imageBytes,
    String sourceId,
    String photoPath,
  ) async {
    if (imageBytes.length > _maxImageBytes) return [];

    // 解码图片。大图解码在 isolate 中完成，避免卡住 UI isolate。
    final image = await compute(_decodeFaceImage, imageBytes);
    if (image == null) return [];

    // 检测人脸
    final faceBoxes = await _detectFaces(image);
    if (faceBoxes.isEmpty) return [];

    final faces = <FaceEntity>[];

    for (final box in faceBoxes) {
      // 裁剪人脸区域
      final faceImage = _cropFace(image, box);
      if (faceImage == null) continue;

      // 提取特征向量
      final embedding = await _extractEmbedding(faceImage);
      if (embedding == null) continue;

      faces.add(
        FaceEntity(
          id: 0,
          photoSourceId: sourceId,
          photoPath: photoPath,
          faceBox: box,
          embedding: embedding,
          confidence: box.score,
        ),
      );
    }

    return faces;
  }

  /// 检测人脸
  Future<List<FaceBox>> _detectFaces(img.Image image) async {
    if (_faceDetector == null) {
      // 使用简单的备用方案：基于肤色检测
      return _detectFacesFallback(image);
    }

    try {
      // 预处理图片
      final resized = img.copyResize(
        image,
        width: _detectorInputSize,
        height: _detectorInputSize,
      );

      // 准备输入数据
      final input = _imageToFloat32List(resized);
      final inputShape = [1, _detectorInputSize, _detectorInputSize, 3];
      final inputTensor = input.reshape<double>(inputShape);

      // 准备输出
      final outputBoxes = List.filled(
        1 * 896 * 16,
        0.0,
      ).reshape<double>([1, 896, 16]);
      final outputScores = List.filled(
        1 * 896 * 1,
        0.0,
      ).reshape<double>([1, 896, 1]);

      // 运行推理
      _faceDetector!.runForMultipleInputs(
        [inputTensor],
        {0: outputBoxes, 1: outputScores},
      );

      // 解析结果
      return _parseDetectorOutput(
        outputBoxes as List<List<List<double>>>,
        outputScores as List<List<List<double>>>,
        image.width,
        image.height,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '人脸检测失败，使用备用方案');
      return _detectFacesFallback(image);
    }
  }

  /// 人脸检测模型不可用时的回退
  ///
  /// 不再伪造人脸框（旧实现假设图片中心上半部有一张脸，会导致错误的人脸
  /// 检测与聚类结果）。模型缺失时返回空列表，表示“无法检测”，调用方会跳过
  /// 该图，不会把假人脸写入数据库。
  List<FaceBox> _detectFacesFallback(img.Image image) {
    logger.w('FaceRecognitionService: 人脸检测模型不可用，跳过人脸检测');
    return const [];
  }

  List<FaceBox> _parseDetectorOutput(
    List<List<List<double>>> boxes,
    List<List<List<double>>> scores,
    int imageWidth,
    int imageHeight,
  ) {
    final faceBoxes = <FaceBox>[];
    const threshold = 0.5;

    for (var i = 0; i < scores[0].length; i++) {
      final score = scores[0][i][0];
      if (score > threshold) {
        final box = boxes[0][i];
        // BlazeFace 输出格式: [ymin, xmin, ymax, xmax, ...]
        final yMin = box[0] * imageHeight;
        final xMin = box[1] * imageWidth;
        final yMax = box[2] * imageHeight;
        final xMax = box[3] * imageWidth;

        faceBoxes.add(
          FaceBox(
            x: xMin,
            y: yMin,
            width: xMax - xMin,
            height: yMax - yMin,
            score: score,
          ),
        );
      }
    }

    // 非极大值抑制
    return _nonMaxSuppression(faceBoxes, 0.3);
  }

  List<FaceBox> _nonMaxSuppression(List<FaceBox> boxes, double iouThreshold) {
    if (boxes.isEmpty) return [];

    // 按面积排序
    boxes.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));

    final selected = <FaceBox>[];
    final active = List.filled(boxes.length, true);

    for (var i = 0; i < boxes.length; i++) {
      if (!active[i]) continue;

      selected.add(boxes[i]);

      for (var j = i + 1; j < boxes.length; j++) {
        if (!active[j]) continue;

        final iou = _calculateIoU(boxes[i], boxes[j]);
        if (iou > iouThreshold) {
          active[j] = false;
        }
      }
    }

    return selected;
  }

  double _calculateIoU(FaceBox a, FaceBox b) {
    final xA = math.max(a.x, b.x);
    final yA = math.max(a.y, b.y);
    final xB = math.min(a.x + a.width, b.x + b.width);
    final yB = math.min(a.y + a.height, b.y + b.height);

    final intersection = math.max(0, xB - xA) * math.max(0, yB - yA);
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;

    return intersection / (areaA + areaB - intersection);
  }

  /// 裁剪人脸区域
  img.Image? _cropFace(img.Image image, FaceBox box) {
    try {
      // 扩大裁剪区域以包含更多上下文
      final padding = box.width * 0.2;
      final x = math.max(0, box.x - padding).toInt();
      final y = math.max(0, box.y - padding).toInt();
      final w = math.min(image.width - x, box.width + padding * 2).toInt();
      final h = math.min(image.height - y, box.height + padding * 2).toInt();

      if (w <= 0 || h <= 0) return null;

      final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);

      // 调整到模型输入尺寸
      return img.copyResize(
        cropped,
        width: _embedderInputSize,
        height: _embedderInputSize,
      );
    } on Exception {
      return null;
    }
  }

  /// 提取人脸特征向量
  Future<Float32List?> _extractEmbedding(img.Image faceImage) async {
    if (_faceEmbedder == null) {
      return _extractEmbeddingFallback(faceImage);
    }

    try {
      // 预处理
      final input = _imageToFloat32List(faceImage, normalize: true);
      final inputShape = [1, _embedderInputSize, _embedderInputSize, 3];
      final inputTensor = input.reshape<double>(inputShape);

      // 准备输出
      final output = List.filled(
        1 * _embeddingSize,
        0.0,
      ).reshape<double>([1, _embeddingSize]);

      // 运行推理
      _faceEmbedder!.run(inputTensor, output);

      // 提取结果并 L2 归一化
      final embedding = Float32List(_embeddingSize);
      var norm = 0.0;
      for (var i = 0; i < _embeddingSize; i++) {
        embedding[i] = (output[0] as List<double>)[i];
        norm += embedding[i] * embedding[i];
      }
      norm = math.sqrt(norm);
      for (var i = 0; i < _embeddingSize; i++) {
        embedding[i] /= norm;
      }

      return embedding;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '特征提取失败，使用备用方案');
      return _extractEmbeddingFallback(faceImage);
    }
  }

  /// 人脸特征提取模型不可用时的回退
  ///
  /// 不再用图像统计量伪造特征向量（旧实现会产出无意义的 embedding，导致错误
  /// 聚类）。模型缺失时返回 null，调用方会跳过该人脸，不写入数据库。
  Float32List? _extractEmbeddingFallback(img.Image image) {
    logger.w('FaceRecognitionService: 人脸特征模型不可用，跳过特征提取');
    return null;
  }

  List<double> _imageToFloat32List(img.Image image, {bool normalize = false}) {
    final result = <double>[];
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        if (normalize) {
          // 归一化到 [-1, 1]
          result
            ..add((pixel.r / 127.5) - 1.0)
            ..add((pixel.g / 127.5) - 1.0)
            ..add((pixel.b / 127.5) - 1.0);
        } else {
          // 归一化到 [0, 1]
          result
            ..add(pixel.r / 255.0)
            ..add(pixel.g / 255.0)
            ..add(pixel.b / 255.0);
        }
      }
    }
    return result;
  }

  /// 对所有人脸进行聚类分组
  Future<int> clusterFaces({double threshold = 0.6}) async {
    if (!_isInitialized) await init();

    logger.i('FaceRecognitionService: 开始人脸聚类，阈值=$threshold');

    final faces = await _faceDb.getAllFaces();
    if (faces.isEmpty) return 0;

    // 使用贪心聚类算法
    final assignments = <int, int>{}; // faceId -> personId
    final personEmbeddings =
        <int, List<Float32List>>{}; // personId -> embeddings

    for (final face in faces) {
      if (face.personId != null) {
        // 已分配的人脸，添加到对应人物的特征列表
        personEmbeddings
            .putIfAbsent(face.personId!, () => [])
            .add(face.embedding);
        continue;
      }

      // 找到最相似的人物
      var bestPersonId = -1;
      var bestSimilarity = 0.0;

      for (final entry in personEmbeddings.entries) {
        final personId = entry.key;
        final embeddings = entry.value;

        // 计算与该人物所有人脸的平均相似度
        var totalSimilarity = 0.0;
        for (final emb in embeddings) {
          totalSimilarity += _cosineSimilarity(face.embedding, emb);
        }
        final avgSimilarity = totalSimilarity / embeddings.length;

        if (avgSimilarity > bestSimilarity) {
          bestSimilarity = avgSimilarity;
          bestPersonId = personId;
        }
      }

      if (bestSimilarity >= threshold && bestPersonId >= 0) {
        // 归入现有人物
        assignments[face.id] = bestPersonId;
        personEmbeddings[bestPersonId]!.add(face.embedding);
      } else {
        // 创建新人物
        final personId = await _faceDb.createPerson();
        assignments[face.id] = personId;
        personEmbeddings[personId] = [face.embedding];
      }
    }

    // 批量更新数据库
    for (final entry in assignments.entries) {
      await _faceDb.updateFacePersonId(entry.key, entry.value);
    }

    // 更新所有人物的统计信息和代表头像
    for (final personId in personEmbeddings.keys) {
      await _faceDb.updatePersonStats(personId);

      // 设置第一张人脸为代表头像
      final personFaces = await _faceDb.getFacesByPersonId(personId);
      if (personFaces.isNotEmpty) {
        await _faceDb.setRepresentativeFace(personId, personFaces.first.id);
      }
    }

    final personCount = personEmbeddings.length;
    logger.i('FaceRecognitionService: 聚类完成，共 $personCount 个人物');

    return personCount;
  }

  /// 计算余弦相似度
  double _cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    return denominator > 0 ? dotProduct / denominator : 0.0;
  }

  /// 取消处理
  void cancel() {
    _shouldCancel = true;
  }

  /// 释放资源
  void dispose() {
    _faceDetector?.close();
    _faceEmbedder?.close();
    _progressController.close();
  }
}

/// 人脸处理进度
class FaceProcessProgress {
  const FaceProcessProgress({
    required this.processed,
    required this.total,
    required this.facesFound,
    required this.status,
    this.currentFile,
    this.error,
  });

  final int processed;
  final int total;
  final int facesFound;
  final FaceProcessStatus status;
  final String? currentFile;
  final String? error;

  double get progress => total > 0 ? processed / total : 0;
}

/// 处理状态
enum FaceProcessStatus { idle, processing, completed, cancelled, error }

img.Image? _decodeFaceImage(Uint8List imageBytes) =>
    img.decodeImage(imageBytes);

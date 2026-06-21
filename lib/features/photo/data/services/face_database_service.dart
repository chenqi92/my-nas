import 'dart:convert';
import 'dart:typed_data';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 人脸实体
class FaceEntity {
  const FaceEntity({
    required this.id,
    required this.photoSourceId,
    required this.photoPath,
    required this.faceBox,
    required this.embedding,
    this.personId,
    this.confidence = 0.0,
    this.createdAt,
  });

  final int id;
  final String photoSourceId;
  final String photoPath;
  final FaceBox faceBox; // 人脸在图片中的位置
  final Float32List embedding; // 128维特征向量
  final int? personId; // 归属的人物ID
  final double confidence; // 检测置信度
  final DateTime? createdAt;

  String get uniqueKey => '${photoSourceId}_$photoPath';

  FaceEntity copyWith({
    int? id,
    String? photoSourceId,
    String? photoPath,
    FaceBox? faceBox,
    Float32List? embedding,
    int? personId,
    double? confidence,
    DateTime? createdAt,
  }) =>
      FaceEntity(
        id: id ?? this.id,
        photoSourceId: photoSourceId ?? this.photoSourceId,
        photoPath: photoPath ?? this.photoPath,
        faceBox: faceBox ?? this.faceBox,
        embedding: embedding ?? this.embedding,
        personId: personId ?? this.personId,
        confidence: confidence ?? this.confidence,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// 人脸位置
class FaceBox {
  const FaceBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory FaceBox.fromJson(Map<String, dynamic> json) => FaceBox(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
      );

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  @override
  String toString() => 'FaceBox($x, $y, $width, $height)';
}

/// 人物实体
class PersonEntity {
  const PersonEntity({
    required this.id,
    this.name,
    this.representativeFaceId,
    this.faceCount = 0,
    this.photoCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String? name; // 用户命名（可选）
  final int? representativeFaceId; // 代表性头像的 face id
  final int faceCount; // 人脸数量
  final int photoCount; // 照片数量
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// 显示名称
  String get displayName => name ?? appL10n.facePersonDisplayNameUnnamed(id);

  PersonEntity copyWith({
    int? id,
    String? name,
    int? representativeFaceId,
    int? faceCount,
    int? photoCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      PersonEntity(
        id: id ?? this.id,
        name: name ?? this.name,
        representativeFaceId: representativeFaceId ?? this.representativeFaceId,
        faceCount: faceCount ?? this.faceCount,
        photoCount: photoCount ?? this.photoCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// 人脸数据库服务
class FaceDatabaseService {
  factory FaceDatabaseService() => _instance ??= FaceDatabaseService._();
  FaceDatabaseService._();

  static FaceDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  static const String _tableFaces = 'faces';
  static const String _tablePersons = 'persons';

  // faces 表字段
  static const String _colId = 'id';
  static const String _colPhotoSourceId = 'photo_source_id';
  static const String _colPhotoPath = 'photo_path';
  static const String _colFaceBox = 'face_box';
  static const String _colEmbedding = 'embedding';
  static const String _colPersonId = 'person_id';
  static const String _colConfidence = 'confidence';
  static const String _colCreatedAt = 'created_at';

  // persons 表字段
  static const String _colName = 'name';
  static const String _colRepresentativeFaceId = 'representative_face_id';
  static const String _colFaceCount = 'face_count';
  static const String _colPhotoCount = 'photo_count';
  static const String _colUpdatedAt = 'updated_at';

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'face_recognition.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
        onConfigure: _onConfigure,
        onCreate: (db, version) async {
          // 创建人脸表
          await db.execute('''
            CREATE TABLE $_tableFaces (
              $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
              $_colPhotoSourceId TEXT NOT NULL,
              $_colPhotoPath TEXT NOT NULL,
              $_colFaceBox TEXT NOT NULL,
              $_colEmbedding BLOB NOT NULL,
              $_colPersonId INTEGER,
              $_colConfidence REAL DEFAULT 0,
              $_colCreatedAt INTEGER,
              FOREIGN KEY ($_colPersonId) REFERENCES $_tablePersons($_colId)
            )
          ''');

          // 创建人物表
          await db.execute('''
            CREATE TABLE $_tablePersons (
              $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
              $_colName TEXT,
              $_colRepresentativeFaceId INTEGER,
              $_colFaceCount INTEGER DEFAULT 0,
              $_colPhotoCount INTEGER DEFAULT 0,
              $_colCreatedAt INTEGER,
              $_colUpdatedAt INTEGER
            )
          ''');

          // 创建索引
          await db.execute(
              'CREATE INDEX idx_faces_photo ON $_tableFaces ($_colPhotoSourceId, $_colPhotoPath)');
          await db.execute(
              'CREATE INDEX idx_faces_person ON $_tableFaces ($_colPersonId)');
          await db.execute(
              'CREATE INDEX idx_persons_name ON $_tablePersons ($_colName)');
        },
      );

      _initialized = true;
      logger.i('FaceDatabaseService: 数据库初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'FaceDatabaseService.init');
      rethrow;
    }
  }

  Future<void> _onConfigure(Database db) async {
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.rawQuery('PRAGMA synchronous=NORMAL');
    await db.rawQuery('PRAGMA foreign_keys=ON');
  }

  // ==================== 人脸操作 ====================

  /// 插入人脸
  Future<int> insertFace(FaceEntity face) async {
    if (!_initialized) await init();

    return _db!.insert(_tableFaces, _faceToRow(face));
  }

  /// 批量插入人脸
  Future<void> insertFacesBatch(List<FaceEntity> faces) async {
    if (!_initialized) await init();
    if (faces.isEmpty) return;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final face in faces) {
        batch.insert(_tableFaces, _faceToRow(face));
      }
      await batch.commit(noResult: true);
    });
  }

  /// 更新人脸的人物归属
  Future<void> updateFacePersonId(int faceId, int personId) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableFaces,
      {_colPersonId: personId},
      where: '$_colId = ?',
      whereArgs: [faceId],
    );
  }

  /// 批量更新人脸的人物归属
  Future<void> updateFacesPersonId(List<int> faceIds, int personId) async {
    if (!_initialized) await init();
    if (faceIds.isEmpty) return;

    final placeholders = List.filled(faceIds.length, '?').join(',');
    await _db!.rawUpdate(
      'UPDATE $_tableFaces SET $_colPersonId = ? WHERE $_colId IN ($placeholders)',
      [personId, ...faceIds],
    );
  }

  /// 获取照片中的所有人脸
  Future<List<FaceEntity>> getFacesByPhoto(
      String sourceId, String photoPath) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableFaces,
      where: '$_colPhotoSourceId = ? AND $_colPhotoPath = ?',
      whereArgs: [sourceId, photoPath],
    );

    return results.map(_faceFromRow).toList();
  }

  /// 获取人物的所有人脸
  Future<List<FaceEntity>> getFacesByPersonId(int personId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableFaces,
      where: '$_colPersonId = ?',
      whereArgs: [personId],
      orderBy: '$_colCreatedAt DESC',
    );

    return results.map(_faceFromRow).toList();
  }

  /// 获取未分组的人脸
  Future<List<FaceEntity>> getUnassignedFaces({int limit = 100}) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableFaces,
      where: '$_colPersonId IS NULL',
      limit: limit,
    );

    return results.map(_faceFromRow).toList();
  }

  /// 获取所有人脸（用于聚类）
  Future<List<FaceEntity>> getAllFaces() async {
    if (!_initialized) await init();

    final results = await _db!.query(_tableFaces);
    return results.map(_faceFromRow).toList();
  }

  /// 检查照片是否已处理
  Future<bool> isPhotoProcessed(String sourceId, String photoPath) async {
    if (!_initialized) await init();

    final count = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableFaces WHERE $_colPhotoSourceId = ? AND $_colPhotoPath = ?',
      [sourceId, photoPath],
    ));

    return (count ?? 0) > 0;
  }

  /// 删除照片的所有人脸
  Future<void> deleteFacesByPhoto(String sourceId, String photoPath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableFaces,
      where: '$_colPhotoSourceId = ? AND $_colPhotoPath = ?',
      whereArgs: [sourceId, photoPath],
    );
  }

  // ==================== 人物操作 ====================

  /// 创建人物
  Future<int> createPerson({String? name}) async {
    if (!_initialized) await init();

    return _db!.insert(_tablePersons, {
      _colName: name,
      _colFaceCount: 0,
      _colPhotoCount: 0,
      _colCreatedAt: DateTime.now().millisecondsSinceEpoch,
      _colUpdatedAt: DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 更新人物名称
  Future<void> updatePersonName(int personId, String name) async {
    if (!_initialized) await init();

    await _db!.update(
      _tablePersons,
      {
        _colName: name,
        _colUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '$_colId = ?',
      whereArgs: [personId],
    );
  }

  /// 更新人物统计
  Future<void> updatePersonStats(int personId) async {
    if (!_initialized) await init();

    // 计算人脸数量
    final faceCount = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableFaces WHERE $_colPersonId = ?',
      [personId],
    )) ?? 0;

    // 计算照片数量（去重）
    final photoCount = Sqflite.firstIntValue(await _db!.rawQuery(
      'SELECT COUNT(DISTINCT $_colPhotoSourceId || $_colPhotoPath) FROM $_tableFaces WHERE $_colPersonId = ?',
      [personId],
    )) ?? 0;

    await _db!.update(
      _tablePersons,
      {
        _colFaceCount: faceCount,
        _colPhotoCount: photoCount,
        _colUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '$_colId = ?',
      whereArgs: [personId],
    );
  }

  /// 设置人物代表头像
  Future<void> setRepresentativeFace(int personId, int faceId) async {
    if (!_initialized) await init();

    await _db!.update(
      _tablePersons,
      {
        _colRepresentativeFaceId: faceId,
        _colUpdatedAt: DateTime.now().millisecondsSinceEpoch,
      },
      where: '$_colId = ?',
      whereArgs: [personId],
    );
  }

  /// 获取所有人物
  Future<List<PersonEntity>> getAllPersons() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tablePersons,
      orderBy: '$_colPhotoCount DESC',
    );

    return results.map(_personFromRow).toList();
  }

  /// 获取人物详情
  Future<PersonEntity?> getPerson(int personId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tablePersons,
      where: '$_colId = ?',
      whereArgs: [personId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _personFromRow(results.first);
  }

  /// 合并人物（将 sourceId 的人脸合并到 targetId）
  Future<void> mergePersons(int targetId, int sourceId) async {
    if (!_initialized) await init();

    await _db!.transaction((txn) async {
      // 将源人物的所有人脸转移到目标人物
      await txn.rawUpdate(
        'UPDATE $_tableFaces SET $_colPersonId = ? WHERE $_colPersonId = ?',
        [targetId, sourceId],
      );

      // 删除源人物
      await txn.delete(
        _tablePersons,
        where: '$_colId = ?',
        whereArgs: [sourceId],
      );
    });

    // 更新目标人物统计
    await updatePersonStats(targetId);
  }

  /// 删除人物
  Future<void> deletePerson(int personId) async {
    if (!_initialized) await init();

    await _db!.transaction((txn) async {
      // 将人物的人脸设为未分组
      await txn.rawUpdate(
        'UPDATE $_tableFaces SET $_colPersonId = NULL WHERE $_colPersonId = ?',
        [personId],
      );

      // 删除人物
      await txn.delete(
        _tablePersons,
        where: '$_colId = ?',
        whereArgs: [personId],
      );
    });
  }

  // ==================== 统计 ====================

  /// 获取统计信息
  Future<({int totalFaces, int totalPersons, int unassignedFaces})>
      getStats() async {
    if (!_initialized) await init();

    final totalFaces = Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tableFaces')) ??
        0;

    final totalPersons = Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tablePersons')) ??
        0;

    final unassignedFaces = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableFaces WHERE $_colPersonId IS NULL')) ??
        0;

    return (
      totalFaces: totalFaces,
      totalPersons: totalPersons,
      unassignedFaces: unassignedFaces,
    );
  }

  // ==================== 转换方法 ====================

  Map<String, dynamic> _faceToRow(FaceEntity face) => {
        if (face.id > 0) _colId: face.id,
        _colPhotoSourceId: face.photoSourceId,
        _colPhotoPath: face.photoPath,
        _colFaceBox: jsonEncode(face.faceBox.toJson()),
        _colEmbedding: face.embedding.buffer.asUint8List(),
        _colPersonId: face.personId,
        _colConfidence: face.confidence,
        _colCreatedAt:
            face.createdAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch,
      };

  FaceEntity _faceFromRow(Map<String, dynamic> row) {
    final embeddingBytes = row[_colEmbedding] as Uint8List;

    return FaceEntity(
      id: row[_colId] as int,
      photoSourceId: row[_colPhotoSourceId] as String,
      photoPath: row[_colPhotoPath] as String,
      faceBox: FaceBox.fromJson(
          jsonDecode(row[_colFaceBox] as String) as Map<String, dynamic>),
      embedding: Float32List.view(embeddingBytes.buffer),
      personId: row[_colPersonId] as int?,
      confidence: (row[_colConfidence] as num?)?.toDouble() ?? 0.0,
      createdAt: row[_colCreatedAt] != null
          ? DateTime.fromMillisecondsSinceEpoch(row[_colCreatedAt] as int)
          : null,
    );
  }

  PersonEntity _personFromRow(Map<String, dynamic> row) => PersonEntity(
        id: row[_colId] as int,
        name: row[_colName] as String?,
        representativeFaceId: row[_colRepresentativeFaceId] as int?,
        faceCount: row[_colFaceCount] as int? ?? 0,
        photoCount: row[_colPhotoCount] as int? ?? 0,
        createdAt: row[_colCreatedAt] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colCreatedAt] as int)
            : null,
        updatedAt: row[_colUpdatedAt] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colUpdatedAt] as int)
            : null,
      );

  /// 关闭数据库
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
      _initialized = false;
      logger.i('FaceDatabaseService: 数据库已关闭');
    }
  }

  /// 清空所有数据
  Future<void> clear() async {
    if (!_initialized) await init();

    await _db!.delete(_tableFaces);
    await _db!.delete(_tablePersons);
    logger.i('FaceDatabaseService: 已清空所有数据');
  }
}

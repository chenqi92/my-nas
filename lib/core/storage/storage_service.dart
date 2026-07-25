import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/core/utils/logger.dart';

abstract class StorageService {
  Future<void> init();
  Future<void> put<T>(String key, T value);
  T? get<T>(String key);
  Future<void> delete(String key);
  Future<void> clear();
  bool containsKey(String key);
}

class HiveStorageService implements StorageService {
  HiveStorageService({required String boxName}) : _boxName = boxName;

  final String _boxName;
  late Box<dynamic> _box;

  @override
  Future<void> init() async {
    // Hive.initFlutter() 已在 main.dart 中调用，这里直接打开 box
    _box = await Hive.openBox(_boxName);
    logger.i('HiveStorageService initialized: $_boxName');
  }

  @override
  Future<void> put<T>(String key, T value) async {
    await _box.put(key, value);
  }

  @override
  T? get<T>(String key) => _box.get(key) as T?;

  @override
  Future<void> delete(String key) async {
    await _box.delete(key);
  }

  @override
  Future<void> clear() async {
    await _box.clear();
  }

  @override
  bool containsKey(String key) => _box.containsKey(key);
}

class SecureStorageService {
  SecureStorageService() : _storage = defaultSecureStorage;

  final FlutterSecureStorage _storage;

  Future<void> write({required String key, required String value}) =>
      writeSecureValueVerified(_storage, key: key, value: value);

  Future<String?> read({required String key}) => _storage.read(key: key);

  Future<void> delete({required String key}) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();

  Future<bool> containsKey({required String key}) =>
      _storage.containsKey(key: key);

  Future<Map<String, String>> readAll() => _storage.readAll();
}

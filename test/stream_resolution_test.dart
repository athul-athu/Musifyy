// ignore_for_file: avoid_print, unnecessary_overrides
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    HttpOverrides.global = _RealHttpOverrides();
    tempDir = await Directory.systemTemp.createTemp('musify_stream_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    try {
      await Hive.close();
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('resolves playable stream URL for VJ-oY5efzjU (Neela Neela Neelamalayil)', () async {
    final url = await fetchSongStreamUrl('VJ-oY5efzjU', false);
    expect(url, isNotNull);
    expect(url, isNotEmpty);
    expect(url!.startsWith('https://'), isTrue);
    print('Resolved VJ-oY5efzjU URL: ${url.substring(0, 60)}...');
  });

  test('resolves playable stream URL for kDSJ6CqMw_4 (Ganadhipathi)', () async {
    final url = await fetchSongStreamUrl('kDSJ6CqMw_4', false);
    expect(url, isNotNull);
    expect(url, isNotEmpty);
    expect(url!.startsWith('https://'), isTrue);
    print('Resolved kDSJ6CqMw_4 URL: ${url.substring(0, 60)}...');
  });
}

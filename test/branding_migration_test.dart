import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_music/branding_migration.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory workspace;
  late Directory legacy;
  late Directory support;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('branding_migration_');
    legacy = await Directory(path.join(workspace.path, 'nexApp')).create();
    support = await Directory(path.join(workspace.path, 'nexMusic')).create();
  });

  tearDown(() async {
    await workspace.delete(recursive: true);
  });

  Future<File> write(Directory directory, String name, List<int> bytes) async {
    final file = File(path.join(directory.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }

  Future<bool> link(String target, String name) async {
    try {
      await Link(name).create(target);
      return true;
    } on FileSystemException catch (error) {
      markTestSkipped('Symbolic links unavailable: $error');
      return false;
    }
  }

  test(
    'retains preferences, catalogue cache and nested files byte for byte',
    () async {
      final preferences = await write(
        legacy,
        'shared_preferences.json',
        '{"flutter.user:alice:playlists":"saved"}'.codeUnits,
      );
      final cache = await write(
        legacy,
        'catalog_cache_v1.json',
        '{"songs":[{"id":"song1"}]}'.codeUnits,
      );
      final nested = await write(legacy, 'covers/track.bin', [0, 1, 127, 255]);

      await copyLegacyBrandingSupportFiles(support);

      for (final file in [preferences, cache, nested]) {
        final restored = File(
          path.join(support.path, path.relative(file.path, from: legacy.path)),
        );
        expect(await restored.readAsBytes(), await file.readAsBytes());
        expect(await file.exists(), isTrue);
      }
    },
  );

  test('keeps new preferences and remains safe to run again', () async {
    await write(legacy, 'shared_preferences.json', 'legacy'.codeUnits);
    await write(support, 'shared_preferences.json', 'new'.codeUnits);
    final cache = await write(
      legacy,
      'catalog_cache_v1.json',
      'cache'.codeUnits,
    );

    await copyLegacyBrandingSupportFiles(support);
    await cache.writeAsString('changed legacy cache');
    await copyLegacyBrandingSupportFiles(support);

    expect(
      await File(
        path.join(support.path, 'shared_preferences.json'),
      ).readAsString(),
      'new',
    );
    expect(
      await File(
        path.join(support.path, 'catalog_cache_v1.json'),
      ).readAsString(),
      'cache',
    );
    expect(await cache.readAsString(), 'changed legacy cache');
  });

  test('ignores another product path and missing legacy data', () async {
    await write(legacy, 'shared_preferences.json', 'legacy'.codeUnits);
    final unrelated = await Directory(
      path.join(workspace.path, 'anotherApp'),
    ).create();
    await copyLegacyBrandingSupportFiles(unrelated);
    expect(await unrelated.list().isEmpty, isTrue);

    await legacy.delete(recursive: true);
    await copyLegacyBrandingSupportFiles(support);
    expect(await support.list().isEmpty, isTrue);
  });

  test(
    'skips source links rather than reading outside legacy storage',
    () async {
      final outside = await Directory(
        path.join(workspace.path, 'outside'),
      ).create();
      final external = await write(
        outside,
        'private.json',
        'private'.codeUnits,
      );
      if (!await link(external.path, path.join(legacy.path, 'linked.json'))) {
        return;
      }
      if (!await link(
        outside.path,
        path.join(legacy.path, 'linked-directory'),
      )) {
        return;
      }
      await write(legacy, 'regular.json', 'retained'.codeUnits);

      await copyLegacyBrandingSupportFiles(support);

      expect(
        await File(path.join(support.path, 'regular.json')).readAsString(),
        'retained',
      );
      expect(
        await FileSystemEntity.type(path.join(support.path, 'linked.json')),
        FileSystemEntityType.notFound,
      );
      expect(
        await FileSystemEntity.type(
          path.join(support.path, 'linked-directory'),
        ),
        FileSystemEntityType.notFound,
      );
      expect(await external.readAsString(), 'private');
    },
  );

  test('skips destination links and conflicting destination types', () async {
    final outside = await Directory(
      path.join(workspace.path, 'outside'),
    ).create();
    final external = await write(outside, 'private.json', 'private'.codeUnits);
    if (!await link(
      external.path,
      path.join(support.path, 'shared_preferences.json'),
    )) {
      return;
    }
    if (!await link(outside.path, path.join(support.path, 'covers'))) return;
    await write(legacy, 'shared_preferences.json', 'legacy'.codeUnits);
    await write(legacy, 'covers/track.bin', [1, 2, 3]);
    await write(legacy, 'blocked/track.bin', [1, 2, 3]);
    await write(support, 'blocked', 'new file'.codeUnits);

    await copyLegacyBrandingSupportFiles(support);

    expect(await external.readAsString(), 'private');
    expect(await File(path.join(outside.path, 'track.bin')).exists(), isFalse);
    expect(
      await File(path.join(support.path, 'blocked')).readAsString(),
      'new file',
    );
  });

  test('does not migrate through a linked legacy root', () async {
    final outside = await Directory(
      path.join(workspace.path, 'outside'),
    ).create();
    await write(outside, 'shared_preferences.json', 'private'.codeUnits);
    await legacy.delete();
    if (!await link(outside.path, legacy.path)) return;

    await copyLegacyBrandingSupportFiles(support);

    expect(await support.list().isEmpty, isTrue);
  });

  test('does not migrate through a linked support root', () async {
    final outside = await Directory(
      path.join(workspace.path, 'outside'),
    ).create();
    await write(legacy, 'shared_preferences.json', 'legacy'.codeUnits);
    await support.delete();
    if (!await link(outside.path, support.path)) return;

    await copyLegacyBrandingSupportFiles(support);

    expect(await outside.list().isEmpty, isTrue);
  });
}

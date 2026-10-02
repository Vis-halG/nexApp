import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Windows path_provider uses CompanyName/ProductName for support storage.
/// Restore the previous brand's files before shared_preferences opens them.
Future<void> migrateWindowsBrandingSupportFiles() async {
  if (kIsWeb || !Platform.isWindows) return;
  try {
    await copyLegacyBrandingSupportFiles(
      await getApplicationSupportDirectory(),
    );
  } catch (error) {
    debugPrint('Previous app data could not be restored: $error');
  }
}

@visibleForTesting
Future<void> copyLegacyBrandingSupportFiles(Directory supportDirectory) async {
  final supportPath = path.normalize(supportDirectory.absolute.path);
  if (path.basename(supportPath) != 'nexMusic') return;

  final legacy = Directory(path.join(path.dirname(supportPath), 'nexApp'));
  if (await FileSystemEntity.type(supportPath, followLinks: false) !=
          FileSystemEntityType.directory ||
      await FileSystemEntity.type(legacy.path, followLinks: false) !=
          FileSystemEntityType.directory) {
    return;
  }

  final sourceRoot = path.normalize(await legacy.resolveSymbolicLinks());
  final targetRoot = path.normalize(
    await supportDirectory.resolveSymbolicLinks(),
  );
  if (path.basename(sourceRoot) != 'nexApp' ||
      path.basename(targetRoot) != 'nexMusic' ||
      !path.equals(path.dirname(sourceRoot), path.dirname(targetRoot))) {
    return;
  }

  Future<void> copyDirectory(Directory directory) async {
    await for (final entity in directory.list(followLinks: false)) {
      try {
        final kind = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (kind != FileSystemEntityType.file &&
            kind != FileSystemEntityType.directory) {
          continue;
        }

        final sourcePath = path.normalize(await entity.resolveSymbolicLinks());
        if (!path.isWithin(sourceRoot, sourcePath)) continue;
        final targetPath = path.join(
          targetRoot,
          path.relative(sourcePath, from: sourceRoot),
        );
        final targetKind = await FileSystemEntity.type(
          targetPath,
          followLinks: false,
        );
        if (kind == FileSystemEntityType.directory) {
          final target = Directory(targetPath);
          if (targetKind == FileSystemEntityType.notFound) {
            await target.create();
          } else if (targetKind != FileSystemEntityType.directory) {
            continue;
          }
          final resolvedTarget = path.normalize(
            await target.resolveSymbolicLinks(),
          );
          if (!path.equals(resolvedTarget, targetPath) ||
              !path.isWithin(targetRoot, resolvedTarget)) {
            continue;
          }
          await copyDirectory(Directory(sourcePath));
        } else if (targetKind == FileSystemEntityType.notFound) {
          final destination = File(targetPath);
          // Reserve the name exclusively so another migration cannot replace
          // a file that already belongs to the newly branded app.
          await destination.create(exclusive: true);
          try {
            await File(sourcePath).copy(targetPath);
          } catch (_) {
            await destination.delete();
            rethrow;
          }
        }
      } on FileSystemException catch (error) {
        debugPrint('A previous app data file could not be restored: $error');
      }
    }
  }

  await copyDirectory(Directory(sourceRoot));
}

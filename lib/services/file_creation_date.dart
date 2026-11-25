// Gene - Nov, 21, 2026: Cross-platform file creation date helper (macOS st_birthtime with FileStat.changed fallback).
// Gene - Nov, 25, 2026: Replaced /usr/bin/stat subprocess spawning with direct Rust FFI nativeFileCreationDate lookup.
import 'dart:io';
import 'rust_file_engines.dart';

Future<Map<String, DateTime>> getCreationDatesForFiles(
  List<File> files,
  Map<String, FileStat> statsByPath,
) async {
  final Map<String, DateTime> result = {};
  if (files.isEmpty) return result;

  // if (Platform.isMacOS) {
  //   const int chunkSize = 100;
  //   for (int i = 0; i < files.length; i += chunkSize) {
  //     final end = (i + chunkSize < files.length) ? i + chunkSize : files.length;
  //     final chunk = files.sublist(i, end);
  //     try {
  //       final procResult = await Process.run('/usr/bin/stat', [
  //         '-f',
  //         '%B\t%N',
  //         ...chunk.map((f) => f.path),
  //       ]);
  //       if (procResult.exitCode == 0 && procResult.stdout is String) {
  //         final lines = (procResult.stdout as String).split('\n');
  //         for (final rawLine in lines) {
  //           final line = rawLine.replaceAll('\r', '');
  //           if (line.isEmpty) continue;
  //           final tabIdx = line.indexOf('\t');
  //           if (tabIdx <= 0) continue;
  //           final secStr = line.substring(0, tabIdx).trim();
  //           final filePath = line.substring(tabIdx + 1);
  //           final epochSec = int.tryParse(secStr);
  //           if (epochSec != null && epochSec > 0) {
  //             result[filePath] = DateTime.fromMillisecondsSinceEpoch(
  //               epochSec * 1000,
  //             );
  //           }
  //         }
  //       }
  //     } catch (_) {
  //       // Fallback to FileStat.changed below when stat cannot run (e.g. sandbox).
  //     }
  //   }
  // }

  for (final file in files) {
    DateTime? nativeCreated;
    try {
      nativeCreated = nativeFileCreationDate(file.path);
    } catch (_) {}
    result[file.path] =
        nativeCreated ?? statsByPath[file.path]?.changed ?? DateTime.now();
  }
  return result;
}

Future<DateTime> getFileCreationDate(File file, FileStat stats) async {
  final map = await getCreationDatesForFiles([file], {file.path: stats});
  return map[file.path] ?? stats.changed;
}

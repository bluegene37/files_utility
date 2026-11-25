// Gene - Nov, 25, 2026: Raw dart:ffi @Native bindings for the native Rust transfer_engine library.
import 'dart:ffi';
import 'package:ffi/ffi.dart';

final class TransferConfigC extends Struct {
  external Pointer<Utf8> sourcePath;
  external Pointer<Utf8> destPath;
  external Pointer<Utf8> lastScannedDir;

  @Uint8()
  external int enableAgeFilter;

  @Int64()
  external int ageThresholdEpochMs;

  @Uint8()
  external int enableDateRange;

  @Int64()
  external int fromInclusiveEpochMs;

  @Int64()
  external int toExclusiveEpochMs;

  @Uint8()
  external int excludeSubfolders;

  @Uint64()
  external int initialFilesMoved;

  @Uint64()
  external int initialErrors;

  @Uint64()
  external int logInterval;
}

@Native<Pointer<Void> Function(Pointer<TransferConfigC>)>(
  symbol: 'transfer_engine_start',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Void> transferEngineStart(Pointer<TransferConfigC> cfg);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'transfer_engine_pause',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void transferEnginePause(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'transfer_engine_resume',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void transferEngineResume(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'transfer_engine_stop',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void transferEngineStop(Pointer<Void> job);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'transfer_engine_poll',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Utf8> transferEnginePoll(Pointer<Void> job);

@Native<Void Function(Pointer<Utf8>)>(
  symbol: 'transfer_engine_free_string',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void transferEngineFreeString(Pointer<Utf8> ptr);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'transfer_engine_destroy',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void transferEngineDestroy(Pointer<Void> job);

// Gene - Nov, 25, 2026: C-ABI structs and @Native bindings for Copy, Count, Delete, and FTP scan Rust engines.
final class CopyConfigC extends Struct {
  external Pointer<Utf8> sourcePath;
  external Pointer<Utf8> destPath;
  external Pointer<Utf8> progressFilePath;
  external Pointer<Utf8> completedDirsSerialized;
  external Pointer<Utf8> lastProcessedSerialized;

  @Uint8()
  external int enableAgeFilter;

  @Int64()
  external int ageThresholdEpochMs;

  @Uint8()
  external int enableDateRange;

  @Int64()
  external int fromInclusiveEpochMs;

  @Int64()
  external int toExclusiveEpochMs;

  @Uint64()
  external int initialCopied;

  @Uint64()
  external int initialSkipped;

  @Uint64()
  external int initialAlreadyExist;

  @Uint64()
  external int initialErrors;

  @Uint64()
  external int initialInspected;

  @Uint64()
  external int logInterval;
}

@Native<Pointer<Void> Function(Pointer<CopyConfigC>)>(
  symbol: 'copy_engine_start',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Void> copyEngineStart(Pointer<CopyConfigC> cfg);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'copy_engine_pause',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void copyEnginePause(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'copy_engine_resume',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void copyEngineResume(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'copy_engine_stop',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void copyEngineStop(Pointer<Void> job);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'copy_engine_poll',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Utf8> copyEnginePoll(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'copy_engine_destroy',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void copyEngineDestroy(Pointer<Void> job);

final class CountConfigC extends Struct {
  external Pointer<Utf8> targetPath;

  @Uint64()
  external int logInterval;
}

@Native<Pointer<Void> Function(Pointer<CountConfigC>)>(
  symbol: 'count_engine_start',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Void> countEngineStart(Pointer<CountConfigC> cfg);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'count_engine_stop',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void countEngineStop(Pointer<Void> job);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'count_engine_poll',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Utf8> countEnginePoll(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'count_engine_destroy',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void countEngineDestroy(Pointer<Void> job);

final class DeleteConfigC extends Struct {
  external Pointer<Utf8> targetPath;

  @Uint64()
  external int logInterval;

  external Pointer<Int64> rangesPtr;

  @Size()
  external int rangesLen;
}

@Native<Pointer<Void> Function(Pointer<DeleteConfigC>)>(
  symbol: 'delete_engine_start',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Void> deleteEngineStart(Pointer<DeleteConfigC> cfg);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'delete_engine_stop',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void deleteEngineStop(Pointer<Void> job);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'delete_engine_poll',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Utf8> deleteEnginePoll(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'delete_engine_destroy',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void deleteEngineDestroy(Pointer<Void> job);

@Native<Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Uint8)>(
  symbol: 'ftp_scan_start',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Void> ftpScanStart(
  Pointer<Utf8> dirPath,
  Pointer<Utf8> rootPath,
  int includeCreationTime,
);

@Native<Pointer<Utf8> Function(Pointer<Void>)>(
  symbol: 'ftp_scan_poll',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external Pointer<Utf8> ftpScanPoll(Pointer<Void> job);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ftp_scan_destroy',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external void ftpScanDestroy(Pointer<Void> job);

@Native<Int64 Function(Pointer<Utf8>)>(
  symbol: 'native_file_creation_ms',
  assetId: 'package:files_utility/services/rust_transfer_bindings.dart',
)
external int nativeFileCreationMs(Pointer<Utf8> path);

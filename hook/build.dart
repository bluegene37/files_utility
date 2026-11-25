// Gene - Nov, 25, 2026: Dart build hook that compiles native/transfer_engine via Cargo
// and bundles the resulting shared library as a CodeAsset for dart:ffi @Native.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

String _rustTargetTriple(OS os, Architecture arch) {
  if (os == OS.macOS && arch == Architecture.arm64) {
    return 'aarch64-apple-darwin';
  }
  if (os == OS.macOS && arch == Architecture.x64) {
    return 'x86_64-apple-darwin';
  }
  if (os == OS.windows && arch == Architecture.x64) {
    return 'x86_64-pc-windows-msvc';
  }
  if (os == OS.windows && arch == Architecture.arm64) {
    return 'aarch64-pc-windows-msvc';
  }
  if (os == OS.linux && arch == Architecture.x64) {
    return 'x86_64-unknown-linux-gnu';
  }
  if (os == OS.linux && arch == Architecture.arm64) {
    return 'aarch64-unknown-linux-gnu';
  }
  throw UnsupportedError(
    'Unsupported target for transfer_engine: OS=$os, Architecture=$arch',
  );
}

String _findCargoExecutable() {
  final sep = Platform.isWindows ? ';' : ':';
  final exeName = Platform.isWindows ? 'cargo.exe' : 'cargo';
  final pathEnv = Platform.environment['PATH'] ?? '';
  for (final dir in pathEnv.split(sep)) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir${Platform.pathSeparator}$exeName');
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }

  final home = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final fallback = File(
      '$home${Platform.pathSeparator}.cargo${Platform.pathSeparator}bin${Platform.pathSeparator}$exeName',
    );
    if (fallback.existsSync()) {
      return fallback.path;
    }
  }

  throw StateError(
    'Could not locate $exeName in PATH or ~/.cargo/bin. '
    'Install the Rust toolchain (https://rustup.rs) to build transfer_engine.',
  );
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final codeConfig = input.config.code;
    final targetOS = codeConfig.targetOS;
    final targetArch = codeConfig.targetArchitecture;
    final rustTarget = _rustTargetTriple(targetOS, targetArch);

    final packageRoot = input.packageRoot;
    final crateDir = packageRoot.resolve('native/transfer_engine/');
    final manifestUri = crateDir.resolve('Cargo.toml');
    // Gene - Nov, 25, 2026: Track all .rs files under native/transfer_engine/src/ as build dependencies.
    // final libRsUri = crateDir.resolve('src/lib.rs');
    //
    // output.dependencies.addAll([manifestUri, libRsUri]);
    final srcDir = Directory.fromUri(crateDir.resolve('src/'));
    final rustSources = srcDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.rs'))
        .map((f) => f.uri);
    output.dependencies.addAll([manifestUri, ...rustSources]);

    final cargoExe = _findCargoExecutable();
    final cargoBinDir = File(cargoExe).parent.path;
    final sep = Platform.isWindows ? ';' : ':';
    final env = Map<String, String>.from(Platform.environment);
    final existingPath = env['PATH'] ?? '';
    env['PATH'] = existingPath.isEmpty
        ? cargoBinDir
        : '$cargoBinDir$sep$existingPath';

    if (targetOS == OS.macOS) {
      String deploymentTarget = '12.0';
      try {
        final v = codeConfig.macOS.deploymentVersion;
        deploymentTarget = '${v.major}.${v.minor}';
      } catch (_) {}
      env['MACOSX_DEPLOYMENT_TARGET'] = deploymentTarget;
    }

    // Use a per-target Cargo target dir so parallel macOS arm64 + x64 builds
    // do not contend on Cargo's directory lock.
    final cargoTargetDir = Directory.fromUri(
      input.outputDirectoryShared.resolve('cargo_target_$rustTarget/'),
    );
    if (!cargoTargetDir.existsSync()) {
      cargoTargetDir.createSync(recursive: true);
    }

    final manifestPath = File.fromUri(manifestUri).path;
    final cargoResult = await Process.run(cargoExe, [
      'build',
      '--release',
      '--manifest-path',
      manifestPath,
      '--target',
      rustTarget,
      '--target-dir',
      cargoTargetDir.path,
    ], environment: env);

    if (cargoResult.exitCode != 0) {
      throw ProcessException(
        cargoExe,
        ['build', '--release', '--target', rustTarget],
        'Cargo build failed (exit ${cargoResult.exitCode}):\n'
        'STDOUT:\n${cargoResult.stdout}\n'
        'STDERR:\n${cargoResult.stderr}',
        cargoResult.exitCode,
      );
    }

    final dylibName = targetOS.dylibFileName('transfer_engine');
    final builtDylib = File(
      '${cargoTargetDir.path}${Platform.pathSeparator}$rustTarget${Platform.pathSeparator}release${Platform.pathSeparator}$dylibName',
    );
    if (!builtDylib.existsSync()) {
      throw StateError(
        'Expected compiled library was not found at ${builtDylib.path}',
      );
    }

    final outDir = Directory.fromUri(input.outputDirectory);
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }
    final copiedDylibUri = input.outputDirectory.resolve(dylibName);
    final copiedDylibFile = File.fromUri(copiedDylibUri);
    await builtDylib.copy(copiedDylibFile.path);

    if (targetOS == OS.macOS) {
      final installNameResult = await Process.run('install_name_tool', [
        '-id',
        '@rpath/$dylibName',
        copiedDylibFile.path,
      ]);
      if (installNameResult.exitCode != 0) {
        throw ProcessException(
          'install_name_tool',
          ['-id', '@rpath/$dylibName', copiedDylibFile.path],
          'install_name_tool failed: ${installNameResult.stderr}',
          installNameResult.exitCode,
        );
      }
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'services/rust_transfer_bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: copiedDylibUri,
      ),
    );
  });
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/update_provider.dart';
import 'update_dialog.dart';

/// Invisible wrapper that kicks off the silent startup update check and
/// presents [UpdateDialog] when a newer release is found. Mount it once,
/// under the [MaterialApp] Navigator (it calls [showDialog]).
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  UpdateProvider? _provider;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (!mounted) return;
    //   _provider = context.read<UpdateProvider>();
    //   _provider!.addListener(_onUpdateStateChanged);
    //   _provider!.checkSilently();
    // });
    // Gene - Nov, 23, 2026: Skip update listener and startup check when updates are disabled (e.g. Microsoft Store builds)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _provider = context.read<UpdateProvider>();
      if (_provider!.updatesDisabled) return;
      _provider!.addListener(_onUpdateStateChanged);
      _provider!.checkSilently();
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onUpdateStateChanged);
    super.dispose();
  }

  void _onUpdateStateChanged() {
    if (!mounted || _dialogVisible) return;
    if (_provider?.availableUpdate == null) return;
    _dialogVisible = true;
    showDialog<void>(
      context: context,
      builder: (_) => const UpdateDialog(),
    ).whenComplete(() => _dialogVisible = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

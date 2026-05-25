import 'package:flutter/material.dart';
import '../models/run_record.dart';
import '../services/history_service.dart';

class HistoryProvider with ChangeNotifier {
  final HistoryService _service = HistoryService();
  
  List<RunRecord> _records = [];
  bool _isLoading = true;

  List<RunRecord> get records => _records;
  bool get isLoading => _isLoading;

  // Aggregate Stats
  int get totalRuns => _records.length;
  
  int get totalFilesTransferred {
    return _records
      .where((r) => r.operation == 'Transfer')
      .fold(0, (sum, r) => sum + r.filesProcessed);
  }

  int get totalFilesCopied {
    return _records
      .where((r) => r.operation == 'Copy')
      .fold(0, (sum, r) => sum + r.filesProcessed);
  }

  int get totalFilesDeleted {
    return _records
      .where((r) => r.operation == 'Delete')
      .fold(0, (sum, r) => sum + r.filesProcessed);
  }

  int get totalErrors {
    return _records.fold(0, (sum, r) => sum + r.errors);
  }

  HistoryProvider() {
    refreshHistory();
  }

  Future<void> refreshHistory() async {
    _isLoading = true;
    notifyListeners();

    _records = await _service.loadHistory();
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addRecord(RunRecord record) async {
    await _service.saveRecord(record);
    await refreshHistory();
  }

  Future<void> clearHistory() async {
    await _service.clearHistory();
    await refreshHistory();
  }
}

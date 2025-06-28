import 'package:flutter/material.dart';
import 'dart:async';

/// 调试日志工具类
/// 用于在应用中显示日志信息，方便调试
class DebugLogger {
  static final DebugLogger _instance = DebugLogger._internal();
  factory DebugLogger() => _instance;
  DebugLogger._internal();

  final List<LogEntry> _logs = [];
  final StreamController<List<LogEntry>> _logController =
      StreamController<List<LogEntry>>.broadcast();

  Stream<List<LogEntry>> get logStream => _logController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  /// 添加日志
  void log(String message, {LogLevel level = LogLevel.info, String? tag}) {
    final entry = LogEntry(
      message: message,
      level: level,
      tag: tag,
      timestamp: DateTime.now(),
    );

    _logs.add(entry);

    // 限制日志数量，避免内存溢出
    if (_logs.length > 1000) {
      _logs.removeRange(0, 100);
    }

    _logController.add(_logs);

    // 同时输出到控制台
    print('${entry.level.emoji} [${entry.tag ?? 'APP'}] ${entry.message}');
  }

  /// 信息日志
  void info(String message, {String? tag}) {
    log(message, level: LogLevel.info, tag: tag);
  }

  /// 警告日志
  void warning(String message, {String? tag}) {
    log(message, level: LogLevel.warning, tag: tag);
  }

  /// 错误日志
  void error(String message, {String? tag}) {
    log(message, level: LogLevel.error, tag: tag);
  }

  /// 调试日志
  void debug(String message, {String? tag}) {
    log(message, level: LogLevel.debug, tag: tag);
  }

  /// 清除所有日志
  void clear() {
    _logs.clear();
    _logController.add(_logs);
  }

  /// 导出日志
  String exportLogs() {
    return _logs.map((entry) => entry.toString()).join('\n');
  }

  void pushLogs() {
    _logController.add(_logs);
  }

  void dispose() {
    _logController.close();
  }
}

/// 日志级别
enum LogLevel {
  debug,
  info,
  warning,
  error;

  String get emoji {
    switch (this) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  Color get color {
    switch (this) {
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.blue;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
    }
  }
}

/// 日志条目
class LogEntry {
  final String message;
  final LogLevel level;
  final String? tag;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    this.tag,
    required this.timestamp,
  });

  @override
  String toString() {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    return '[$timeStr] ${level.emoji} [${tag ?? 'APP'}] $message';
  }
}

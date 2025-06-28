#!/usr/bin/env dart

import 'lib/utils/debug_logger.dart';

/// 调试数据库内容的脚本
void main() {
  DebugLogger().info('=== 数据库调试工具 ===', tag: 'DEBUG_DB');

  DebugLogger().info('由于权限限制，无法直接访问模拟器数据库', tag: 'DEBUG_DB');
  DebugLogger().info('建议在模拟器A中添加调试日志来查看群组数据', tag: 'DEBUG_DB');

  // 提供调试建议
  DebugLogger().info('\n=== 调试建议 ===', tag: 'DEBUG_DB');
  DebugLogger().info(
    '1. 在模拟器A的GroupService._validateConnection方法中添加详细日志',
    tag: 'DEBUG_DB',
  );
  DebugLogger().info('2. 在AppProvider中打印当前群组列表', tag: 'DEBUG_DB');
  DebugLogger().info('3. 检查群组状态是否正确保存', tag: 'DEBUG_DB');

  debugSuggestions();
}

/// 添加调试日志的建议代码
void debugSuggestions() {
  DebugLogger().info('''
=== 建议在以下位置添加调试日志 ===

1. 在GroupService._validateConnection方法中：
```dart
DebugLogger().info('=== 连接验证调试 ===', tag: 'GROUP_SERVICE');
DebugLogger().info('验证连接: 用户=\$userId, 群组=\$groupId, 是否新成员=\$isNewMember', tag: 'GROUP_SERVICE');

// 1. 检查群组是否存在
final group = await StorageService.loadGroup(groupId);
if (group == null) {
  DebugLogger().error('❌ 群组不存在: \$groupId', tag: 'GROUP_SERVICE');
  return false;
}
DebugLogger().info('✅ 群组存在: \${group.name}', tag: 'GROUP_SERVICE');
DebugLogger().info('群组状态: \${group.status}', tag: 'GROUP_SERVICE');
DebugLogger().info('群组成员数: \${group.members.length}', tag: 'GROUP_SERVICE');
DebugLogger().info('群组成员列表:', tag: 'GROUP_SERVICE');
for (var member in group.members) {
  DebugLogger().info('  - userId: \${member.userId}, name: \${member.name}, status: \${member.status}', tag: 'GROUP_SERVICE');
}

// 2. 检查群组状态
if (group.status != GroupStatus.active) {
  DebugLogger().error('❌ 群组状态无效: \${group.status}', tag: 'GROUP_SERVICE');
  return false;
}
DebugLogger().info('✅ 群组状态有效: \${group.status}', tag: 'GROUP_SERVICE');

// 3. 新成员验证
if (isNewMember) {
  DebugLogger().info('✅ 新成员验证通过', tag: 'GROUP_SERVICE');
  return true;
}
```

2. 在AppProvider中打印当前群组：
```dart
DebugLogger().info('=== 当前群组列表 ===', tag: 'APP_PROVIDER');
for (var group in groups) {
  DebugLogger().info('群组: \${group.name} (\${group.id})', tag: 'APP_PROVIDER');
  DebugLogger().info('状态: \${group.status}', tag: 'APP_PROVIDER');
  DebugLogger().info('成员数: \${group.members.length}', tag: 'APP_PROVIDER');
  for (var member in group.members) {
    DebugLogger().info('  - \${member.name} (\${member.userId})', tag: 'APP_PROVIDER');
  }
}
```
''', tag: 'DEBUG_DB');
}

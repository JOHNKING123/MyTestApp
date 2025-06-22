#!/usr/bin/env dart

/// 调试数据库内容的脚本
void main() {
  print('=== 数据库调试工具 ===');

  print('由于权限限制，无法直接访问模拟器数据库');
  print('建议在模拟器A中添加调试日志来查看群组数据');

  // 提供调试建议
  print('\n=== 调试建议 ===');
  print('1. 在模拟器A的GroupService._validateConnection方法中添加详细日志');
  print('2. 在AppProvider中打印当前群组列表');
  print('3. 检查群组状态是否正确保存');

  debugSuggestions();
}

/// 添加调试日志的建议代码
void debugSuggestions() {
  print('''
=== 建议在以下位置添加调试日志 ===

1. 在GroupService._validateConnection方法中：
```dart
print('=== 连接验证调试 ===');
print('验证连接: 用户=\$userId, 群组=\$groupId, 是否新成员=\$isNewMember');

// 1. 检查群组是否存在
final group = await StorageService.loadGroup(groupId);
if (group == null) {
  print('❌ 群组不存在: \$groupId');
  return false;
}
print('✅ 群组存在: \${group.name}');
print('群组状态: \${group.status}');
print('群组成员数: \${group.members.length}');
print('群组成员列表:');
for (var member in group.members) {
  print('  - userId: \${member.userId}, name: \${member.name}, status: \${member.status}');
}

// 2. 检查群组状态
if (group.status != GroupStatus.active) {
  print('❌ 群组状态无效: \${group.status}');
  return false;
}
print('✅ 群组状态有效: \${group.status}');

// 3. 新成员验证
if (isNewMember) {
  print('✅ 新成员验证通过');
  return true;
}
```

2. 在AppProvider中打印当前群组：
```dart
print('=== 当前群组列表 ===');
for (var group in groups) {
  print('群组: \${group.name} (\${group.id})');
  print('状态: \${group.status}');
  print('成员数: \${group.members.length}');
  for (var member in group.members) {
    print('  - \${member.name} (\${member.userId})');
  }
}
```
''');
}

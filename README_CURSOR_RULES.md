# Cursor AI 代码生成规则使用说明

## 概述

本项目包含了一个完整的 `.cursorrules` 文件，用于指导 Cursor AI 生成符合项目规范的 Flutter 代码。这些规则基于现有的 MyTestApp 项目代码风格和架构设计。

## 规则文件位置

- `.cursorrules` - 主要的 Cursor AI 规则文件
- `README_CURSOR_RULES.md` - 本说明文档

## 规则文件特点

### 1. 项目特定规范
- 基于现有的 MyTestApp 项目架构
- 遵循项目的命名约定和代码组织方式
- 包含项目特定的安全要求和加密规范

### 2. Flutter 最佳实践
- 遵循 Flutter 官方推荐的编码规范
- 使用 Provider 进行状态管理
- 支持跨平台开发

### 3. 安全优先
- 强调端到端加密实现
- 包含数据验证规范
- 避免敏感信息泄露

## 如何使用

### 1. 在 Cursor 中启用规则
确保 `.cursorrules` 文件位于项目根目录，Cursor AI 会自动读取并应用这些规则。

### 2. 代码生成提示
当使用 Cursor AI 生成代码时，可以引用规则中的特定部分：

```
请按照项目规范创建一个新的服务类，遵循单例模式和错误处理规范。
```

### 3. 代码审查
使用规则文件作为代码审查的标准，确保新代码符合项目规范。

## 规则内容详解

### 命名规范
- **文件命名**: 使用小写字母和下划线，如 `user_setup_screen.dart`
- **类命名**: 使用 PascalCase，如 `User`, `GroupService`
- **变量命名**: 使用 camelCase，私有变量以下划线开头

### 架构模式
- **模型层**: 使用 `@JsonSerializable()` 注解，包含序列化方法
- **服务层**: 单例模式，异步方法使用 `async/await`
- **状态管理**: 继承 `ChangeNotifier`，使用 `notifyListeners()`
- **UI层**: StatefulWidget，使用 `Consumer<AppProvider>`

### 编码规范
- **导入顺序**: Dart标准库 → Flutter框架 → 第三方包 → 项目内部
- **错误处理**: 使用 try-catch，记录错误日志
- **空安全**: 充分利用 Dart 的空安全特性

## 常见使用场景

### 1. 创建新的模型类
```dart
// 提示: 请按照项目规范创建一个新的消息类型模型
@JsonSerializable()
class MessageType {
  final String id;
  final String name;
  final MessageTypeCategory category;
  
  MessageType({
    required this.id,
    required this.name,
    required this.category,
  });
  
  factory MessageType.fromJson(Map<String, dynamic> json) => 
      _$MessageTypeFromJson(json);
  Map<String, dynamic> toJson() => _$MessageTypeToJson(this);
}
```

### 2. 创建新的服务类
```dart
// 提示: 请按照项目规范创建一个新的通知服务
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  Future<void> sendNotification(String message) async {
    try {
      // 实现通知逻辑
      print('发送通知: $message');
    } catch (e) {
      print('发送通知失败: $e');
    }
  }
}
```

### 3. 创建新的界面
```dart
// 提示: 请按照项目规范创建一个新的设置界面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          return _buildSettingsList(provider);
        },
      ),
    );
  }
  
  Widget _buildSettingsList(AppProvider provider) {
    // 构建设置列表
  }
}
```

## 规则更新和维护

### 1. 更新规则
当项目架构或编码规范发生变化时，及时更新 `.cursorrules` 文件。

### 2. 规则验证
定期检查生成的代码是否符合规则要求，必要时调整规则。

### 3. 团队协作
确保团队成员都了解并遵循这些规则，保持代码风格的一致性。

## 最佳实践

### 1. 渐进式采用
- 新功能严格按照规则实现
- 现有代码逐步重构以符合规则

### 2. 代码审查
- 使用规则作为代码审查的标准
- 重点关注安全性和性能

### 3. 文档同步
- 保持规则文件与项目文档的一致性
- 及时更新相关说明

## 故障排除

### 1. 规则不生效
- 检查 `.cursorrules` 文件是否在项目根目录
- 确认 Cursor AI 已正确加载规则

### 2. 生成的代码不符合预期
- 检查规则描述是否清晰明确
- 考虑添加更具体的示例

### 3. 性能问题
- 确保规则文件大小合理
- 避免过于复杂的规则描述

## 总结

`.cursorrules` 文件是确保项目代码质量和一致性的重要工具。通过遵循这些规则，可以：

1. **提高代码质量**: 统一的编码风格和架构模式
2. **增强安全性**: 严格的安全规范和加密要求
3. **提升开发效率**: 减少代码审查时间，提高团队协作效率
4. **保证可维护性**: 清晰的代码结构和文档规范

定期维护和更新这些规则，确保它们与项目的发展保持同步。 
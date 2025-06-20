import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

@JsonSerializable()
class Message {
  final String id;
  final String groupId;
  final String senderId;
  final MessageContent content;
  final MessageType type;
  final DateTime timestamp;
  MessageStatus status;
  final String signature;
  final Map<String, dynamic> metadata;

  // 消息序列号（防重放）
  final int sequenceNumber;

  // 消息引用（回复功能）
  final String? replyToMessageId;

  // 消息编辑历史
  final List<MessageEdit> editHistory;

  Message({
    required this.id,
    required this.groupId,
    required this.senderId,
    required this.content,
    required this.type,
    required this.timestamp,
    this.status = MessageStatus.sending,
    required this.signature,
    this.metadata = const {},
    required this.sequenceNumber,
    this.replyToMessageId,
    this.editHistory = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  bool isValid() => id.isNotEmpty && groupId.isNotEmpty && senderId.isNotEmpty;
  String getEncryptedContent() => content.encryptedContent ?? '';
  bool verifySignature() => signature.isNotEmpty;
}

@JsonSerializable()
class MessageContent {
  final String text;
  final MessageType type;
  final Map<String, dynamic> data;
  final int size;

  // 文件相关
  final String? filePath;
  final String? fileName;
  final String? mimeType;

  // 媒体相关
  final String? mediaUrl;
  final int? duration;
  final int? width;
  final int? height;

  // 加密相关
  final String? encryptedContent;

  MessageContent({
    required this.text,
    required this.type,
    this.data = const {},
    required this.size,
    this.filePath,
    this.fileName,
    this.mimeType,
    this.mediaUrl,
    this.duration,
    this.width,
    this.height,
    this.encryptedContent,
  });

  factory MessageContent.fromJson(Map<String, dynamic> json) =>
      _$MessageContentFromJson(json);
  Map<String, dynamic> toJson() => _$MessageContentToJson(this);

  int getSize() => size;
}

@JsonSerializable()
class MessageEdit {
  final String editorId;
  final String oldText;
  final String newText;
  final DateTime editedAt;

  MessageEdit({
    required this.editorId,
    required this.oldText,
    required this.newText,
    required this.editedAt,
  });

  factory MessageEdit.fromJson(Map<String, dynamic> json) =>
      _$MessageEditFromJson(json);
  Map<String, dynamic> toJson() => _$MessageEditToJson(this);
}

@JsonSerializable()
class EncryptedMessage {
  final String messageId;
  final String groupId;
  final String senderId;
  final String encryptedContent;
  final String signature;
  final DateTime timestamp;
  final int sequenceNumber;
  final MessageType type;

  // 加密相关
  final String encryptionAlgorithm;
  final String iv;
  final String authTag;

  // 密钥相关
  final String keyId;
  final int keyVersion;

  EncryptedMessage({
    required this.messageId,
    required this.groupId,
    required this.senderId,
    required this.encryptedContent,
    required this.signature,
    required this.timestamp,
    required this.sequenceNumber,
    required this.type,
    required this.encryptionAlgorithm,
    required this.iv,
    required this.authTag,
    required this.keyId,
    required this.keyVersion,
  });

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) =>
      _$EncryptedMessageFromJson(json);
  Map<String, dynamic> toJson() => _$EncryptedMessageToJson(this);
}

enum MessageType {
  text,
  image,
  file,
  voice,
  video,
  location,
  system,
  encrypted,
}

enum MessageStatus { sending, sent, delivered, read, failed, deleted }

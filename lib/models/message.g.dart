// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  groupId: json['groupId'] as String,
  senderId: json['senderId'] as String,
  content: MessageContent.fromJson(json['content'] as Map<String, dynamic>),
  type: $enumDecode(_$MessageTypeEnumMap, json['type']),
  timestamp: DateTime.parse(json['timestamp'] as String),
  status:
      $enumDecodeNullable(_$MessageStatusEnumMap, json['status']) ??
      MessageStatus.sending,
  signature: json['signature'] as String,
  metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
  sequenceNumber: (json['sequenceNumber'] as num).toInt(),
  replyToMessageId: json['replyToMessageId'] as String?,
  editHistory:
      (json['editHistory'] as List<dynamic>?)
          ?.map((e) => MessageEdit.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'groupId': instance.groupId,
  'senderId': instance.senderId,
  'content': instance.content,
  'type': _$MessageTypeEnumMap[instance.type]!,
  'timestamp': instance.timestamp.toIso8601String(),
  'status': _$MessageStatusEnumMap[instance.status]!,
  'signature': instance.signature,
  'metadata': instance.metadata,
  'sequenceNumber': instance.sequenceNumber,
  'replyToMessageId': instance.replyToMessageId,
  'editHistory': instance.editHistory,
};

const _$MessageTypeEnumMap = {
  MessageType.text: 'text',
  MessageType.image: 'image',
  MessageType.file: 'file',
  MessageType.voice: 'voice',
  MessageType.video: 'video',
  MessageType.location: 'location',
  MessageType.system: 'system',
  MessageType.encrypted: 'encrypted',
};

const _$MessageStatusEnumMap = {
  MessageStatus.sending: 'sending',
  MessageStatus.sent: 'sent',
  MessageStatus.delivered: 'delivered',
  MessageStatus.read: 'read',
  MessageStatus.failed: 'failed',
  MessageStatus.deleted: 'deleted',
};

MessageContent _$MessageContentFromJson(Map<String, dynamic> json) =>
    MessageContent(
      text: json['text'] as String,
      type: $enumDecode(_$MessageTypeEnumMap, json['type']),
      data: json['data'] as Map<String, dynamic>? ?? const {},
      size: (json['size'] as num).toInt(),
      filePath: json['filePath'] as String?,
      fileName: json['fileName'] as String?,
      mimeType: json['mimeType'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      encryptedContent: json['encryptedContent'] as String?,
    );

Map<String, dynamic> _$MessageContentToJson(MessageContent instance) =>
    <String, dynamic>{
      'text': instance.text,
      'type': _$MessageTypeEnumMap[instance.type]!,
      'data': instance.data,
      'size': instance.size,
      'filePath': instance.filePath,
      'fileName': instance.fileName,
      'mimeType': instance.mimeType,
      'mediaUrl': instance.mediaUrl,
      'duration': instance.duration,
      'width': instance.width,
      'height': instance.height,
      'encryptedContent': instance.encryptedContent,
    };

MessageEdit _$MessageEditFromJson(Map<String, dynamic> json) => MessageEdit(
  editorId: json['editorId'] as String,
  oldText: json['oldText'] as String,
  newText: json['newText'] as String,
  editedAt: DateTime.parse(json['editedAt'] as String),
);

Map<String, dynamic> _$MessageEditToJson(MessageEdit instance) =>
    <String, dynamic>{
      'editorId': instance.editorId,
      'oldText': instance.oldText,
      'newText': instance.newText,
      'editedAt': instance.editedAt.toIso8601String(),
    };

EncryptedMessage _$EncryptedMessageFromJson(Map<String, dynamic> json) =>
    EncryptedMessage(
      messageId: json['messageId'] as String,
      groupId: json['groupId'] as String,
      senderId: json['senderId'] as String,
      encryptedContent: json['encryptedContent'] as String,
      signature: json['signature'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sequenceNumber: (json['sequenceNumber'] as num).toInt(),
      type: $enumDecode(_$MessageTypeEnumMap, json['type']),
      encryptionAlgorithm: json['encryptionAlgorithm'] as String,
      iv: json['iv'] as String,
      authTag: json['authTag'] as String,
      keyId: json['keyId'] as String,
      keyVersion: (json['keyVersion'] as num).toInt(),
    );

Map<String, dynamic> _$EncryptedMessageToJson(EncryptedMessage instance) =>
    <String, dynamic>{
      'messageId': instance.messageId,
      'groupId': instance.groupId,
      'senderId': instance.senderId,
      'encryptedContent': instance.encryptedContent,
      'signature': instance.signature,
      'timestamp': instance.timestamp.toIso8601String(),
      'sequenceNumber': instance.sequenceNumber,
      'type': _$MessageTypeEnumMap[instance.type]!,
      'encryptionAlgorithm': instance.encryptionAlgorithm,
      'iv': instance.iv,
      'authTag': instance.authTag,
      'keyId': instance.keyId,
      'keyVersion': instance.keyVersion,
    };

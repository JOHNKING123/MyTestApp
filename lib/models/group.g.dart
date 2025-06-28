// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Group _$GroupFromJson(Map<String, dynamic> json) => Group(
  id: json['id'] as String,
  name: json['name'] as String,
  creatorId: json['creatorId'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  groupKeys: GroupKeyPair.fromJson(json['groupKeys'] as Map<String, dynamic>),
  sessionKey: SessionKey.fromJson(json['sessionKey'] as Map<String, dynamic>),
  members: (json['members'] as List<dynamic>?)
      ?.map((e) => Member.fromJson(e as Map<String, dynamic>))
      .toList(),
  status:
      $enumDecodeNullable(_$GroupStatusEnumMap, json['status']) ??
      GroupStatus.active,
  description: json['description'] as String? ?? '',
  maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 100,
  settings: json['settings'] == null
      ? const GroupSettings()
      : GroupSettings.fromJson(json['settings'] as Map<String, dynamic>),
);

Map<String, dynamic> _$GroupToJson(Group instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'creatorId': instance.creatorId,
  'createdAt': instance.createdAt.toIso8601String(),
  'groupKeys': instance.groupKeys,
  'sessionKey': instance.sessionKey,
  'members': instance.members,
  'status': _$GroupStatusEnumMap[instance.status]!,
  'description': instance.description,
  'maxMembers': instance.maxMembers,
  'settings': instance.settings,
};

const _$GroupStatusEnumMap = {
  GroupStatus.active: 'active',
  GroupStatus.inactive: 'inactive',
  GroupStatus.disbanded: 'disbanded',
};

GroupKeyPair _$GroupKeyPairFromJson(Map<String, dynamic> json) => GroupKeyPair(
  publicKey: json['publicKey'] as String,
  privateKey: json['privateKey'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  algorithm:
      $enumDecodeNullable(_$KeyAlgorithmEnumMap, json['algorithm']) ??
      KeyAlgorithm.ecdsa,
);

const _$KeyAlgorithmEnumMap = {
  KeyAlgorithm.rsa: 'rsa',
  KeyAlgorithm.ecdsa: 'ecdsa',
  KeyAlgorithm.ed25519: 'ed25519',
};

SessionKey _$SessionKeyFromJson(Map<String, dynamic> json) => SessionKey(
  key: json['key'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  expiresAt: DateTime.parse(json['expiresAt'] as String),
  version: (json['version'] as num).toInt(),
);

Map<String, dynamic> _$SessionKeyToJson(SessionKey instance) =>
    <String, dynamic>{
      'key': instance.key,
      'createdAt': instance.createdAt.toIso8601String(),
      'expiresAt': instance.expiresAt.toIso8601String(),
      'version': instance.version,
    };

GroupSettings _$GroupSettingsFromJson(Map<String, dynamic> json) =>
    GroupSettings(
      allowMemberInvite: json['allowMemberInvite'] as bool? ?? true,
      allowMessageEdit: json['allowMessageEdit'] as bool? ?? true,
      allowMessageDelete: json['allowMessageDelete'] as bool? ?? true,
      messageRetentionDays:
          (json['messageRetentionDays'] as num?)?.toInt() ?? 30,
    );

Map<String, dynamic> _$GroupSettingsToJson(GroupSettings instance) =>
    <String, dynamic>{
      'allowMemberInvite': instance.allowMemberInvite,
      'allowMessageEdit': instance.allowMessageEdit,
      'allowMessageDelete': instance.allowMessageDelete,
      'messageRetentionDays': instance.messageRetentionDays,
    };

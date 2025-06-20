// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Member _$MemberFromJson(Map<String, dynamic> json) => Member(
  id: json['id'] as String,
  userId: json['userId'] as String,
  groupId: json['groupId'] as String,
  name: json['name'] as String,
  publicKey: json['publicKey'] as String,
  joinedAt: DateTime.parse(json['joinedAt'] as String),
  lastSeen: DateTime.parse(json['lastSeen'] as String),
  role:
      $enumDecodeNullable(_$MemberRoleEnumMap, json['role']) ??
      MemberRole.member,
  status:
      $enumDecodeNullable(_$MemberStatusEnumMap, json['status']) ??
      MemberStatus.active,
  permissions:
      (json['permissions'] as List<dynamic>?)
          ?.map((e) => $enumDecode(_$PermissionEnumMap, e))
          .toList() ??
      const [],
  groupNickname: json['groupNickname'] as String?,
  isMuted: json['isMuted'] as bool? ?? false,
  mutedUntil: json['mutedUntil'] == null
      ? null
      : DateTime.parse(json['mutedUntil'] as String),
);

Map<String, dynamic> _$MemberToJson(Member instance) => <String, dynamic>{
  'id': instance.id,
  'userId': instance.userId,
  'groupId': instance.groupId,
  'name': instance.name,
  'publicKey': instance.publicKey,
  'joinedAt': instance.joinedAt.toIso8601String(),
  'lastSeen': instance.lastSeen.toIso8601String(),
  'role': _$MemberRoleEnumMap[instance.role]!,
  'status': _$MemberStatusEnumMap[instance.status]!,
  'permissions': instance.permissions
      .map((e) => _$PermissionEnumMap[e]!)
      .toList(),
  'groupNickname': instance.groupNickname,
  'isMuted': instance.isMuted,
  'mutedUntil': instance.mutedUntil?.toIso8601String(),
};

const _$MemberRoleEnumMap = {
  MemberRole.creator: 'creator',
  MemberRole.admin: 'admin',
  MemberRole.moderator: 'moderator',
  MemberRole.member: 'member',
};

const _$MemberStatusEnumMap = {
  MemberStatus.active: 'active',
  MemberStatus.inactive: 'inactive',
  MemberStatus.kicked: 'kicked',
  MemberStatus.left: 'left',
};

const _$PermissionEnumMap = {
  Permission.sendMessage: 'sendMessage',
  Permission.sendFile: 'sendFile',
  Permission.sendImage: 'sendImage',
  Permission.sendVoice: 'sendVoice',
  Permission.inviteMember: 'inviteMember',
  Permission.kickMember: 'kickMember',
  Permission.changeGroupInfo: 'changeGroupInfo',
  Permission.changeMemberRole: 'changeMemberRole',
  Permission.rotateKeys: 'rotateKeys',
  Permission.viewGroupLogs: 'viewGroupLogs',
  Permission.deleteGroup: 'deleteGroup',
};

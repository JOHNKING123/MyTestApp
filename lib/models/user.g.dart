// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: json['id'] as String,
  name: json['name'] as String,
  profile: UserProfile.fromJson(json['profile'] as Map<String, dynamic>),
  createdAt: DateTime.parse(json['createdAt'] as String),
  status:
      $enumDecodeNullable(_$UserStatusEnumMap, json['status']) ??
      UserStatus.active,
  lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
  deviceId: json['deviceId'] as String,
  sessionTokens:
      (json['sessionTokens'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'profile': instance.profile,
  'createdAt': instance.createdAt.toIso8601String(),
  'status': _$UserStatusEnumMap[instance.status]!,
  'lastActiveAt': instance.lastActiveAt.toIso8601String(),
  'deviceId': instance.deviceId,
  'sessionTokens': instance.sessionTokens,
};

const _$UserStatusEnumMap = {
  UserStatus.active: 'active',
  UserStatus.inactive: 'inactive',
  UserStatus.suspended: 'suspended',
  UserStatus.deleted: 'deleted',
};

UserProfile _$UserProfileFromJson(Map<String, dynamic> json) {
  $checkKeys(json, requiredKeys: const ['publicKey']);
  return UserProfile(
    avatar: json['avatar'] as String?,
    nickname: json['nickname'] as String?,
    status: json['status'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    publicKey: json['publicKey'] as String,
    customFields: json['customFields'] as Map<String, dynamic>?,
  );
}

Map<String, dynamic> _$UserProfileToJson(UserProfile instance) =>
    <String, dynamic>{
      'avatar': instance.avatar,
      'nickname': instance.nickname,
      'status': instance.status,
      'email': instance.email,
      'phone': instance.phone,
      'publicKey': instance.publicKey,
      'customFields': instance.customFields,
    };

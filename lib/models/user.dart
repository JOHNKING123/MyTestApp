import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final String id;
  final String name;
  UserProfile profile;
  final DateTime createdAt;
  UserStatus status;
  final DateTime lastActiveAt;

  // 安全相关
  final String deviceId;
  final List<String> sessionTokens;

  User({
    required this.id,
    required this.name,
    required this.profile,
    required this.createdAt,
    this.status = UserStatus.active,
    required this.lastActiveAt,
    required this.deviceId,
    this.sessionTokens = const [],
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  String get publicKey => profile.publicKey;
  bool get isActive => status == UserStatus.active;

  void updateProfile(UserProfile newProfile) {
    profile = newProfile;
  }
}

@JsonSerializable()
class UserProfile {
  String? avatar;
  String? nickname;
  String? status;
  String? email;
  String? phone;
  @JsonKey(required: true)
  String publicKey;
  Map<String, dynamic> customFields;

  UserProfile({
    this.avatar,
    this.nickname,
    this.status,
    this.email,
    this.phone,
    required this.publicKey,
    Map<String, dynamic>? customFields,
  }) : customFields = customFields ?? {};

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
  Map<String, dynamic> toJson() => _$UserProfileToJson(this);
}

enum UserStatus { active, inactive, suspended, deleted }

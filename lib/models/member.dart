import 'package:json_annotation/json_annotation.dart';

part 'member.g.dart';

@JsonSerializable()
class Member {
  final String id;
  final String userId;
  final String groupId;
  final String name;
  final String publicKey;
  final DateTime joinedAt;
  DateTime lastSeen;
  MemberRole role;
  MemberStatus status;
  final List<Permission> permissions;

  // 群组内特定信息
  String? groupNickname;
  bool isMuted;
  DateTime? mutedUntil;

  Member({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.name,
    required this.publicKey,
    required this.joinedAt,
    required this.lastSeen,
    this.role = MemberRole.member,
    this.status = MemberStatus.active,
    this.permissions = const [],
    this.groupNickname,
    this.isMuted = false,
    this.mutedUntil,
  });

  factory Member.fromJson(Map<String, dynamic> json) => _$MemberFromJson(json);
  Map<String, dynamic> toJson() => _$MemberToJson(this);

  String getPublicKey() => publicKey;
  bool isActive() => status == MemberStatus.active;
  bool isOnline() => DateTime.now().difference(lastSeen).inMinutes < 5;

  void updateLastSeen() {
    lastSeen = DateTime.now();
  }

  bool hasPermission(Permission permission) {
    return permissions.contains(permission) ||
        _getRolePermissions(role).contains(permission);
  }

  List<Permission> _getRolePermissions(MemberRole role) {
    switch (role) {
      case MemberRole.creator:
        return Permission.values;
      case MemberRole.admin:
        return [
          Permission.sendMessage,
          Permission.sendFile,
          Permission.sendImage,
          Permission.sendVoice,
          Permission.inviteMember,
          Permission.kickMember,
          Permission.changeGroupInfo,
          Permission.changeMemberRole,
          Permission.rotateKeys,
          Permission.viewGroupLogs,
        ];
      case MemberRole.moderator:
        return [
          Permission.sendMessage,
          Permission.sendFile,
          Permission.sendImage,
          Permission.sendVoice,
          Permission.inviteMember,
          Permission.kickMember,
        ];
      case MemberRole.member:
        return [
          Permission.sendMessage,
          Permission.sendFile,
          Permission.sendImage,
          Permission.sendVoice,
        ];
    }
  }
}

enum MemberRole { creator, admin, moderator, member }

enum MemberStatus { active, inactive, kicked, left }

enum Permission {
  // 消息权限
  sendMessage,
  sendFile,
  sendImage,
  sendVoice,

  // 群组管理权限
  inviteMember,
  kickMember,
  changeGroupInfo,
  changeMemberRole,

  // 高级权限
  rotateKeys,
  viewGroupLogs,
  deleteGroup,
}

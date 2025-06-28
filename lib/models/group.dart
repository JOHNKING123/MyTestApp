import 'package:json_annotation/json_annotation.dart';
import 'member.dart';

part 'group.g.dart';

@JsonSerializable()
class Group {
  final String id;
  final String name;
  final String creatorId;
  final DateTime createdAt;
  final GroupKeyPair groupKeys;
  SessionKey sessionKey;
  List<Member> members;
  GroupStatus status;

  // 元数据
  final String description;
  final int maxMembers;
  final GroupSettings settings;

  Group({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.createdAt,
    required this.groupKeys,
    required this.sessionKey,
    List<Member>? members,
    this.status = GroupStatus.active,
    this.description = '',
    this.maxMembers = 100,
    this.settings = const GroupSettings(),
  }) : members = members ?? [];

  factory Group.fromJson(Map<String, dynamic> json) {
    final rawMembers = (json['members'] as List<dynamic>?) ?? [];
    // 根据userId 去重
    final memberMap = <String, Member>{};
    for (final e in rawMembers) {
      final m = Member.fromJson(e as Map<String, dynamic>);
      if (m.userId.isNotEmpty) {
        memberMap[m.userId] = m; // 后面的会覆盖前面的
      }
    }
    final members = memberMap.values.toList();
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      creatorId: json['creatorId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      groupKeys: GroupKeyPair.fromJson(
        json['groupKeys'] as Map<String, dynamic>,
      ),
      sessionKey: SessionKey.fromJson(
        json['sessionKey'] as Map<String, dynamic>,
      ),
      members: members,
      status: json['status'] == null
          ? GroupStatus.active
          : GroupStatus.values.firstWhere(
              (e) => e.toString() == 'GroupStatus.${json['status']}',
              orElse: () => GroupStatus.active,
            ),
      description: json['description'] as String? ?? '',
      maxMembers: (json['maxMembers'] as num?)?.toInt() ?? 100,
      settings: json['settings'] == null
          ? const GroupSettings()
          : GroupSettings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }
  Map<String, dynamic> toJson() => _$GroupToJson(this);

  bool addMember(Member member) {
    if (members.length >= maxMembers) return false;
    if (members.any((m) => m.userId == member.userId)) return false;
    // 如果userId为空，则不添加
    if (member.userId.isEmpty) return false;
    members.add(member);
    return true;
  }

  bool removeMember(String memberId) {
    final index = members.indexWhere((m) => m.id == memberId);
    if (index == -1) return false;
    members.removeAt(index);
    return true;
  }

  void updateSessionKey(SessionKey newKey) {
    sessionKey = newKey;
  }

  int get memberCount => members.length;
  bool isMember(String memberId) => members.any((m) => m.userId == memberId);
}

@JsonSerializable()
class GroupKeyPair {
  final String publicKey;
  final String privateKey;
  final DateTime createdAt;
  final KeyAlgorithm algorithm;

  GroupKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
    this.algorithm = KeyAlgorithm.ecdsa,
  });

  factory GroupKeyPair.fromJson(Map<String, dynamic> json) =>
      _$GroupKeyPairFromJson(json);
  Map<String, dynamic> toJson() => {
    'publicKey': publicKey,
    'privateKey': "########",
    'createdAt': createdAt.toIso8601String(),
    'algorithm': algorithm.toString().split('.').last,
  };

  String getPublicKey() => publicKey;
  String getPrivateKey() => privateKey;
  bool isValid() => publicKey.isNotEmpty && privateKey.isNotEmpty;
}

@JsonSerializable()
class SessionKey {
  final String key;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int version;

  SessionKey({
    required this.key,
    required this.createdAt,
    required this.expiresAt,
    required this.version,
  });

  factory SessionKey.fromJson(Map<String, dynamic> json) =>
      _$SessionKeyFromJson(json);
  Map<String, dynamic> toJson() => _$SessionKeyToJson(this);

  bool isExpired() => DateTime.now().isAfter(expiresAt);
  int getVersion() => version;
}

@JsonSerializable()
class GroupSettings {
  final bool allowMemberInvite;
  final bool allowMessageEdit;
  final bool allowMessageDelete;
  final int messageRetentionDays;

  const GroupSettings({
    this.allowMemberInvite = true,
    this.allowMessageEdit = true,
    this.allowMessageDelete = true,
    this.messageRetentionDays = 30,
  });

  factory GroupSettings.fromJson(Map<String, dynamic> json) =>
      _$GroupSettingsFromJson(json);
  Map<String, dynamic> toJson() => _$GroupSettingsToJson(this);
}

enum GroupStatus { active, inactive, disbanded, unavailable }

enum KeyAlgorithm { rsa, ecdsa, ed25519 }

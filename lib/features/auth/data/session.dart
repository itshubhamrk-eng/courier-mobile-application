/// Signed-in user, built from courier-service `LoginResponse` (login and refresh
/// return the same shape).
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.userId,
    required this.companyId,
    required this.email,
    required this.displayName,
    required this.roles,
    required this.permissions,
    this.branchId,
    this.hubId,
    this.companyName,
    this.companyLogo,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final String userId;
  final String companyId;
  final String email;
  final String displayName;
  final Set<String> roles;
  final Set<String> permissions;
  final String? branchId;
  final String? hubId;
  final String? companyName;
  final String? companyLogo;

  /// The branch (or hub) whose work this user does. Null means the account is
  /// not staffed at a branch and cannot use this app.
  String? get operatingBranchId => branchId ?? hubId;

  bool can(String permission) => permissions.contains(permission);

  /// Refresh a little before the server's expiry so requests rarely hit a 401.
  bool get accessExpiringSoon => DateTime.now().isAfter(accessExpiresAt.subtract(const Duration(seconds: 30)));

  factory Session.fromLoginResponse(Map<String, dynamic> json) {
    Set<String> strings(Object? v) => v is List ? v.whereType<String>().toSet() : <String>{};
    final expiresIn = (json['expiresIn'] as num?)?.toInt() ?? 0;
    return Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      accessExpiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: json['userId'] as String,
      companyId: json['companyId'] as String,
      email: json['email'] as String? ?? '',
      displayName: (json['displayName'] as String?) ?? (json['email'] as String? ?? ''),
      roles: strings(json['roles']),
      permissions: strings(json['permissions']),
      branchId: json['branchId'] as String?,
      hubId: json['hubId'] as String?,
      companyName: json['companyName'] as String?,
      companyLogo: json['companyLogo'] as String?,
    );
  }
}

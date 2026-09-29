class UserModel {
  final int id;
  final String phoneNumber;
  final String? name;
  final String? email;
  final DateTime? birthday;
  final String role;
  final bool isActive;

  UserModel({
    required this.id,
    required this.phoneNumber,
    this.name,
    this.email,
    this.birthday,
    required this.role,
    required this.isActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime? birthday;
    if (json['birthday'] != null) {
      try {
        birthday = DateTime.parse(json['birthday'] as String);
      } catch (e) {
        birthday = null;
      }
    }
    
    return UserModel(
      id: json['id'] as int,
      phoneNumber: json['phoneNumber'] as String,
      name: json['name'] as String?,
      email: json['email'] as String?,
      birthday: birthday,
      role: json['role'] as String? ?? 'customer',
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'name': name,
      'email': email,
      'birthday': birthday?.toIso8601String().split('T')[0],
      'role': role,
      'isActive': isActive,
    };
  }
}


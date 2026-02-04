import 'model_utils.dart';

class UserModel {
  final String id;
  final String email;
  final String name;
  final String? avatar;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    this.avatar,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: ModelUtils.parseId(json),
      email: json['email'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        if (avatar != null) 'avatar': avatar,
      };
}

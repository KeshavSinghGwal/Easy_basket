class AddressModel {
  final int id;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String state;
  final String pincode;
  final String? landmark;
  final bool isDefault;
  final String? latitude;
  final String? longitude;
  final String? tag; // home, office, other, etc.

  AddressModel({
    required this.id,
    required this.addressLine1,
    this.addressLine2,
    required this.city,
    required this.state,
    required this.pincode,
    this.landmark,
    required this.isDefault,
    this.latitude,
    this.longitude,
    this.tag,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'] as int,
      addressLine1: json['addressLine1'] as String,
      addressLine2: json['addressLine2'] as String?,
      city: json['city'] as String,
      state: json['state'] as String,
      pincode: json['pincode'] as String,
      landmark: json['landmark'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
      tag: json['tag'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'addressLine1': addressLine1,
      'addressLine2': addressLine2,
      'city': city,
      'state': state,
      'pincode': pincode,
      'landmark': landmark,
      'isDefault': isDefault,
      'latitude': latitude,
      'longitude': longitude,
      'tag': tag,
    };
  }

  String get fullAddress {
    return '$addressLine1${addressLine2 != null ? ', $addressLine2' : ''}, $city, $state - $pincode';
  }
}


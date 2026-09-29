/// Campaign model — promo banners, offers, announcements
class CampaignModel {
  final int id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? ctaText;
  final String? ctaLink;
  final String placement;
  final int priority;
  final List<String> targetPincodes;
  final List<String> targetCities;
  final DateTime startsAt;
  final DateTime expiresAt;
  final bool isActive;
  final bool pushEnabled;
  final bool pushSent;

  CampaignModel({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.ctaText,
    this.ctaLink,
    required this.placement,
    required this.priority,
    required this.targetPincodes,
    required this.targetCities,
    required this.startsAt,
    required this.expiresAt,
    required this.isActive,
    required this.pushEnabled,
    required this.pushSent,
  });

  factory CampaignModel.fromJson(Map<String, dynamic> json) {
    return CampaignModel(
      id: json['id'] as int,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['imageUrl'] as String?,
      ctaText: json['ctaText'] as String?,
      ctaLink: json['ctaLink'] as String?,
      placement: json['placement'] as String? ?? 'hero_banner',
      priority: json['priority'] as int? ?? 0,
      targetPincodes: (json['targetPincodes'] as List?)?.map((e) => e.toString()).toList() ?? [],
      targetCities: (json['targetCities'] as List?)?.map((e) => e.toString()).toList() ?? [],
      startsAt: DateTime.parse(json['startsAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      isActive: json['isActive'] as bool? ?? true,
      pushEnabled: json['pushEnabled'] as bool? ?? false,
      pushSent: json['pushSent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'ctaText': ctaText,
    'ctaLink': ctaLink,
    'placement': placement,
    'priority': priority,
    'targetPincodes': targetPincodes,
    'targetCities': targetCities,
    'startsAt': startsAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'isActive': isActive,
    'pushEnabled': pushEnabled,
  };
}

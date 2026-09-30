part of '../levixel.dart';

enum LevixelMediaType { image, video }

enum LevixelTheme { light, dark }

enum LevixelActionLayout { list, grid }

enum LevixelEventType {
  opened,
  indexChange,
  mediaLoad,
  mediaError,
  action,
  dismiss
}

String _nonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be blank');
  }
  return value;
}

/// Stable media identity and native media locations.
@immutable
class LevixelMedia {
  LevixelMedia({
    required String id,
    required this.type,
    required String url,
    String? thumbnailUrl,
    String? posterUrl,
  })  : id = _nonEmpty(id, 'id'),
        url = _nonEmpty(url, 'url'),
        thumbnailUrl = thumbnailUrl == null
            ? null
            : _nonEmpty(thumbnailUrl, 'thumbnailUrl'),
        posterUrl =
            posterUrl == null ? null : _nonEmpty(posterUrl, 'posterUrl');

  final String id;
  final LevixelMediaType type;
  final String url;
  final String? thumbnailUrl;
  final String? posterUrl;

  Map<String, Object?> _toMap() => <String, Object?>{
        'id': id,
        'type': type.name,
        'url': url,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        if (posterUrl != null) 'posterUrl': posterUrl,
      };
}

/// The callback belongs to the opening snapshot, even if the host changes later.
@immutable
class LevixelAction {
  LevixelAction({
    required String id,
    required String label,
    String? icon,
    String? group,
    this.disabled = false,
    this.destructive = false,
    this.onSelected,
  })  : id = _nonEmpty(id, 'id'),
        label = _nonEmpty(label, 'label'),
        icon = icon == null ? null : _nonEmpty(icon, 'icon'),
        group = group == null ? null : _nonEmpty(group, 'group');

  final String id;
  final String label;
  final String? icon;
  final String? group;
  final bool disabled;
  final bool destructive;
  final ValueChanged<LevixelEvent>? onSelected;

  Map<String, Object?> _toMap() => <String, Object?>{
        'id': id,
        'label': label,
        if (icon != null) 'icon': icon,
        if (group != null) 'group': group,
        'disabled': disabled,
        'destructive': destructive,
      };
}

/// A native event whose media identity always refers to one opening snapshot.
@immutable
class LevixelEvent {
  LevixelEvent._(Map<Object?, Object?> value)
      : type = LevixelEventType.values.byName(value['type']! as String),
        payload = Map<String, Object?>.unmodifiable(
          (value['payload']! as Map<Object?, Object?>).cast<String, Object?>(),
        ),
        time = DateTime.fromMillisecondsSinceEpoch(
          (value['time']! as num).round(),
        );

  final LevixelEventType type;
  final Map<String, Object?> payload;
  final DateTime time;
  String get sessionId => payload['sessionId']! as String;
  String get galleryId => payload['galleryId']! as String;
  String get itemId => payload['itemId']! as String;
  int get index => payload['index']! as int;
  String? get actionId => payload['actionId'] as String?;
}

List<LevixelMedia> _mediaSnapshot(Iterable<LevixelMedia> items) {
  final result = List<LevixelMedia>.unmodifiable(items);
  final ids = <String>{};
  for (final item in result) {
    if (!ids.add(item.id)) {
      throw ArgumentError('Media IDs must be unique: ${item.id}');
    }
  }
  return result;
}

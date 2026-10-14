/// Filtrage local des résultats de supervision renvoyés par l'API.
class SuperAdminConsoleFilters {
  const SuperAdminConsoleFilters._();

  static List<Map<String, dynamic>> schools(
    List<Map<String, dynamic>> values, {
    String search = '',
    String status = 'all',
  }) {
    final needle = search.trim().toLowerCase();
    return values.where((school) {
      final rawAdmin = school['admin'];
      final admin = rawAdmin is Map ? rawAdmin : const <String, dynamic>{};
      final rawManagers = school['managers'];
      final managers = rawManagers is List ? rawManagers : const <dynamic>[];
      final searchable = [
        school['name'],
        school['code'],
        admin['display_name'],
        ...managers.whereType<Map>().map((m) => m['display_name']),
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return (needle.isEmpty || searchable.contains(needle)) &&
          (status == 'all' || school['subscription_effective_status'] == status);
    }).toList(growable: false);
  }

  static List<Map<String, dynamic>> activities(
    List<Map<String, dynamic>> values, {
    String search = '',
  }) {
    final needle = search.trim().toLowerCase();
    return values.where((event) {
      final searchable = [
        event['organization_name'],
        event['module'],
        event['event_type'],
        event['message'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return needle.isEmpty || searchable.contains(needle);
    }).toList(growable: false);
  }
}

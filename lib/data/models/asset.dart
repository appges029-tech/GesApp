class AssetSummary {
  const AssetSummary({
    required this.total,
    required this.inService,
    required this.maintenance,
    required this.outOfService,
    required this.missing,
    required this.totalAcquisitionValue,
    required this.warrantyExpiring,
    required this.openInventories,
  });
  final int total;
  final int inService;
  final int maintenance;
  final int outOfService;
  final int missing;
  final int totalAcquisitionValue;
  final int warrantyExpiring;
  final int openInventories;
}

class AssetItem {
  const AssetItem({
    required this.id,
    required this.assetNumber,
    required this.name,
    required this.categoryId,
    required this.categoryName,
    required this.condition,
    required this.status,
    required this.acquisitionValue,
    this.brand,
    this.model,
    this.serialNumber,
    this.locationId,
    this.locationName,
    this.employeeId,
    this.employeeName,
    this.photoPath,
    this.warrantyEndDate,
  });
  final String id;
  final String assetNumber;
  final String name;
  final String categoryId;
  final String categoryName;
  final String condition;
  final String status;
  final int acquisitionValue;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? locationId;
  final String? locationName;
  final String? employeeId;
  final String? employeeName;
  final String? photoPath;
  final DateTime? warrantyEndDate;
}

class AssetCategoryItem {
  const AssetCategoryItem({required this.id, required this.name, required this.active, this.description});
  final String id;
  final String name;
  final String? description;
  final bool active;
}

class AssetLocationItem {
  const AssetLocationItem({required this.id, required this.name, required this.type, required this.active, this.parentId, this.parentName, this.description});
  final String id;
  final String name;
  final String type;
  final bool active;
  final String? parentId;
  final String? parentName;
  final String? description;
}

class AssetMaintenanceItem {
  const AssetMaintenanceItem({required this.id, required this.assetId, required this.assetName, required this.type, required this.status, required this.cost, required this.startedAt, this.nextMaintenanceAt, this.provider, this.problem, this.expenseId});
  final String id;
  final String assetId;
  final String assetName;
  final String type;
  final String status;
  final int cost;
  final DateTime startedAt;
  final DateTime? nextMaintenanceAt;
  final String? provider;
  final String? problem;
  final String? expenseId;
}

class AssetInventorySessionItem {
  const AssetInventorySessionItem({required this.id, required this.label, required this.startedAt, required this.status, required this.total, required this.checked, required this.missing, required this.damaged});
  final String id;
  final String label;
  final DateTime startedAt;
  final String status;
  final int total;
  final int checked;
  final int missing;
  final int damaged;
}

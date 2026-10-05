class FamilyItem {
  const FamilyItem({
    required this.id,
    required this.name,
    this.primaryPhone,
    this.secondaryPhone,
    this.address,
    this.studentCount = 0,
  });

  final String id;
  final String name;
  final String? primaryPhone;
  final String? secondaryPhone;
  final String? address;
  final int studentCount;
}

class FamilyMember {
  const FamilyMember({
    required this.id,
    required this.fullName,
    required this.classroomName,
    required this.status,
  });

  final String id;
  final String fullName;
  final String classroomName;
  final String status;
}

class FamilyBalance {
  const FamilyBalance({required this.expected, required this.paid});
  final int expected;
  final int paid;
  int get outstanding => expected - paid;
}

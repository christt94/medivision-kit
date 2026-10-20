class ClinicalCase {
  final String id;
  final String patientId;
  final String title;
  final String indication;
  final String priority;
  final String status;
  final String createdBy;
  final String? assignedTo;
  final List<Map<String, dynamic>> studies;
  final List<Map<String, dynamic>> signoffs;

  const ClinicalCase({
    required this.id,
    required this.patientId,
    required this.title,
    required this.indication,
    required this.priority,
    required this.status,
    required this.createdBy,
    this.assignedTo,
    this.studies = const [],
    this.signoffs = const [],
  });

  factory ClinicalCase.fromJson(Map<String, dynamic> json) {
    return ClinicalCase(
      id: '${json['id'] ?? ''}',
      patientId: '${json['patient_id'] ?? ''}',
      title: '${json['title'] ?? 'Clinical case'}',
      indication: '${json['indication'] ?? ''}',
      priority: '${json['priority'] ?? 'ROUTINE'}',
      status: '${json['status'] ?? 'OPEN'}',
      createdBy: '${json['created_by'] ?? ''}',
      assignedTo: json['assigned_to']?.toString(),
      studies: _mapList(json['studies']),
      signoffs: _mapList(json['signoffs']),
    );
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }
}

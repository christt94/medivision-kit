class Patient {
  final String  id;
  final String  nom;
  final String  prenom;
  final String? sexe;
  final String? dateNais;
  final String  paysCode;
  final String? createdAt;

  const Patient({
    required this.id,
    required this.nom,
    required this.prenom,
    this.sexe,
    this.dateNais,
    this.paysCode = 'CM',
    this.createdAt,
  });

  String get fullName => '$prenom $nom';
  String get initials =>
    '${prenom.isNotEmpty ? prenom[0] : ""}${nom.isNotEmpty ? nom[0] : ""}'
      .toUpperCase();

  factory Patient.fromJson(Map<String, dynamic> j) => Patient(
    id:        j['id']        ?? '',
    nom:       j['nom']       ?? '',
    prenom:    j['prenom']    ?? '',
    sexe:      j['sexe'],
    dateNais:  j['date_naissance'] ?? j['date_nais'],  // handles both keys
    paysCode:  j['pays_code'] ?? 'CM',
    createdAt: j['created_at'],
  );

  Map<String, dynamic> toMap() => {
    'id':             id,
    'nom':            nom,
    'prenom':         prenom,
    'sexe':           sexe,
    'date_naissance': dateNais,
  };
}

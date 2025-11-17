class Lieu {
  int? id;
  String titre;
  String categorie;
  String image;
  double latitude;
  double longitude;
  String? commentaire;
  int? note;

  Lieu({
    this.id,
    required this.titre,
    required this.categorie,
    required this.image,
    required this.latitude,
    required this.longitude,
    this.commentaire,
    this.note,
  });

  factory Lieu.fromMap(Map<String, dynamic> map) => Lieu(
    id: map['id'],
    titre: map['titre'],
    categorie: map['categorie'],
    image: map['image'],
    latitude: map['latitude'],
    longitude: map['longitude'],
    commentaire: map['commentaire'],
    note: map['note'],
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'titre': titre,
    'categorie': categorie,
    'image': image,
    'latitude': latitude,
    'longitude': longitude,
    'commentaire': commentaire,
    'note': note,
  };
}

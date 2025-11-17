class Ville {
  String nom;
  double latitude;
  double longitude;
  String meteo;
  double tempActuelle;
  double tempMin;
  double tempMax;

  Ville({
    required this.nom,
    required this.latitude,
    required this.longitude,
    required this.meteo,
    required this.tempActuelle,
    required this.tempMin,
    required this.tempMax,
  });

  factory Ville.fromMap(Map<String, dynamic> map) => Ville(
    nom: map['nom'],
    latitude: map['latitude'],
    longitude: map['longitude'],
    meteo: map['meteo'],
    tempActuelle: map['tempActuelle'],
    tempMin: map['tempMin'],
    tempMax: map['tempMax'],
  );

  Map<String, dynamic> toMap() => {
    'nom': nom,
    'latitude': latitude,
    'longitude': longitude,
    'meteo': meteo,
    'tempActuelle': tempActuelle,
    'tempMin': tempMin,
    'tempMax': tempMax,
  };
}

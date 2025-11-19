import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart'; // Contient VilleData et fetchVilleData

class PagePrincipale extends StatefulWidget {
  const PagePrincipale({super.key});

  @override
  State<PagePrincipale> createState() => _PagePrincipaleState();
}

class _PagePrincipaleState extends State<PagePrincipale> {
  final TextEditingController _villeController = TextEditingController();

  String villeSelectionnee = "Paris";
  VilleData? villeData;
  bool isLoading = false;
  String? error;
  double? latitude; // Position GPS
  double? longitude; // Position GPS
  double? villeLat; // Position ville sélectionnée
  double? villeLon; // Position ville sélectionnée
  bool ajoutLieuEnCours = false;
  String? nomLieuTemp;

  bool villeFavorite = false;
  List<String> villesFavorites = [];
  List<Map<String, String>> lieux = [];

  String? villePrincipale;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initialiserVille();
  }

  /// ------------------ Initialisation ------------------
  Future<void> _initialiserVille() async {
    await _loadFavorites();

    final prefs = await SharedPreferences.getInstance();
    villePrincipale = prefs.getString('ville_principale');

    if (villePrincipale != null) {
      villeSelectionnee = villePrincipale!;
      await _selectionnerVille(villeSelectionnee);
      return;
    }

    // Géolocalisation
    try {
      String? currentCity = await _getCurrentCity();
      if (currentCity != null && currentCity.isNotEmpty) {
        villeSelectionnee = currentCity;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ville géolocalisée : $villeSelectionnee")),
        );
      }
    } catch (e) {
      debugPrint("Erreur géolocalisation: $e");
    }

    // Sélectionne seulement si villeSelectionnee est défini
    if (villeSelectionnee.isNotEmpty) {
      await _selectionnerVille(villeSelectionnee);
    }
  }

  /// ------------------ Géolocalisation ------------------
  Future<String?> _getCurrentCity() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }

      if (permission == LocationPermission.deniedForever) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      latitude = position.latitude;
      longitude = position.longitude;
      debugPrint(latitude.toString());
      debugPrint(longitude.toString());
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      debugPrint("erreur");
      if (placemarks.isNotEmpty) {
        return placemarks.first.locality;
      }
    } catch (e) {
      debugPrint("pas de ville trouvée: $e");
    }
    return null;
  }

  /// ------------------ Gestion API ------------------
  Future<void> _fetchVille(String ville) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      final data = await fetchVilleData(ville);
      setState(() {
        villeSelectionnee = data.nom;
        villeData = data;
      });
      _checkFavorite();
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  /// ------------------ Gestion lieux ------------------
  Future<void> _loadLieux(String ville) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('lieux_$ville') ?? [];
    setState(() {
      lieux = saved
          .map((e) => Map<String, String>.from(json.decode(e)))
          .toList();
    });
  }

  Future<void> _saveLieux(String ville) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = lieux.map((e) => json.encode(e)).toList();
    await prefs.setStringList('lieux_$ville', saved);
  }

  void _ajouterLieu() {
    final nomController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom du lieu'),
        content: TextField(
          controller: nomController,
          decoration: const InputDecoration(labelText: 'Nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              nomLieuTemp = nomController.text.trim();
              ajoutLieuEnCours = true;

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Cliquez sur la carte pour placer le lieu"),
                ),
              );
            },
            child: const Text('Placer sur la carte'),
          ),
        ],
      ),
    );
  }

  Widget _buildLieuCard(Map<String, String> lieu) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(lieu['titre']!),
        trailing: const Icon(Icons.location_searching),
        onTap: () {
          final lat = double.parse(lieu['lat']!);
          final lon = double.parse(lieu['lon']!);

          _mapController.move(LatLng(lat, lon), 15);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Centré sur ${lieu['titre']}")),
          );
        },
      ),
    );
  }

  /// ------------------ Gestion favoris ------------------
  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList('villes_favorites') ?? [];
    setState(() {
      villesFavorites = favs;
    });
    _checkFavorite();
  }

  Future<void> _toggleFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    if (villeFavorite) {
      villesFavorites.remove(villeSelectionnee);
    } else {
      if (!villesFavorites.contains(villeSelectionnee)) {
        villesFavorites.add(villeSelectionnee);
      }
    }
    await prefs.setStringList('villes_favorites', villesFavorites);
    _checkFavorite();
  }

  void _checkFavorite() {
    setState(() {
      villeFavorite = villesFavorites.contains(villeSelectionnee);
    });
  }

  Future<void> _setVillePrincipale(String ville) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ville_principale', ville);
    setState(() {
      villePrincipale = ville;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$ville est maintenant la ville principale 🌆')),
    );
  }
  Future<void> _showLieuFromMapClick(LatLng latlng) async {
  final url = Uri.parse(
    "https://nominatim.openstreetmap.org/reverse?lat=${latlng.latitude}&lon=${latlng.longitude}&format=json&addressdetails=1",
  );

  final response = await http.get(url, headers: {
    "User-Agent": "FlutterApp"
  });

  if (response.statusCode != 200) return;

  final data = jsonDecode(response.body);

  // Nom trouvé par Nominatim
  String nom =
      data["name"] ??
      data["display_name"] ??
      "Lieu sans nom";

  // Affiche une bottom sheet
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nom,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text("Latitude : ${latlng.latitude}"),
            Text("Longitude : ${latlng.longitude}"),

            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final nouveauLieu = {
                  'titre': nom,
                  'lat': latlng.latitude.toString(),
                  'lon': latlng.longitude.toString(),
                };

                setState(() {
                  lieux.add(nouveauLieu);
                });
                _saveLieux(villeSelectionnee);

                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$nom ajouté aux lieux")),
                );
              },
              icon: const Icon(Icons.add_location_alt),
              label: const Text("Ajouter ce lieu"),
            ),
          ],
        ),
      );
    },
  );
}


  /// ------------------ Recherche ------------------
  void _onSearch() async {
    final query = _villeController.text.trim();
    if (query.isEmpty) return;
    await _selectionnerVille(query);
  }

  Future<void> _selectionnerVille(String ville) async {
    setState(() {
      isLoading = true;
      error = null;
    });

    try {
      // 1️⃣ Récupérer les données météo via ton API (VilleData)
      final data = await fetchVilleData(ville);
      setState(() {
        villeSelectionnee = data.nom;
        villeData = data;
      });

      // 2️⃣ Charger les lieux enregistrés
      await _loadLieux(ville);

      // 3️⃣ Récupérer les coordonnées de la ville via Nominatim
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$ville&format=json&limit=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'FlutterApp'},
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData.isNotEmpty) {
          setState(() {
            villeLat = double.parse(jsonData[0]['lat']);
            villeLon = double.parse(jsonData[0]['lon']);
          });
        }
      }

      // 4️⃣ Si pas de ville trouvée mais position GPS dispo, utiliser la position GPS
      if (villeLat == null || villeLon == null) {
        if (latitude != null && longitude != null) {
          villeLat = latitude;
          villeLon = longitude;
        }
      }

      // 5️⃣ Centrer la carte
      _centrerCarteSurVille();
      _checkFavorite();
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _centrerCarteSurVille() {
    if (villeLat != null && villeLon != null) {
      _mapController.move(LatLng(villeLat!, villeLon!), 13.0);
    } else if (latitude != null && longitude != null) {
      _mapController.move(LatLng(latitude!, longitude!), 13.0);
    }
  }
  void _afficherDetailLieu(Map<String, String> lieu) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(lieu['titre']!),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Latitude : ${lieu['lat']}"),
          Text("Longitude : ${lieu['lon']}"),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              final lat = double.parse(lieu['lat']!);
              final lon = double.parse(lieu['lon']!);
              _mapController.move(LatLng(lat, lon), 15);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.location_searching),
            label: const Text("Centrer sur la carte"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Fermer"),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorez Votre Ville'),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Barre de recherche
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _villeController,
                    decoration: const InputDecoration(
                      labelText: 'Rechercher une ville',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _onSearch(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _onSearch,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Infos ville
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Text('Erreur: $error', style: const TextStyle(color: Colors.red))
            else if (villeData != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        villeData!.nom,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          villeFavorite ? Icons.star : Icons.star_border,
                          color: Colors.yellow[700],
                        ),
                        onPressed: _toggleFavorite,
                      ),
                    ],
                  ),
                  Text(
                    '☀️ ${villeData!.meteo}, ${villeData!.tempActuelle}°C '
                    '(Min: ${villeData!.tempMin}°C, Max: ${villeData!.tempMax}°C)',
                  ),
                ],
              ),

            // Carte
            Container(
              height: 300,
              margin: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.teal, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    onMapReady: () {
                      _centrerCarteSurVille();
                    },
                    onTap: (tapPosition, latlng) async {
                      if (ajoutLieuEnCours && nomLieuTemp != null) {
                        // ---- Cas 1 : On est dans l’ajout manuel d’un lieu ----
                        final nouveauLieu = {
                          'titre': nomLieuTemp!,
                          'lat': latlng.latitude.toString(),
                          'lon': latlng.longitude.toString(),
                        };

                        setState(() {
                          lieux.add(nouveauLieu);
                          ajoutLieuEnCours = false;
                          nomLieuTemp = null;
                        });

                        _saveLieux(villeSelectionnee);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              "Lieu ajouté : ${nouveauLieu['titre']}",
                            ),
                          ),
                        );
                      } 
                      else {
                        // ---- Cas 2 : On clique sur un lieu de la carte (pas enregistré) ----
                        await _showLieuFromMapClick(latlng);
                      }
                    },

                  ),

                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.app",
                    ),
                    MarkerLayer(
                      markers: [
                        // Ville sélectionnée
                        if (villeLat != null && villeLon != null)
                          Marker(
                            point: LatLng(villeLat!, villeLon!),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),

                        // Position GPS
                        if (latitude != null && longitude != null)
                          Marker(
                            point: LatLng(latitude!, longitude!),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blue,
                              size: 30,
                            ),
                          ),

                        // Lieux utilisateur
                        ...lieux.map((lieu) {
                          return Marker(
                            point: LatLng(
                              double.parse(lieu['lat']!),
                              double.parse(lieu['lon']!),
                            ),
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _afficherDetailLieu(lieu),
                              child: const Icon(
                                Icons.place,
                                color: Colors.green,
                                size: 35,
                              ),
                            ),

                          );
                        }).toList(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Villes favorites
            const SizedBox(height: 20),
            const Text(
              'Villes favorites :',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 8,
              children: villesFavorites.map((v) {
                return ActionChip(
                  label: Text(v),
                  onPressed: () async {
                    await _selectionnerVille(v);
                    _setVillePrincipale(v);
                  },
                );
              }).toList(),
            ),

            // Lieux
            const SizedBox(height: 20),
            const Text(
              'Lieux enregistrés :',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            ...lieux.map(_buildLieuCard),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _ajouterLieu,
        child: const Icon(Icons.add),
      ),
    );
  }
}

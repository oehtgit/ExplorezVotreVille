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
    final titreController = TextEditingController();
    final categorieController = TextEditingController();
    final imageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un nouveau lieu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titreController,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            TextField(
              controller: categorieController,
              decoration: const InputDecoration(labelText: 'Catégorie'),
            ),
            TextField(
              controller: imageController,
              decoration: const InputDecoration(labelText: 'Image URL'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final newLieu = {
                'titre': titreController.text,
                'categorie': categorieController.text,
                'image': imageController.text,
              };
              setState(() {
                lieux.add(newLieu);
              });
              _saveLieux(villeSelectionnee);
              Navigator.pop(context);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Widget _buildLieuCard(Map<String, String> lieu) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            lieu['image']!,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 60,
              height: 60,
              color: Colors.grey[300],
              child: const Icon(Icons.image_not_supported),
            ),
          ),
        ),
        title: Text(lieu['titre']!),
        subtitle: Text(lieu['categorie']!),
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
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.app",
                    ),
                    MarkerLayer(
                      markers: [
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

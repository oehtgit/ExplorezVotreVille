import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ville.dart';

class ApiService {
  static const weatherApiKey = 'VOTRE_CLE_API_OPENWEATHERMAP';

  static Future<Ville> fetchVilleData(String villeNom) async {
    // Étape 1 : géocodage via Nominatim
    final geoResponse = await http.get(
      Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$villeNom,France&format=json&limit=1',
      ),
    );

    final geoData = json.decode(geoResponse.body);
    if (geoData.isEmpty) throw Exception('Ville introuvable');

    final lat = double.parse(geoData[0]['lat']);
    final lon = double.parse(geoData[0]['lon']);

    // Étape 2 : météo via OpenWeatherMap
    final weatherResponse = await http.get(
      Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$weatherApiKey&units=metric&lang=fr',
      ),
    );

    final weatherData = json.decode(weatherResponse.body);

    return Ville(
      nom: villeNom,
      latitude: lat,
      longitude: lon,
      meteo: weatherData['weather'][0]['description'],
      tempActuelle: weatherData['main']['temp'].toDouble(),
      tempMin: weatherData['main']['temp_min'].toDouble(),
      tempMax: weatherData['main']['temp_max'].toDouble(),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/ville.dart';
import '../services/api_service.dart';

class VilleProvider extends ChangeNotifier {
  Ville? _villeSelectionnee;

  Ville? get villeSelectionnee => _villeSelectionnee;

  Future<void> selectVille(String villeNom) async {
    _villeSelectionnee = await ApiService.fetchVilleData(villeNom);
    notifyListeners();
  }
}

import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

class FruitsClassificationPage extends StatefulWidget {
  const FruitsClassificationPage({super.key});

  @override
  State<FruitsClassificationPage> createState() =>
      _FruitsClassificationPageState();
}

class _FruitsClassificationPageState extends State<FruitsClassificationPage> {
  // --- ÉTAT ---
  File? _imageFile;
  Uint8List? _webImage;
  String _result = "Aucun résultat";

  // --- INFERENCE ---
  late Interpreter _interpreter;
  late List<String> _labels;
  bool _modelReady = false;
  
  // ✅ Dimensions du modèle (détectées automatiquement)
  late int inputHeight;
  late int inputWidth;
  late int outputSize;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  // Charger le modèle TFLite (tflite_flutter)
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/model/model.tflite');

      // ✅ Détecter automatiquement les dimensions
      final inputShape = _interpreter.getInputTensor(0).shape;
      final outputShape = _interpreter.getOutputTensor(0).shape;
      
      debugPrint("📊 Input shape: $inputShape");
      debugPrint("📊 Output shape: $outputShape");
      
      // Input shape attendu: [1, height, width, 3]
      inputHeight = inputShape[1];
      inputWidth = inputShape[2];
      
      // Output shape attendu: [1, num_classes]
      outputSize = outputShape[1];

      // ✅ Vérifier si le widget est encore monté
      if (!mounted) return;

      final labelsData = await DefaultAssetBundle.of(
        context,
      ).loadString('assets/model/labels.txt');
      _labels = labelsData
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) {
            // ✅ Supprimer les numéros si présents (ex: "0 apple" -> "apple")
            final parts = e.split(' ');
            return parts.length > 1 && int.tryParse(parts[0]) != null
                ? parts.sublist(1).join(' ')
                : e;
          })
          .toList();

      setState(() => _modelReady = true);
      debugPrint("✅ Modèle chargé: ${inputWidth}x$inputHeight -> $outputSize classes");
      debugPrint("✅ Labels chargés: ${_labels.length} classes");
      
      if (_labels.length != outputSize) {
        debugPrint("⚠️ Attention: ${_labels.length} labels mais $outputSize sorties du modèle");
      }
    } catch (e) {
      debugPrint("❌ Erreur chargement modèle/labels: $e");
      if (mounted) {
        setState(() => _modelReady = false);
      }
    }
  }

  // 📸 Ouvrir la caméra
  Future<void> _openCamera() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImage = bytes;
          _imageFile = null;
        });
      } else {
        setState(() {
          _imageFile = File(pickedFile.path);
          _webImage = null;
        });
      }
    }
  }

  // 🔮 Prédiction (mobile seulement, via tflite_flutter)
  Future<void> _predict() async {
    if (kIsWeb) {
      setState(() => _result = "Prédiction non supportée sur Flutter Web 🌐");
      return;
    }
    if (!_modelReady) {
      setState(() => _result = "Modèle non prêt");
      return;
    }
    if (_imageFile == null) {
      setState(() => _result = "Aucune image pour prédire");
      return;
    }

    try {
      // 1) Décoder + redimensionner à la taille exacte du modèle
      final bytes = await _imageFile!.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() => _result = "Image invalide");
        return;
      }
      final resized = img.copyResize(
        decoded,
        width: inputWidth,
        height: inputHeight,
      );

      // 2) ✅ Construire l'input tensor [1, height, width, 3]
      // Certains modèles attendent une normalisation différente
      var input = List.generate(
        1,
        (_) => List.generate(
          inputHeight,
          (y) => List.generate(
            inputWidth,
            (x) {
              final pixel = resized.getPixel(x, y);
              
              // 🔄 OPTION 1: Normalisation [0, 1] (par défaut)
              return [
                pixel.r.toDouble() / 255.0,
                pixel.g.toDouble() / 255.0,
                pixel.b.toDouble() / 255.0,
              ];
              
              // 🔄 OPTION 2: Normalisation [-1, 1] (décommentez si nécessaire)
              // return [
              //   (pixel.r.toDouble() - 127.5) / 127.5,
              //   (pixel.g.toDouble() - 127.5) / 127.5,
              //   (pixel.b.toDouble() - 127.5) / 127.5,
              // ];
              
              // 🔄 OPTION 3: Sans normalisation [0, 255] (décommentez si nécessaire)
              // return [
              //   pixel.r.toDouble(),
              //   pixel.g.toDouble(),
              //   pixel.b.toDouble(),
              // ];
            },
          ),
        ),
      );

      // 3) ✅ Préparer l'output [1, outputSize]
      var output = List.generate(1, (_) => List.filled(outputSize, 0.0));

      // 4) ✅ Exécuter l'inférence
      _interpreter.run(input, output);

      // 4.5) ✅ Appliquer Softmax car le modèle utilise from_logits=True
      final logits = output[0];
      
      // Calcul de Softmax: exp(x) / sum(exp(x))
      final expValues = logits.map((x) => exp(x)).toList();
      final sumExp = expValues.reduce((a, b) => a + b);
      final probs = expValues.map((x) => x / sumExp).toList();
      
      // 5) Trouver la meilleure prédiction
      int bestIdx = 0;
      double bestProb = probs[0];
      
      // 📊 Afficher toutes les probabilités pour debug
      debugPrint("📊 Probabilités détectées:");
      for (int i = 0; i < probs.length; i++) {
        final label = i < _labels.length ? _labels[i] : "Classe $i";
        debugPrint("   $label: ${(probs[i] * 100).toStringAsFixed(2)}%");
      }
      
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > bestProb) {
          bestProb = probs[i];
          bestIdx = i;
        }
      }

      // 6) Afficher le résultat
      final labelText = bestIdx < _labels.length 
          ? _labels[bestIdx] 
          : "Classe $bestIdx";
          
      setState(() {
        _result = "$labelText : ${(bestProb * 100).toStringAsFixed(1)}%";
      });
      
      debugPrint("🎯 Prédiction finale: $labelText (${(bestProb * 100).toStringAsFixed(1)}%)");
      
    } catch (e, stackTrace) {
      debugPrint("❌ Erreur détaillée: $e");
      debugPrint("❌ Stack trace: $stackTrace");
      setState(() => _result = "Erreur de prédiction: $e");
    }
  }

  @override
  void dispose() {
    if (_modelReady) {
      _interpreter.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget = _webImage != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_webImage!, fit: BoxFit.cover),
          )
        : (_imageFile != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_imageFile!, fit: BoxFit.cover),
                )
              : const Text(
                  "Aucune image capturée 📷",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Fruits Classification"),
        backgroundColor: Colors.green,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCamera,
        backgroundColor: Colors.green,
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Zone image
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: Center(child: imageWidget),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _predict,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text(
                  "Predict",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                _result,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              if (!_modelReady)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    "Chargement du modèle...",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EmsiChatbotPage extends StatefulWidget {
  const EmsiChatbotPage({super.key});

  @override
  State<EmsiChatbotPage> createState() => _EmsiChatbotPageState();
}

class _EmsiChatbotPageState extends State<EmsiChatbotPage> {
  late final WebViewController controller;
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    
    // URL de votre application Streamlit
    // Par défaut, Streamlit tourne sur http://localhost:8501
    const String streamlitUrl = 'http://192.168.137.230:8501';
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              errorMessage = '';
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
              errorMessage = 'Erreur de chargement: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(streamlitUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('EMSI Chatbot'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              controller.reload();
            },
            tooltip: 'Rafraîchir',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (errorMessage.isEmpty)
            WebViewWidget(controller: controller)
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 80,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Assurez-vous que:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '1. Streamlit est en cours d\'exécution\n'
                      '2. L\'application tourne sur http://localhost:8501\n'
                      '3. Votre appareil peut accéder à localhost',
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          errorMessage = '';
                        });
                        controller.reload();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isLoading && errorMessage.isEmpty)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Colors.teal,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Chargement du chatbot...',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
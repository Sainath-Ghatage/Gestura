import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(SignBridgeApp());
}

class SignBridgeApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "SignBridge AI",
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: SpeechScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SpeechScreen extends StatefulWidget {
  @override
  _SpeechScreenState createState() => _SpeechScreenState();
}

class _SpeechScreenState extends State<SpeechScreen> {

  FlutterTts flutterTts = FlutterTts();
  TextEditingController textController = TextEditingController();

  String selectedLanguage = "en-US";

  Map<String, String> languages = {
    "English": "en-US",
    "Hindi": "hi-IN",
    "Marathi": "mr-IN"
  };

  Future speakText(String text) async {
    await flutterTts.stop();
    await flutterTts.setLanguage(selectedLanguage);
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setPitch(1.0);

    await flutterTts.speak(text);
  }

  simulateGesture(String gestureText) async {
    textController.text = gestureText;
    await speakText(gestureText);
  }

  stopSpeech() async {
    await flutterTts.stop();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text("SignBridge AI"),
        centerTitle: true,
      ),

      body: Center(
        child: Padding(
          padding: EdgeInsets.all(20),

          child: SizedBox(
            width: 420,

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                Text(
                  "Text to Speech Module",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                SizedBox(height: 30),

                DropdownButtonFormField<String>(
                  value: selectedLanguage,
                  decoration: InputDecoration(
                    labelText: "Select Language",
                    border: OutlineInputBorder(),
                  ),
                  items: languages.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.value,
                      child: Text(entry.key),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedLanguage = value!;
                    });
                  },
                ),

                SizedBox(height: 20),

                TextField(
                  controller: textController,
                  decoration: InputDecoration(
                    labelText: "Enter text",
                    border: OutlineInputBorder(),
                  ),
                ),

                SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    ElevatedButton.icon(
                      icon: Icon(Icons.volume_up),
                      label: Text("Speak"),
                      onPressed: () {
                        speakText(textController.text);
                      },
                    ),

                    SizedBox(width: 15),

                    ElevatedButton.icon(
                      icon: Icon(Icons.stop),
                      label: Text("Stop"),
                      onPressed: stopSpeech,
                    ),
                  ],
                ),

                SizedBox(height: 35),

                Text(
                  "Gesture Simulation",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                SizedBox(height: 20),

                Wrap(
                  spacing: 15,
                  runSpacing: 15,
                  alignment: WrapAlignment.center,
                  children: [

                    ElevatedButton(
                      onPressed: () {
                        simulateGesture("Hello");
                      },
                      child: Text("HELLO"),
                    ),

                    ElevatedButton(
                      onPressed: () {
                        simulateGesture("Thank you");
                      },
                      child: Text("THANK YOU"),
                    ),

                    ElevatedButton(
                      onPressed: () {
                        simulateGesture("Help");
                      },
                      child: Text("HELP"),
                    ),

                  ],
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}
# Gestura 🤟

> Breaking communication barriers with real-time sign language translation.

Gestura is a mobile application that facilitates seamless, two-way communication by translating sign language to text/speech, and speech/text back to sign language in real-time.

## ✨ Key Functionalities
This section outlines the core capabilities of the system:
* **Real-Time Sign Language to Text/Speech:** Uses the device camera to capture sign language gestures and instantly translates them into readable text and audible speech using on-device ML.
* **Speech/Text to Sign Language:** Converts spoken or typed input into appropriate visual representations of sign language.
* **Low Latency Translation:** Optimized locally to ensure natural, real-time conversation flows.

## 🛠️ Tech Stack & Resources
* **Frontend:** Flutter & Dart
* **Machine Learning:** TensorFlow Lite
* **Dataset:** [ASL Alphabet (Kaggle)](https://www.kaggle.com/datasets/grassknoted/asl-alphabet?resource=download)

## 🏗️ Project Architecture
An overview of the project architecture.

### Activity Diagram
*(Illustrates the user flow from capturing the video feed to displaying the translated text/speech output.)*

### System Block Diagram
*(Illustrates the data flow between the Flutter UI, the device camera, and the TensorFlow Lite inference engine.)*

## 🚀 Setup and Installation Guide
Follow these instructions to run the project locally.

### Prerequisites
* [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable version)
* Android Studio or VS Code
* A physical device or emulator

### Installation
1. Clone the repository:
   ```text
   git clone [https://github.com/Sainath-Ghatage/Gestura.git](https://github.com/Sainath-Ghatage/Gestura.git)
   ```

2. Navigate to the project directory:
    ```text
    cd Gestura
    ```
3. Install the required dependencies:
    ```text
    flutter pub get
    ```
4. Run the app:
    ```text
    flutter run
    ```
    
## 🤖 Ethical AI Usage Disclosure
In accordance with the hackathon's Technical Integrity & AI Policy, AI tools are permitted but must be disclosed.

* **Tools Used:** Gemini and Claude.
* **Purpose:** These tools were utilized for code assistance, debugging Flutter/Dart implementation, and structuring technical documentation.

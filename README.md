<p align="center">
  <img src="assets/icon/filegym_icon.jpg" width="140" height="140" style="border-radius: 28px; box-shadow: 0 4px 20px rgba(0,0,0,0.15);" alt="FileGym Logo" />
</p>

<h1 align="center">FileGym</h1>

<p align="center">
  <strong>Your files' personal trainer. Convert, resize, compress, and stitch files 100% offline.</strong>
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-v3.11.0+-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-v3.0+-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart" /></a>
  <a href="https://developer.android.com"><img src="https://img.shields.io/badge/Android-5.0_--_13.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-F5A623?style=for-the-badge" alt="License" /></a>
</p>

---

**FileGym** is a premium, local-first file utility suite for Android designed to stretch, shrink, and sculpt your files. Built with security and efficiency in mind, FileGym performs all conversion, extraction, and resizing operations **100% locally on your device**—no servers, no tracking, and zero external APIs.

---

## 🚀 Key Features

*   🎯 **Universal Conversion Pipeline**: Intelligent file analyzer detects true formats using magic bytes and automatically suggests appropriate offline converters.
*   📄 **Document & Text Suite**: 
    *   **PDF to PPTX**: Convert PDF documents directly into editable, structured PowerPoint (.pptx) slides.
    *   **Markdown Render**: Render `.md` documents into clean, styled PDFs or plain text.
    *   **PDF Page Extractor**: Render and extract all pages of a PDF as high-resolution JPEGs zipped into a single archive.
*   📊 **Spreadsheet & Data Engine**: Cross-convert between **JSON**, **CSV**, and **XLSX (Excel)** datasets.
*   🖼️ **Image Resizer & Stitcher**:
    *   Bulk-resize JPEG, PNG, and WebP images with precise target resolution and quality options.
    *   Stitch multiple images into a single paginated PDF document.
*   📦 **Media Compactor**: Archive, compile, and zip files into local zip archives.
*   🔔 **Advanced UI & Customization**: Supports custom sound alerts, native push notifications, background processing indicators, and dynamic Light/Dark mode themes.

---

## 🛡️ Offline-First & Privacy Secured

FileGym does not request internet access (`android.permission.INTERNET` is omitted from the production manifest). Your sensitive documents, databases, and photos never leave your device. All calculations, conversions, and rendering operations run inside lightweight native Kotlin processes and optimized Dart isolates.

---

## 📦 Sideloading & Installation

Since FileGym is distributed directly via GitHub, you can sideload the signed release APKs on your device:

1.  Navigate to the [Releases](../../releases) tab on this repository.
2.  Choose the version corresponding to your device's CPU architecture:
    *   **`app-arm64-v8a-release.apk`**: Recommended for all modern 64-bit Android devices.
    *   **`app-armeabi-v7a-release.apk`**: For older 32-bit Android devices.
    *   **`app-x86_64-release.apk`**: For Android emulators and x86-based processors.
3.  Download and open the APK file on your mobile device.
4.  If prompted to allow installations from unknown sources, toggle **Allow** for your browser or file manager.
5.  Tap **Install** and open **FileGym**!

---

## 🛠️ Tech Stack & Architecture

- **UI Framework**: Flutter (Dart)
- **Design Language**: Modern Glassmorphism & Custom Tailwind-inspired HSL Palettes
- **State Management**: Flutter Riverpod (`flutter_riverpod`)
- **Navigation Routing**: GoRouter (`go_router`)
- **Database**: Hive Local Storage (`hive` & `hive_flutter` for config settings)
- **Interactive UI Elements**: Lucide Icons (`lucide_icons`), Outfit Fonts (`google_fonts`), and micro-animations (`flutter_animate`).

---

## 👨‍💻 Developer & Team

- **Developer**: Pondara Akhil Behara
- **Academic Focus**: Artificial Intelligence & Data Science (AI & DS)
- **Institution**: Chaitanya Engineering College, Kommadi, Visakhapatnam

---

## 🤝 Contributing

We welcome contributions from developers, designers, and testers! 
1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for details.

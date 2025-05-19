# Vineyard Inventory (Flutter)

A native mobile application for vineyard inventory management with QR code scanning capabilities.

## Features

- Scan QR codes to identify individual vines
- Import QR codes from gallery photos
- Track vine positions in the vineyard (field, row, spot)
- Record vine details (variety, rootstock, planting year, nursery)
- Mark vines as dead with date tracking
- Track maintenance activities for each vine
- Report and manage issues with vines
- Extract vine IDs from URLs in QR codes (format: http://vineinfo.isleta.abqwebdev.com/inventory/ID2023-02210)
- Camera flash control for better scanning in low light conditions
- Offline support with local SQLite database

## Prerequisites

- Flutter 3.19.0 or higher
- Dart 3.4.0 or higher
- Android Studio / Xcode (for running on physical devices)

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/vineyard-inventory-flutter.git
   cd vineyard-inventory-flutter
   ```

2. Install dependencies:
   ```
   flutter pub get
   ```

3. Run the app in debug mode:
   ```
   flutter run
   ```

4. Build release version for Android:
   ```
   flutter build apk
   ```

5. Build release version for iOS:
   ```
   flutter build ios
   ```

## Project Structure

- `/lib`
  - `/models` - Data models for vines, maintenance, and issues
  - `/screens` - UI screens for different app features
  - `/services` - Business logic and database operations

## QR Code Format

The application processes QR codes in two formats:

1. Plain alphanumeric identifier corresponding to the `alphaNumericID` field in the database
2. URL format: `http://vineinfo.isleta.abqwebdev.com/inventory/ID2023-02210` (the ID portion after the last slash is extracted)

## Database Structure

The application uses SQLite for local data storage with the following tables:

- **vines**: Stores information about each vine
- **maintenanceTypes**: Types of maintenance activities
- **maintenanceActivities**: Records of maintenance performed on vines
- **vineIssues**: Issues reported for specific vines

## Camera Permissions

This app requires camera permissions to scan QR codes. The first time you use the scanner, you'll be prompted to grant permissions.

## Best Practices for QR Scanning

- Ensure good lighting for optimal QR code recognition
- Keep the camera steady and at a distance of 6-8 inches from the code
- For difficult scanning conditions, use the flash button or gallery import option

## Credits

Built with Flutter, mobile_scanner, sqflite, and flutter_form_builder.
# vineyard_inventory_flutter

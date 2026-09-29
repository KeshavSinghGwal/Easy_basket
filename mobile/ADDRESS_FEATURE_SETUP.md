# 📍 Address Management Feature - Setup Guide

## ✅ Features Implemented

1. **Location Picker** - Get address from current location
2. **Map Picker** - Select location on interactive map
3. **Address Tags** - Mark addresses as Home, Office, or Other
4. **Address Form** - Complete address details
5. **Address List** - View all saved addresses with tags

## 🗺️ Google Maps Setup (Required for Map Feature)

### Step 1: Get Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable **Maps SDK for Android** and **Maps SDK for iOS**
4. Create API Key
5. Restrict the key to your app (optional but recommended)

### Step 2: Add API Key to Android

Edit `android/app/src/main/AndroidManifest.xml`:

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_ACTUAL_API_KEY_HERE"/>
```

### Step 3: Add API Key to iOS (if needed)

Edit `ios/Runner/AppDelegate.swift`:

```swift
GMSServices.provideAPIKey("YOUR_ACTUAL_API_KEY_HERE")
```

## 📱 How It Works

### 1. Add Address Flow

1. Tap "Add Address" button
2. Choose location method:
   - **Use Current Location** - Automatically gets your location
   - **Pick on Map** - Select location on interactive map
3. Select address tag (Home, Office, Other)
4. Fill in address details (auto-filled from location)
5. Save address

### 2. Map Picker Features

- Interactive Google Maps
- Drag marker to adjust location
- Tap map to select location
- Shows address in real-time
- "Current Location" button to recenter

### 3. Address Tags

- **Home** 🏠 - For home address
- **Office** 🏢 - For office address  
- **Other** 📍 - For other locations

Tags are displayed in the address list for easy identification.

## 🔧 Permissions

The app requests location permissions automatically:
- **Android**: Already configured in AndroidManifest.xml
- **iOS**: Add to `ios/Runner/Info.plist`:
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>We need your location to set delivery address</string>
  ```

## 🚀 Usage

### From Home Screen
- Tap address bar at top → Add address

### From Address List
- Tap "+" button → Add new address

### Features Available
- ✅ Current location detection
- ✅ Map-based location picker
- ✅ Address auto-fill from coordinates
- ✅ Tag selection (Home/Office/Other)
- ✅ Default address setting
- ✅ Address list with tags

## ⚠️ Important Notes

1. **Google Maps API Key** is required for map feature
2. **Location Permission** must be granted
3. **Internet Connection** needed for geocoding
4. Map will show error without API key, but location picker still works

## 🐛 Troubleshooting

### Map not showing
- Check Google Maps API key is set
- Verify API key has Maps SDK enabled
- Check internet connection

### Location not working
- Grant location permissions
- Enable location services on device
- Check app permissions in settings

### Address not auto-filling
- Check internet connection
- Verify geocoding service is working
- Try manual entry as fallback

## 📝 Backend Changes

The backend now supports:
- `tag` field in Address entity
- Tag filtering and display
- Location coordinates (latitude/longitude)

All changes are backward compatible!


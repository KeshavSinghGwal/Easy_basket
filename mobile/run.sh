#!/bin/bash

# Easy Basket Flutter App - Run Script
# This script helps you run the Flutter app with proper configuration

echo "🚀 Easy Basket Flutter App - Setup & Run"
echo "=========================================="
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed!"
    echo "Please install Flutter from: https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter found: $(flutter --version | head -n 1)"
echo ""

# Check if we're in the mobile directory
if [ ! -f "pubspec.yaml" ]; then
    echo "⚠️  Not in mobile directory. Changing to mobile directory..."
    cd mobile 2>/dev/null || {
        echo "❌ mobile directory not found!"
        exit 1
    }
fi

# Install dependencies
echo "📦 Installing dependencies..."
flutter pub get

if [ $? -ne 0 ]; then
    echo "❌ Failed to install dependencies!"
    exit 1
fi

echo "✅ Dependencies installed"
echo ""

# Detect platform
PLATFORM=""
if [ "$1" == "android" ] || [ "$1" == "a" ]; then
    PLATFORM="android"
elif [ "$1" == "ios" ] || [ "$1" == "i" ]; then
    PLATFORM="ios"
elif [ "$1" == "web" ] || [ "$1" == "w" ]; then
    PLATFORM="web"
else
    # Auto-detect connected devices
    echo "🔍 Detecting connected devices..."
    DEVICES=$(flutter devices)
    if echo "$DEVICES" | grep -q "Chrome"; then
        PLATFORM="web"
    elif echo "$DEVICES" | grep -q "iPhone"; then
        PLATFORM="ios"
    elif echo "$DEVICES" | grep -q "Android"; then
        PLATFORM="android"
    else
        echo "⚠️  No device detected. Available options:"
        echo "   - Run with: ./run.sh android (for Android)"
        echo "   - Run with: ./run.sh ios (for iOS)"
        echo "   - Run with: ./run.sh web (for Web)"
        exit 1
    fi
fi

echo "📱 Platform: $PLATFORM"
echo ""

# Show API configuration reminder
echo "⚠️  IMPORTANT: API Configuration"
echo "================================"
echo "Make sure your backend is running on http://localhost:3000"
echo ""
echo "Update API URL in lib/config/app_config.dart:"
echo "  - Android Emulator: 'http://10.0.2.2:3000/api'"
echo "  - iOS Simulator: 'http://localhost:3000/api'"
echo "  - Physical Device: 'http://YOUR_IP:3000/api'"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Run the app
echo ""
echo "🎯 Starting Flutter app..."
echo ""

if [ "$PLATFORM" == "web" ]; then
    flutter run -d chrome
elif [ "$PLATFORM" == "ios" ]; then
    flutter run -d ios
else
    flutter run -d android
fi


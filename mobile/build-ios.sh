#!/bin/bash

# iOS Build Script for Easy Basket
# This script helps build the app for iOS physical devices

set -e

echo "🚀 Easy Basket - iOS Build Script"
echo "=================================="
echo ""

# Check if CocoaPods is installed
if ! command -v pod &> /dev/null; then
    echo "❌ CocoaPods is not installed!"
    echo ""
    echo "Please install CocoaPods first:"
    echo "  sudo gem install cocoapods"
    echo "  OR"
    echo "  brew install cocoapods"
    echo ""
    exit 1
fi

echo "✅ CocoaPods found"
echo ""

# Navigate to iOS directory
cd ios

# Install/Update pods
echo "📦 Installing iOS dependencies..."
pod install

echo ""
echo "✅ Dependencies installed"
echo ""

# Go back to mobile directory
cd ..

# Check for connected devices
echo "📱 Checking for connected iOS devices..."
DEVICES=$(flutter devices | grep -i ios || echo "")

if [ -z "$DEVICES" ]; then
    echo ""
    echo "⚠️  No iOS device detected!"
    echo ""
    echo "Please:"
    echo "  1. Connect your iPhone/iPad via USB"
    echo "  2. Unlock your device"
    echo "  3. Trust this computer if prompted"
    echo "  4. Run this script again"
    echo ""
    echo "Or build for simulator:"
    echo "  flutter run -d ios"
    echo ""
    exit 1
fi

echo ""
echo "✅ iOS device detected"
echo ""
echo "Available devices:"
flutter devices | grep -i ios
echo ""

# Build and run
echo "🔨 Building and installing on device..."
echo ""

# Try to run on first iOS device found
DEVICE_ID=$(flutter devices | grep -i ios | head -1 | awk '{print $5}' | tr -d '()')

if [ -z "$DEVICE_ID" ]; then
    echo "❌ Could not detect device ID"
    echo ""
    echo "Please run manually:"
    echo "  flutter devices"
    echo "  flutter run -d <device-id>"
    exit 1
fi

echo "Installing on device: $DEVICE_ID"
echo ""

flutter run -d "$DEVICE_ID"


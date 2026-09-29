#!/bin/bash

# Script to build release App Bundle for Google Play Store

echo "🏗️  Building Easy Basket Release App Bundle"
echo ""

# Navigate to mobile directory
cd "$(dirname "$0")" || exit

# Check if keystore exists
if [ ! -f "android/easy-basket-key.jks" ]; then
    echo "⚠️  Keystore not found!"
    echo ""
    echo "Please generate keystore first:"
    echo "  ./generate-keystore.sh"
    echo ""
    echo "Or manually create it:"
    echo "  cd android"
    echo "  keytool -genkey -v -keystore easy-basket-key.jks \\"
    echo "    -keyalg RSA -keysize 2048 -validity 10000 \\"
    echo "    -alias easy-basket-key"
    echo ""
    exit 1
fi

# Check environment variables
if [ -z "$KEYSTORE_PASSWORD" ] || [ -z "$KEY_PASSWORD" ]; then
    echo "⚠️  Environment variables not set!"
    echo ""
    echo "Please set KEYSTORE_PASSWORD and KEY_PASSWORD:"
    echo "  export KEYSTORE_PASSWORD=\"your_keystore_password\""
    echo "  export KEY_PASSWORD=\"your_key_password\""
    echo ""
    read -p "Continue with manual password entry? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build App Bundle
echo "🔨 Building App Bundle (AAB)..."
flutter build appbundle --release

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "📁 App Bundle location:"
    echo "   build/app/outputs/bundle/release/app-release.aab"
    echo ""
    echo "📤 Next steps:"
    echo "   1. Upload app-release.aab to Google Play Console"
    echo "   2. Go to: https://play.google.com/console"
    echo "   3. Create new release in Production"
    echo ""
else
    echo ""
    echo "❌ Build failed. Please check the errors above."
    exit 1
fi


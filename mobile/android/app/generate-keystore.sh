#!/bin/bash

# Keystore Generation Script for Easy Basket
# This script helps generate the signing keystore for Google Play Store

echo "=========================================="
echo "Easy Basket - Keystore Generation"
echo "=========================================="
echo ""

# Find Java from Android Studio
JAVA_PATH="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin"

if [ ! -f "$JAVA_PATH/keytool" ]; then
    echo "❌ Error: Could not find keytool in Android Studio"
    echo "Please make sure Android Studio is installed at:"
    echo "/Applications/Android Studio.app"
    exit 1
fi

echo "✅ Found Java keytool: $JAVA_PATH/keytool"
echo ""

# Navigate to the app directory
cd "$(dirname "$0")"

echo "📁 Current directory: $(pwd)"
echo ""
echo "You will be asked to enter:"
echo "  1. Keystore password (at least 6 characters) - SAVE THIS!"
echo "  2. Your name or company name"
echo "  3. Organizational unit (optional - press Enter)"
echo "  4. Organization name"
echo "  5. City"
echo "  6. State/Province"
echo "  7. Country code (2 letters, e.g., IN, US)"
echo "  8. Key password (can be same as keystore password)"
echo ""
echo "⚠️  IMPORTANT: Save your passwords securely!"
echo "   You'll need them for all future app updates."
echo ""
read -p "Press Enter to continue..."

echo ""
echo "Generating keystore..."
echo ""

# Generate keystore
"$JAVA_PATH/keytool" -genkey -v \
    -keystore easy-basket-key.jks \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias easy-basket-key

if [ $? -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✅ Keystore generated successfully!"
    echo "=========================================="
    echo ""
    echo "📁 Location: $(pwd)/easy-basket-key.jks"
    echo ""
    echo "⚠️  NEXT STEPS:"
    echo "1. Save your keystore password securely"
    echo "2. Save your key password securely"
    echo "3. Set environment variables (see guide)"
    echo ""
    echo "To set environment variables, add to ~/.zshrc:"
    echo "  export KEYSTORE_PASSWORD=\"your_keystore_password\""
    echo "  export KEY_PASSWORD=\"your_key_password\""
    echo ""
else
    echo ""
    echo "❌ Error: Failed to generate keystore"
    echo "Please try again or check the error messages above."
    exit 1
fi

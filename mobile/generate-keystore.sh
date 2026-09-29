#!/bin/bash

# Script to generate Android signing keystore for Easy Basket

echo "🔐 Generating Android Signing Keystore for Easy Basket"
echo ""

# Navigate to android directory
cd "$(dirname "$0")/android" || exit

# Check if keystore already exists
if [ -f "easy-basket-key.jks" ]; then
    echo "⚠️  Keystore already exists: easy-basket-key.jks"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Aborted. Keystore not generated."
        exit 1
    fi
    rm -f easy-basket-key.jks
fi

# Prompt for keystore details
echo "Enter keystore details (keep these safe!):"
read -p "Keystore password: " -s KEYSTORE_PASS
echo
read -p "Key password (can be same as keystore): " -s KEY_PASS
echo
read -p "Your name/company: " NAME
read -p "Organization unit: " ORG_UNIT
read -p "Organization: " ORG
read -p "City: " CITY
read -p "State: " STATE
read -p "Country code (2 letters, e.g., IN): " COUNTRY

# Generate keystore
keytool -genkey -v -keystore easy-basket-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias easy-basket-key \
  -storepass "$KEYSTORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=$NAME, OU=$ORG_UNIT, O=$ORG, L=$CITY, ST=$STATE, C=$COUNTRY"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Keystore generated successfully!"
    echo ""
    echo "📁 Location: android/easy-basket-key.jks"
    echo ""
    echo "⚠️  IMPORTANT:"
    echo "   1. Backup this keystore file securely"
    echo "   2. Save the passwords securely"
    echo "   3. If you lose this keystore, you CANNOT update your app on Play Store"
    echo ""
    echo "🔧 Next steps:"
    echo "   1. Add environment variables to ~/.zshrc or ~/.bashrc:"
    echo "      export KEYSTORE_PASSWORD=\"$KEYSTORE_PASS\""
    echo "      export KEY_PASSWORD=\"$KEY_PASS\""
    echo "   2. Run: source ~/.zshrc (or source ~/.bashrc)"
    echo "   3. Build release: flutter build appbundle --release"
else
    echo ""
    echo "❌ Failed to generate keystore. Please check the errors above."
    exit 1
fi


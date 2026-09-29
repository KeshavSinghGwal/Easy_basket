# Quick Publishing Checklist for Easy Basket

## Pre-Launch Checklist

### 1. Google Play Developer Account
- [ ] Create Google Play Developer account ($25)
- [ ] Complete developer profile
- [ ] Wait for account approval (24-48 hours)

### 2. App Assets Preparation
- [ ] App icon: 512x512px PNG (no transparency)
- [ ] Feature graphic: 1024x500px PNG
- [ ] Screenshots: At least 2 (up to 8)
- [ ] Privacy Policy URL (required!)

### 3. App Signing
- [ ] Generate keystore file (`easy-basket-key.jks`)
- [ ] Save keystore password securely
- [ ] Save key password securely
- [ ] Set environment variables (KEYSTORE_PASSWORD, KEY_PASSWORD)
- [ ] Test release build locally

### 4. App Configuration
- [ ] Verify application ID: `com.easybasket.app`
- [ ] Set version: `1.0.0+1` in `pubspec.yaml`
- [ ] Update app name if needed
- [ ] Verify all permissions in AndroidManifest.xml

### 5. Build & Test
- [ ] Run `flutter clean`
- [ ] Run `flutter pub get`
- [ ] Build AAB: `flutter build appbundle --release`
- [ ] Test release APK on device
- [ ] Verify all features work
- [ ] Test with production API URL

### 6. Google Play Console Setup
- [ ] Create new app in Play Console
- [ ] Complete store listing (name, description, screenshots)
- [ ] Upload app icon and feature graphic
- [ ] Add privacy policy URL
- [ ] Complete content rating questionnaire
- [ ] Fill data safety form
- [ ] Upload AAB file
- [ ] Add release notes

### 7. Review & Publish
- [ ] Review all sections (all green checkmarks)
- [ ] Submit for review
- [ ] Wait for approval (1-7 days)
- [ ] App goes live! 🎉

---

## Current App Status

**Application ID:** `com.easybasket.app` ✅  
**Version:** `1.0.0+1` ✅  
**App Name:** Easy Basket ✅  
**API URL:** `https://api.easybasket.in/api` ✅  

**Next Steps:**
1. Generate keystore (if not exists)
2. Build AAB
3. Create Play Console account
4. Upload and publish

---

## Quick Commands

```bash
# Navigate to project
cd /Users/nikhil/Projects/easyBucket/mobile

# Generate keystore (if needed)
cd android/app
keytool -genkey -v -keystore easy-basket-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias easy-basket-key

# Build release AAB
cd /Users/nikhil/Projects/easyBucket/mobile
flutter clean
flutter pub get
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

---

## Important Reminders

⚠️ **Save your keystore passwords!** You'll need them for every update.  
⚠️ **Application ID cannot be changed** after first release.  
⚠️ **Version code must always increase** for each update.  
⚠️ **Privacy Policy is required** - create one before publishing.

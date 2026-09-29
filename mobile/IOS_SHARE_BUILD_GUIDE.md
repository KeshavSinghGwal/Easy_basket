# Sharing iOS Build with Friends - Complete Guide

Unlike Android APK files, iOS apps cannot be directly installed by sharing an IPA file. iOS requires code signing and specific distribution methods.

## ⚠️ Important: iOS vs Android

- **Android**: Share APK → Friend installs directly ✅
- **iOS**: Cannot share IPA directly → Requires Apple Developer account & distribution method ❌

## Options for Sharing iOS Builds

### Option 1: TestFlight (Recommended - Best for Friends)

**Requirements:**
- Apple Developer Account ($99/year)
- Friend's Apple ID email
- Friend needs TestFlight app (free from App Store)

**Steps:**

1. **Build for TestFlight:**
   ```bash
   cd mobile
   flutter build ipa --release
   ```

2. **Upload to App Store Connect:**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - Create your app (if not already created)
   - Upload the IPA using Transporter app or Xcode

3. **Add Testers:**
   - Go to TestFlight tab
   - Add your friend's email as an internal/external tester
   - Friend receives email invitation

4. **Friend Installs:**
   - Friend downloads TestFlight app
   - Accepts invitation
   - Installs your app from TestFlight

**Pros:**
- ✅ Official Apple method
- ✅ Easy for friends
- ✅ Automatic updates
- ✅ Works for 90 days per build

**Cons:**
- ❌ Requires paid Apple Developer account ($99/year)
- ❌ Takes 1-2 hours for Apple to process

---

### Option 2: Ad-Hoc Distribution (For Specific Devices)

**Requirements:**
- Apple Developer Account ($99/year)
- Friend's device UDID (Unique Device Identifier)
- Maximum 100 devices per year

**Steps:**

1. **Get Friend's Device UDID:**
   - Friend connects iPhone to Mac
   - Open Finder → Select iPhone → Copy UDID
   - Or use online tools (like https://udid.tech)

2. **Add Device to Apple Developer:**
   - Go to [Apple Developer Portal](https://developer.apple.com)
   - Certificates, Identifiers & Profiles
   - Devices → Register New Device
   - Add friend's UDID

3. **Create Ad-Hoc Provisioning Profile:**
   - Profiles → Create New
   - Select "Ad Hoc" distribution
   - Select your app and friend's device
   - Download profile

4. **Build with Ad-Hoc Profile:**
   ```bash
   cd mobile
   flutter build ipa --release
   ```
   - Open Xcode → Runner.xcworkspace
   - Select Ad-Hoc profile in Signing & Capabilities
   - Archive and export IPA

5. **Share IPA:**
   - Send IPA file to friend
   - Friend installs via:
     - iTunes (older method)
     - Apple Configurator 2
     - 3uTools or similar tools

**Pros:**
- ✅ Direct file sharing
- ✅ No TestFlight needed

**Cons:**
- ❌ Requires device UDID
- ❌ Limited to 100 devices/year
- ❌ More complex setup
- ❌ Friend needs Mac or special tools to install

---

### Option 3: Enterprise Distribution (For Companies)

**Requirements:**
- Apple Enterprise Developer Account ($299/year)
- For internal company use only

**Not suitable for sharing with friends.**

---

### Option 4: App Store (Public Release)

**Requirements:**
- Apple Developer Account ($99/year)
- App Store review process (1-7 days)

**Steps:**
1. Build and upload to App Store Connect
2. Submit for review
3. Once approved, anyone can download from App Store

**Pros:**
- ✅ Public distribution
- ✅ Anyone can install

**Cons:**
- ❌ Requires App Store review
- ❌ Takes 1-7 days for approval
- ❌ App is publicly visible

---

## Quick Comparison

| Method | Cost | Setup Time | Friend's Effort | Best For |
|--------|------|------------|-----------------|----------|
| **TestFlight** | $99/year | 1-2 hours | Easy (just install TestFlight) | ✅ **Sharing with friends** |
| **Ad-Hoc** | $99/year | 30 mins | Medium (needs UDID + tools) | Specific devices |
| **App Store** | $99/year | 1-7 days | Easy (just download) | Public release |

---

## Recommended: TestFlight Setup

### Step-by-Step TestFlight Guide

1. **Prerequisites:**
   ```bash
   # Make sure you have Apple Developer account
   # Sign in at: https://developer.apple.com
   ```

2. **Build IPA:**
   ```bash
   cd mobile
   flutter build ipa --release
   # Output: build/ios/ipa/easy_basket.ipa
   ```

3. **Upload to App Store Connect:**
   - Download [Transporter app](https://apps.apple.com/app/transporter/id1450874784) from Mac App Store
   - Open Transporter → Drag IPA file → Deliver
   - Or use Xcode: Product → Archive → Distribute App

4. **Configure in App Store Connect:**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - My Apps → Create New App (if needed)
   - Wait for processing (1-2 hours)

5. **Add Testers:**
   - Go to TestFlight tab
   - Internal Testing: Add team members
   - External Testing: Add friend's email
   - Friend receives email invitation

6. **Friend Installs:**
   - Friend downloads "TestFlight" app from App Store
   - Opens invitation email
   - Taps "Start Testing"
   - App installs automatically

---

## Alternative: Use Android APK for Testing

If you just want your friend to test the app quickly:

```bash
cd mobile
flutter build apk --release
# Share: build/app/outputs/flutter-apk/app-release.apk
```

Friend can install APK directly on Android device (no restrictions).

---

## Troubleshooting

### "IPA won't install on friend's device"
- Check if device UDID is registered (for Ad-Hoc)
- Verify provisioning profile includes device
- Make sure friend trusts developer certificate

### "TestFlight invitation not received"
- Check spam folder
- Verify email is correct
- Friend must have TestFlight app installed

### "Build fails - Code signing error"
- Make sure you're signed in to Xcode with Apple ID
- Select correct team in Signing & Capabilities
- Verify certificates are valid

---

## Summary

**For sharing with friends, TestFlight is the best option:**
- ✅ Easy for friends (just install TestFlight)
- ✅ Official Apple method
- ✅ Automatic updates
- ✅ Works for 90 days per build

**Quick TestFlight Command:**
```bash
cd mobile
flutter build ipa --release
# Then upload to App Store Connect via Transporter or Xcode
```


# iOS Physical Device Build Guide

This guide will help you build the Easy Basket app for iOS physical devices.

## Prerequisites

1. **Xcode** - Must be installed from App Store
2. **CocoaPods** - Package manager for iOS dependencies
3. **Apple Developer Account** (for device deployment)
4. **Physical iOS Device** connected via USB

## Step 1: Install CocoaPods

If CocoaPods is not installed, run:

```bash
sudo gem install cocoapods
```

Or install via Homebrew:
```bash
brew install cocoapods
```

## Step 2: Install iOS Dependencies

Navigate to the iOS directory and install pods:

```bash
cd mobile/ios
pod install
cd ../..
```

## Step 3: Open Xcode and Configure

1. Open the iOS project in Xcode:
   ```bash
   open mobile/ios/Runner.xcworkspace
   ```

2. **Configure Signing & Capabilities:**
   - Select the "Runner" project in the left sidebar
   - Go to "Signing & Capabilities" tab
   - Select your Team (Apple Developer Account)
   - Xcode will automatically create a provisioning profile

3. **Set Bundle Identifier:**
   - In "Signing & Capabilities", ensure Bundle Identifier is unique
   - Example: `com.yourcompany.easybasket`

4. **Select Your Device:**
   - Connect your iPhone/iPad via USB
   - Select your device from the device dropdown (top toolbar)

## Step 4: Build and Run

### Option A: Using Xcode (Recommended for first time)

1. Click the "Play" button (▶️) in Xcode
2. Or press `Cmd + R`
3. First build may take 5-10 minutes

### Option B: Using Flutter CLI

```bash
cd mobile

# List connected devices
flutter devices

# Build and install on connected device
flutter run -d <device-id>

# Or build release version
flutter build ios --release
```

## Step 5: Trust Developer Certificate (First Time Only)

On your iOS device:
1. Go to **Settings** → **General** → **VPN & Device Management**
2. Tap on your developer certificate
3. Tap **Trust** → **Trust**

## Troubleshooting

### Issue: "CocoaPods not installed"
```bash
sudo gem install cocoapods
pod setup
```

### Issue: "No signing certificate found"
- Make sure you're logged into Xcode with your Apple ID
- Go to Xcode → Preferences → Accounts
- Add your Apple ID
- Select your team in Signing & Capabilities

### Issue: "Device not trusted"
- On your iPhone: Settings → General → VPN & Device Management
- Trust the developer certificate

### Issue: "Build failed - Pods missing"
```bash
cd mobile/ios
rm -rf Pods Podfile.lock
pod install
cd ../..
```

### Issue: "Xcode installation incomplete"
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

## Building IPA for Distribution

To create an IPA file for TestFlight or App Store:

```bash
cd mobile

# Build release
flutter build ipa --release

# Output will be in: build/ios/ipa/easy_basket.ipa
```

## Quick Build Commands

```bash
# 1. Install pods (first time only)
cd mobile/ios && pod install && cd ../..

# 2. Check connected devices
flutter devices

# 3. Run on connected device
flutter run -d <device-id>

# 4. Build release
flutter build ios --release
```

## Notes

- First build takes longer (5-10 minutes)
- You need an active internet connection for CocoaPods
- Free Apple Developer accounts have 7-day certificate expiration
- Paid accounts ($99/year) have 1-year certificates


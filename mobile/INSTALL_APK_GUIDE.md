# 📱 Install APK on Your Phone

## ✅ APK Built Successfully!

**Location:** `build/app/outputs/flutter-apk/app-release.apk`  
**Size:** ~57 MB

---

## 📲 Installation Methods

### Method 1: Using USB Cable (Recommended)

1. **Enable USB Debugging on your phone:**
   - Go to **Settings** → **About phone**
   - Tap **Build number** 7 times (enables Developer options)
   - Go back to **Settings** → **Developer options**
   - Enable **USB debugging**

2. **Connect phone to Mac:**
   ```bash
   # Check if device is connected
   adb devices
   
   # Install APK
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

3. **If device not found:**
   - Allow USB debugging on phone (check notification)
   - Try different USB cable
   - Check USB connection mode (should be File Transfer/MTP)

---

### Method 2: Using ADB Wireless (Same WiFi)

1. **Connect phone via USB first:**
   ```bash
   adb devices  # Verify connection
   ```

2. **Enable wireless debugging:**
   ```bash
   # Get phone IP address (Settings → About phone → Status → IP address)
   # Then run:
   adb tcpip 5555
   adb connect YOUR_PHONE_IP:5555
   ```

3. **Disconnect USB and install:**
   ```bash
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```

---

### Method 3: Transfer File Manually

1. **Copy APK to phone:**
   - Email the APK to yourself
   - Use Google Drive / Dropbox
   - Use AirDrop (if iPhone, use Android File Transfer)
   - Use USB cable in File Transfer mode

2. **Install on phone:**
   - Open **Files** app on phone
   - Navigate to Downloads (or where you saved the APK)
   - Tap the APK file
   - If prompted, allow **Install from Unknown Sources**
   - Tap **Install**

---

### Method 4: Using Android Studio

1. **Open Android Studio**
2. **Connect phone via USB**
3. **Run app:**
   - Click **Run** button (green play icon)
   - Select your device
   - App will install and launch

---

## ⚠️ Important Notes

### Allow Unknown Sources

If you see "Install blocked" or "Unknown sources":

1. Go to **Settings** → **Security** (or **Apps** → **Special access**)
2. Enable **Install unknown apps** (or **Unknown sources**)
3. Select the app you're using to install (Files, Chrome, etc.)
4. Enable **Allow from this source**

### First Launch

- App may take a few seconds to launch first time
- Grant permissions when prompted:
  - Location (for address selection)
  - Storage (if needed)

### Testing Checklist

- [ ] App launches successfully
- [ ] Login with phone number works
- [ ] OTP: 1234 works
- [ ] Home screen loads
- [ ] Products display correctly
- [ ] Add to cart works
- [ ] Checkout flow works
- [ ] Payment screen loads
- [ ] Location services work
- [ ] API calls work (check if backend is accessible)

---

## 🔧 Troubleshooting

### "App not installed" Error

**Possible causes:**
1. **Previous version exists:** Uninstall old version first
   ```bash
   adb uninstall com.easybasket.app
   ```

2. **Signature mismatch:** If you installed debug version before, uninstall it first

3. **Storage full:** Free up space on phone

### "Package appears to be corrupt" Error

- Rebuild APK: `flutter build apk --release`
- Try installing again

### App Crashes on Launch

1. **Check logs:**
   ```bash
   adb logcat | grep -i flutter
   ```

2. **Check API URL:**
   - Ensure `app_config.dart` has correct API URL
   - Test API: `curl http://api.easybasket.in/api/health`

3. **Check permissions:**
   - Location permission granted
   - Internet permission (should be automatic)

---

## 📋 Quick Commands

```bash
# Check connected devices
adb devices

# Install APK
adb install build/app/outputs/flutter-apk/app-release.apk

# Install with replacement (if app exists)
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Uninstall app
adb uninstall com.easybasket.app

# View app logs
adb logcat | grep -i easybasket

# Clear app data
adb shell pm clear com.easybasket.app
```

---

## 🎯 Next Steps After Testing

1. **Test all features:**
   - Login/Logout
   - Browse products
   - Add to cart
   - Checkout
   - Place order
   - View orders
   - Profile

2. **Report issues:**
   - Note any crashes
   - UI issues
   - Performance problems

3. **Prepare for Play Store:**
   - Re-enable minification (for smaller APK)
   - Generate proper signing key
   - Build App Bundle (AAB) instead of APK

---

**APK Location:** `mobile/build/app/outputs/flutter-apk/app-release.apk`

**Ready to install! 📱**


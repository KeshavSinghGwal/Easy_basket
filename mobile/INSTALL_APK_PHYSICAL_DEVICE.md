# 📱 Install APK on Physical Android Device

Guide to install Easy Basket APK on your physical Android device.

---

## ✅ APK Built Successfully!

**Location:** `mobile/build/app/outputs/flutter-apk/app-release.apk`  
**Size:** ~57 MB

---

## 📲 Installation Methods

### Method 1: Using USB Cable (Easiest)

#### Step 1: Enable USB Debugging on Your Phone

1. Go to **Settings** → **About phone**
2. Find **"Build number"** (usually at the bottom)
3. Tap **"Build number"** 7 times
   - You'll see: "You are now a developer!"
4. Go back to **Settings**
5. Find **"Developer options"** (now visible)
6. Enable **"USB debugging"**
7. Enable **"Install via USB"** (if available)

#### Step 2: Connect Phone to Mac

1. Connect your Android phone to Mac via USB cable
2. On your phone, you'll see a popup: **"Allow USB debugging?"**
3. Check **"Always allow from this computer"**
4. Tap **"Allow"**

#### Step 3: Verify Connection

**On Mac terminal:**

```bash
adb devices
```

**Expected output:**
```
List of devices attached
ABC123XYZ    device
```

If you see "device", you're connected! ✅

#### Step 4: Install APK

**On Mac terminal:**

```bash
cd ~/Projects/easyBucket/mobile
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Success message:**
```
Performing Streamed Install
Success
```

---

### Method 2: Transfer File Manually

#### Step 1: Copy APK to Phone

**Option A: Email**
1. Email the APK to yourself
2. Open email on phone
3. Download the APK attachment

**Option B: Google Drive / Dropbox**
1. Upload APK to Google Drive or Dropbox
2. Open Drive/Dropbox app on phone
3. Download the APK

**Option C: USB File Transfer**
1. Connect phone via USB
2. On phone: Select **"File Transfer"** or **"MTP"** mode
3. On Mac: Open **Android File Transfer** app
4. Copy `app-release.apk` to phone's Downloads folder

**Option D: AirDrop (if supported)**
1. Enable AirDrop on Mac
2. Right-click APK → Share → AirDrop
3. Select your phone

#### Step 2: Install on Phone

1. Open **Files** app on your phone
2. Navigate to **Downloads** (or where you saved the APK)
3. Tap the **app-release.apk** file

**If you see "Install blocked":**

1. Go to **Settings** → **Security** (or **Apps** → **Special access**)
2. Enable **"Install unknown apps"** or **"Unknown sources"**
3. Select the app you're using (Files, Chrome, Email, etc.)
4. Enable **"Allow from this source"**
5. Go back and tap the APK again

4. Tap **"Install"**
5. Wait for installation
6. Tap **"Open"** to launch the app

---

### Method 3: Using ADB Wireless (Same WiFi)

#### Step 1: Connect via USB First

```bash
adb devices  # Verify connection
```

#### Step 2: Enable Wireless Debugging

**On your phone:**
1. Go to **Settings** → **Developer options**
2. Enable **"Wireless debugging"** or **"ADB over network"**
3. Note the IP address and port shown (e.g., 192.168.1.100:5555)

**On Mac terminal:**

```bash
adb tcpip 5555
adb connect YOUR_PHONE_IP:5555
# Example: adb connect 192.168.1.100:5555
```

#### Step 3: Disconnect USB and Install

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔧 Troubleshooting

### "Device not found" Error

**Problem:** `adb devices` shows no devices

**Solutions:**
1. **Check USB cable** - Try different cable
2. **Check USB mode** - Select "File Transfer" or "MTP" on phone
3. **Restart ADB:**
   ```bash
   adb kill-server
   adb start-server
   adb devices
   ```
4. **Check USB debugging** - Re-enable on phone
5. **Try different USB port** on Mac

### "Install blocked" Error

**Problem:** Phone blocks installation

**Solution:**
1. Go to **Settings** → **Security**
2. Enable **"Install unknown apps"**
3. Select the app you're using (Files, Chrome, etc.)
4. Enable **"Allow from this source"**

### "App not installed" Error

**Problem:** Installation fails

**Solutions:**
1. **Uninstall old version first:**
   ```bash
   adb uninstall com.easybasket.app
   ```
2. **Check storage space** - Free up space on phone
3. **Check if app already exists** - Uninstall from phone settings first

### "Package appears to be corrupt" Error

**Problem:** APK seems corrupted

**Solution:**
1. Rebuild APK:
   ```bash
   cd mobile
   flutter clean
   flutter build apk --release
   ```
2. Try installing again

---

## 📋 Quick Commands Reference

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

# Restart ADB
adb kill-server && adb start-server
```

---

## 🧪 Testing Checklist

After installation, test:

- [ ] App launches without crashes
- [ ] Login with phone number works
- [ ] OTP: 1234 works
- [ ] Home screen loads
- [ ] Products display correctly
- [ ] Add to cart works
- [ ] Checkout flow works
- [ ] Payment screen loads
- [ ] Location services work
- [ ] API calls work (check if backend is accessible)
- [ ] Orders display correctly
- [ ] Profile screen works

---

## 📱 APK Location

**Full path:**
```
/Users/nikhil/Projects/easyBucket/mobile/build/app/outputs/flutter-apk/app-release.apk
```

**Size:** ~57 MB

---

## ✅ Next Steps

1. **Test thoroughly** on your physical device
2. **Report any issues** you find
3. **Fix bugs** before Play Store launch
4. **Build AAB** for Play Store (not APK)

---

**APK is ready to install on your physical device! 📱**


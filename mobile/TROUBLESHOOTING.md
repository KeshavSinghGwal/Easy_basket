# 🔧 Troubleshooting Guide

## Issue: "Nothing Happen" / App Not Launching

### ✅ Fixed Issues

1. **Android Project Files Missing** - ✅ FIXED
   - Ran `flutter create . --platforms=android,ios`
   - Generated all required Android/iOS native files

2. **API URL Configuration** - ✅ FIXED
   - Updated to `http://10.0.2.2:3000/api` for Android emulator

3. **Backend Running** - ✅ VERIFIED
   - Backend is running on port 3000

### Current Status

- ✅ Android emulator: Running (emulator-5554)
- ✅ Backend: Running on localhost:3000
- ✅ Flutter: Ready
- ✅ Android project: Created
- 🚀 App: Building and launching...

## If App Still Doesn't Launch

### Check 1: Is Backend Running?
```bash
curl http://localhost:3000/
# Should return: "Easy Basket Backend is running"
```

If not running:
```bash
cd backend
npm run dev
```

### Check 2: Is Emulator Running?
```bash
flutter devices
# Should show: emulator-5554
```

If not running:
```bash
flutter emulators --launch Medium_Phone_API_35
```

### Check 3: Build Errors?
```bash
cd mobile
flutter clean
flutter pub get
flutter run -d android
```

### Check 4: Check Logs
The app is building in the background. Check the terminal output for:
- Build progress
- Any error messages
- "Flutter run key commands" message (means it's running!)

## Common Issues

### "Gradle build failed"
- Wait for first build (can take 5-10 minutes)
- Check internet connection (needs to download Gradle)

### "SDK not found"
- Make sure Android Studio SDK is installed
- Check ANDROID_HOME is set: `echo $ANDROID_HOME`

### "License not accepted"
- Run: `flutter doctor --android-licenses`
- Press `y` for all prompts

### "Connection refused" in app
- Backend not running: `cd backend && npm run dev`
- Wrong API URL: Check `lib/config/app_config.dart`
- For Android emulator: Must use `10.0.2.2` not `localhost`

## Quick Fix Commands

```bash
# 1. Make sure backend is running
cd backend && npm run dev

# 2. Make sure emulator is running
flutter devices

# 3. Clean and rebuild
cd mobile
flutter clean
flutter pub get
flutter run -d android
```

## First Build Takes Time

⚠️ **First build can take 5-10 minutes!**
- Downloading Gradle
- Building Android project
- Installing dependencies

**Be patient** - subsequent builds are much faster.

## Success Indicators

You'll know it's working when you see:
1. ✅ "Running Gradle task 'assembleDebug'..."
2. ✅ "Installing app..."
3. ✅ "Flutter run key commands" message
4. ✅ App appears on emulator screen

## Still Having Issues?

1. Check terminal output for specific errors
2. Check Android Studio for build errors
3. Verify backend is accessible: `curl http://localhost:3000/api/categories`
4. Try web version: `flutter run -d chrome` (faster for testing)


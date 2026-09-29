# Easy Basket Flutter App - Run Commands

## Quick Start

### 1. Install Dependencies
```bash
cd mobile
flutter pub get
```

### 2. Configure API URL

**IMPORTANT:** Update `lib/config/app_config.dart` with your backend URL:

```dart
// For Android Emulator
static const String apiBaseUrl = 'http://10.0.2.2:3000/api';

// For iOS Simulator  
static const String apiBaseUrl = 'http://localhost:3000/api';

// For Physical Device (replace with your computer's IP)
static const String apiBaseUrl = 'http://192.168.1.100:3000/api';
```

**To find your IP address:**
- **Mac/Linux:** `ifconfig | grep "inet " | grep -v 127.0.0.1`
- **Windows:** `ipconfig` (look for IPv4 Address)

### 3. Make sure Backend is Running

```bash
cd backend
npm run dev
```

Backend should be running on `http://localhost:3000`

## Run Commands

### Option 1: Using the Run Script (Recommended)

```bash
cd mobile
chmod +x run.sh
./run.sh
```

Or specify platform:
```bash
./run.sh android   # For Android
./run.sh ios       # For iOS
./run.sh web       # For Web
```

### Option 2: Direct Flutter Commands

#### Run on Android
```bash
cd mobile
flutter run -d android
```

#### Run on iOS
```bash
cd mobile
flutter run -d ios
```

#### Run on Web
```bash
cd mobile
flutter run -d chrome
```

#### Run on Connected Device (Auto-detect)
```bash
cd mobile
flutter run
```

## Platform-Specific API URLs

### Android Emulator
- Use: `http://10.0.2.2:3000/api`
- This is the special IP that Android emulator uses to access localhost

### iOS Simulator
- Use: `http://localhost:3000/api`
- iOS simulator can access localhost directly

### Physical Device
- Use: `http://YOUR_COMPUTER_IP:3000/api`
- Example: `http://192.168.1.100:3000/api`
- Make sure your phone and computer are on the same WiFi network
- Make sure your backend allows connections from your network

## Testing the Connection

### 1. Test Backend
```bash
curl http://localhost:3000/
# Should return: "Easy Basket Backend is running"
```

### 2. Test API
```bash
curl http://localhost:3000/api/categories
# Should return: [] (empty array if no categories)
```

### 3. Test from App
- Launch the app
- Try to login with phone number
- Use OTP: `1234` (development mode)

## Common Issues

### Issue: "Network error" or "Connection refused"
**Solution:**
1. Make sure backend is running: `cd backend && npm run dev`
2. Check API URL in `lib/config/app_config.dart`
3. For physical device, ensure same WiFi network
4. Check firewall settings

### Issue: "No devices found"
**Solution:**
1. For Android: Start an emulator or connect a device via USB
2. For iOS: Start a simulator or connect an iPhone
3. Check: `flutter devices`

### Issue: "Build failed"
**Solution:**
```bash
flutter clean
flutter pub get
flutter run
```

### Issue: "Package not found"
**Solution:**
```bash
flutter pub get
```

## Development Workflow

1. **Start Backend:**
   ```bash
   cd backend
   npm run dev
   ```

2. **Start Flutter App:**
   ```bash
   cd mobile
   flutter run
   ```

3. **Hot Reload:**
   - Press `r` in terminal to hot reload
   - Press `R` to hot restart
   - Press `q` to quit

## Build for Production

### Android APK
```bash
cd mobile
flutter build apk --release
```

### Android App Bundle
```bash
cd mobile
flutter build appbundle --release
```

### iOS
```bash
cd mobile
flutter build ios --release
```

## Quick Test Checklist

- [ ] Backend is running on port 3000
- [ ] API URL is configured correctly in `app_config.dart`
- [ ] Flutter dependencies installed (`flutter pub get`)
- [ ] Device/Emulator is connected
- [ ] App launches successfully
- [ ] Can login with OTP (use `1234`)
- [ ] Can see home screen
- [ ] Can browse products (if any exist)

## Need Help?

1. Check backend logs: `cd backend && npm run dev`
2. Check Flutter logs in terminal
3. Verify API URL matches your platform
4. Ensure backend and app are on same network (for physical devices)


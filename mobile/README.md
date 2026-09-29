# Easy Basket Mobile App

Flutter mobile application for Easy Basket - Instant Grocery Delivery

## Features

- ✅ OTP-based Authentication
- ✅ Home Screen with Categories
- ✅ Product Listing & Search
- ✅ Shopping Cart
- ✅ Address Management
- ✅ Order Placement
- ✅ Order Tracking
- ✅ Payment Integration (UPI/Cash)
- ✅ User Profile

## Setup Instructions

### Prerequisites

1. **Flutter SDK** (3.0.0 or higher)
   ```bash
   flutter --version
   ```

2. **Android Studio / Xcode** (for Android/iOS development)

3. **Backend API** running (see backend README)

### Installation

1. **Navigate to mobile directory:**
   ```bash
   cd mobile
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure API Base URL:**
   
   Edit `lib/services/api_service.dart` and update the `baseUrl`:
   
   ```dart
   // For Android Emulator
   static const String baseUrl = 'http://10.0.2.2:3000/api';
   
   // For iOS Simulator
   static const String baseUrl = 'http://localhost:3000/api';
   
   // For Physical Device (use your computer's IP)
   static const String baseUrl = 'http://192.168.1.100:3000/api';
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── user_model.dart
│   ├── product_model.dart
│   ├── category_model.dart
│   ├── address_model.dart
│   └── order_model.dart
├── services/                 # API & Business logic
│   ├── api_service.dart
│   ├── auth_service.dart
│   └── cart_service.dart
├── providers/               # State management
│   ├── auth_provider.dart
│   ├── cart_provider.dart
│   ├── product_provider.dart
│   └── order_provider.dart
├── screens/                 # UI Screens
│   ├── splash_screen.dart
│   ├── auth/
│   │   └── login_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   ├── products/
│   │   ├── product_list_screen.dart
│   │   └── product_detail_screen.dart
│   ├── cart/
│   │   └── cart_screen.dart
│   ├── address/
│   │   ├── address_list_screen.dart
│   │   └── add_address_screen.dart
│   ├── payment/
│   │   └── payment_screen.dart
│   ├── orders/
│   │   ├── order_list_screen.dart
│   │   └── order_tracking_screen.dart
│   └── profile/
│       └── profile_screen.dart
├── widgets/                 # Reusable widgets
│   ├── category_card.dart
│   └── product_card.dart
├── routes/                  # Navigation
│   └── app_router.dart
└── utils/                   # Utilities
    └── theme.dart
```

## Configuration

### API Configuration

The app connects to the backend API. Make sure:

1. Backend is running on `http://localhost:3000`
2. Update `baseUrl` in `api_service.dart` based on your platform
3. For physical devices, use your computer's local IP address

### Firebase (Optional)

For push notifications:

1. Add `google-services.json` (Android) to `android/app/`
2. Add `GoogleService-Info.plist` (iOS) to `ios/Runner/`
3. Configure Firebase in `main.dart`

### Payment Integration

Razorpay integration is set up. To enable:

1. Add Razorpay keys to backend `.env`
2. Configure Razorpay in Flutter (see Razorpay Flutter docs)

## Testing

### Development OTP

In development mode, use `1234` as OTP for any phone number.

### Test Flow

1. Launch app → Splash screen
2. Login with phone number → Enter OTP (1234)
3. Browse categories and products
4. Add items to cart
5. Proceed to checkout
6. Add/select delivery address
7. Place order
8. Track order status

## Building for Production

### Android

```bash
flutter build apk --release
# or
flutter build appbundle --release
```

### iOS

```bash
flutter build ios --release
```

## Troubleshooting

### API Connection Issues

- **Android Emulator**: Use `10.0.2.2` instead of `localhost`
- **iOS Simulator**: Use `localhost`
- **Physical Device**: Use your computer's IP address (e.g., `192.168.1.100`)

### Build Errors

- Run `flutter clean` and `flutter pub get`
- Check Flutter version: `flutter --version`
- Ensure all dependencies are compatible

### Missing Assets

Create placeholder directories:
```bash
mkdir -p assets/images assets/icons assets/fonts
```

Add placeholder font file or remove font reference from `pubspec.yaml` if not using custom fonts.

## Next Steps

- [ ] Add image assets
- [ ] Configure Firebase for notifications
- [ ] Integrate Razorpay payment gateway
- [ ] Add location services for address
- [ ] Implement push notifications
- [ ] Add app icons and splash screens
- [ ] Optimize for production

## Support

For issues or questions, refer to the backend API documentation.


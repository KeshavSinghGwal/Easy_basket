# Google Play Store Publishing Guide for Easy Basket

## Prerequisites Checklist

- [ ] Google Play Developer Account ($25 one-time fee)
- [ ] App icon (512x512px PNG, no transparency)
- [ ] Feature graphic (1024x500px PNG)
- [ ] Screenshots (at least 2, up to 8)
- [ ] Privacy Policy URL (required)
- [ ] App signing key (keystore file)

---

## Step 1: Create Google Play Developer Account

1. Go to [Google Play Console](https://play.google.com/console)
2. Click **"Create account"** or sign in with your Google account
3. Pay the **$25 one-time registration fee** (credit/debit card)
4. Complete your developer profile:
   - Developer name: "Easy Basket" (or your company name)
   - Email address
   - Phone number
   - Address

**Note:** Account approval usually takes 24-48 hours.

---

## Step 2: Prepare App Assets

### Required Assets:

1. **App Icon** (512x512px)
   - Format: PNG
   - No transparency
   - Square, no rounded corners (Play Store will add them)

2. **Feature Graphic** (1024x500px)
   - Format: PNG
   - Used on the Play Store listing page

3. **Screenshots** (Minimum 2, Maximum 8)
   - Phone: 16:9 or 9:16 aspect ratio
   - Recommended: 1080x1920px (portrait) or 1920x1080px (landscape)
   - Show key features of your app

4. **Privacy Policy URL**
   - Must be publicly accessible
   - Required for apps that collect user data
   - You can use services like:
     - [Privacy Policy Generator](https://www.privacypolicygenerator.info/)
     - [Termly](https://termly.io/)
     - Host on your website

---

## Step 3: Generate App Signing Key (Keystore)

Your app needs to be signed with a keystore for release. Let's create one:

### Option A: Create Keystore (Recommended)

**For macOS with Android Studio:**

```bash
cd /Users/nikhil/Projects/easyBucket/mobile/android/app

# Use Android Studio's Java (if you have Android Studio installed)
"/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" -genkey -v -keystore easy-basket-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias easy-basket-key
```

**Or use the helper script:**

```bash
cd /Users/nikhil/Projects/easyBucket/mobile/android/app
./generate-keystore.sh
```

**For Linux/Windows or if you have Java installed:**

```bash
cd /Users/nikhil/Projects/easyBucket/mobile/android/app

# Generate keystore
keytool -genkey -v -keystore easy-basket-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias easy-basket-key
```

**Important Information to Save:**
- Keystore password: _______________
- Key alias: `easy-basket-key`
- Key password: _______________
- Keystore location: `android/app/easy-basket-key.jks`

**⚠️ CRITICAL:** Save these credentials securely! You'll need them for all future updates.

### Option B: Use Existing Keystore (if already created)

If you already have `easy-basket-key.jks` in `android/app/`, skip this step.

---

## Step 4: Configure Environment Variables for Signing

Add keystore passwords to your environment (for security):

### On macOS/Linux:

Add to `~/.zshrc` or `~/.bash_profile`:

```bash
export KEYSTORE_PASSWORD="your_keystore_password"
export KEY_PASSWORD="your_key_password"
```

Then reload:
```bash
source ~/.zshrc  # or source ~/.bash_profile
```

### On Windows:

```cmd
setx KEYSTORE_PASSWORD "your_keystore_password"
setx KEY_PASSWORD "your_key_password"
```

---

## Step 5: Update App Configuration

### 5.1 Update Version Number

In `pubspec.yaml`:
```yaml
version: 1.0.0+1
```
- Format: `versionName+versionCode`
- `versionName`: User-visible version (1.0.0)
- `versionCode`: Internal version number (1, 2, 3...)

**For each update, increment both:**
- First update: `1.0.1+2`
- Second update: `1.0.2+3`
- etc.

### 5.2 Verify Application ID

In `android/app/build.gradle.kts`, verify:
```kotlin
applicationId = "com.easybasket.app"
```

This is your unique app identifier. **Cannot be changed after publishing!**

### 5.3 Update AndroidManifest.xml (if needed)

Ensure your app name and permissions are correct:
- App label: "Easy Basket"
- Required permissions are declared

---

## Step 6: Build Release App Bundle (AAB)

**Important:** Google Play Store requires **AAB (Android App Bundle)**, not APK.

```bash
cd /Users/nikhil/Projects/easyBucket/mobile

# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build release app bundle
flutter build appbundle --release
```

**Output location:**
```
build/app/outputs/bundle/release/app-release.aab
```

**File size:** Check this file size. If it's too large (>150MB), you may need to optimize.

---

## Step 7: Test the Release Build

Before uploading, test the release build:

```bash
# Build release APK for testing
flutter build apk --release

# Install on device
flutter install --release
```

Test all features:
- [ ] App launches correctly
- [ ] All screens work
- [ ] API calls work (production URL)
- [ ] Payments work (if applicable)
- [ ] Location services work
- [ ] Push notifications work
- [ ] No crashes or errors

---

## Step 8: Create App in Google Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Click **"Create app"**
3. Fill in:
   - **App name:** Easy Basket
   - **Default language:** English (United States)
   - **App or game:** App
   - **Free or paid:** Free (or Paid)
   - **Declarations:** Check all applicable boxes
4. Click **"Create app"**

---

## Step 9: Complete Store Listing

### 9.1 Main Store Listing

1. Go to **"Store presence" > "Main store listing"**

2. Fill in required fields:

   **App name:** Easy Basket
   
   **Short description** (80 characters max):
   ```
   Instant grocery delivery - Fresh products delivered to your doorstep
   ```
   
   **Full description** (4000 characters max):
   ```
   Easy Basket - Your one-stop solution for instant grocery delivery!
   
   🛒 Shop from thousands of products
   🚚 Fast delivery to your doorstep
   💳 Secure payment options
   📍 Real-time order tracking
   🎯 Best prices and offers
   
   Features:
   • Browse products by category
   • Add to cart and checkout easily
   • Multiple payment methods
   • Track your orders in real-time
   • Save delivery addresses
   • View order history
   
   Download now and get your groceries delivered fresh!
   ```

3. **App icon:** Upload 512x512px icon

4. **Feature graphic:** Upload 1024x500px graphic

5. **Screenshots:** Upload at least 2 screenshots

6. **Privacy Policy:** Add your privacy policy URL

### 9.2 Categorization

- **App category:** Shopping
- **Tags:** Grocery, Delivery, Shopping, Food

### 9.3 Contact Details

- **Email:** Your support email
- **Phone:** (Optional)
- **Website:** (If you have one)

---

## Step 10: Set Up App Content

### 10.1 Content Rating

1. Go to **"Policy" > "App content"**
2. Complete the questionnaire about your app's content
3. Submit for rating (usually instant)

### 10.2 Target Audience

- Select appropriate age groups
- Answer questions about content

### 10.3 Data Safety

1. Go to **"Policy" > "Data safety"**
2. Declare what data you collect:
   - Location data (if you collect)
   - Personal information
   - Financial information (for payments)
   - etc.

**Be honest!** Google reviews apps and can reject if misrepresented.

---

## Step 11: Upload App Bundle

1. Go to **"Production"** (or "Testing" for internal testing first)

2. Click **"Create new release"**

3. **Upload AAB file:**
   - Click **"Upload"**
   - Select: `build/app/outputs/bundle/release/app-release.aab`
   - Wait for upload and processing

4. **Release name:** (Optional)
   ```
   Version 1.0.0 - Initial Release
   ```

5. **Release notes:** (What's new in this version)
   ```
   🎉 Welcome to Easy Basket!
   
   • Browse and order groceries
   • Fast delivery to your doorstep
   • Secure payment options
   • Real-time order tracking
   ```

6. Click **"Save"**

---

## Step 12: Complete Required Forms

### 12.1 App Access

- If your app requires login, provide test credentials
- Or mark as "All functionality available without login"

### 12.2 Ads

- Declare if your app shows ads
- If yes, specify ad networks

### 12.3 Content Rating

- Complete the questionnaire (if not done earlier)

### 12.4 Target Audience & Content

- Complete all required sections

---

## Step 13: Review and Publish

1. Go to **"Production"** tab
2. Review all sections:
   - ✅ Store listing complete
   - ✅ App bundle uploaded
   - ✅ Content rating complete
   - ✅ Data safety declared
   - ✅ All required forms filled

3. Click **"Review release"**

4. If everything is green, click **"Start rollout to Production"**

5. **Confirm** the release

---

## Step 14: Wait for Review

- **Review time:** Usually 1-7 days (can be longer)
- **Status:** You'll see "Under review" in Play Console
- **Notifications:** You'll get email updates

**Common rejection reasons:**
- Missing privacy policy
- Misleading content
- Policy violations
- Technical issues

---

## Step 15: App Goes Live! 🎉

Once approved:
- Your app will be live on Google Play Store
- Users can download and install
- You'll receive an email confirmation

**Share your app:**
```
https://play.google.com/store/apps/details?id=com.easybasket.app
```

---

## Post-Launch Checklist

- [ ] Monitor crash reports in Play Console
- [ ] Respond to user reviews
- [ ] Monitor app performance
- [ ] Plan updates and new features
- [ ] Set up analytics (if not already done)

---

## Updating Your App

For future updates:

1. **Update version in `pubspec.yaml`:**
   ```yaml
   version: 1.0.1+2  # Increment both numbers
   ```

2. **Build new AAB:**
   ```bash
   flutter build appbundle --release
   ```

3. **Upload to Play Console:**
   - Go to "Production" > "Create new release"
   - Upload new AAB
   - Add release notes
   - Submit for review

---

## Troubleshooting

### Issue: "Upload failed"
- Check file size (must be <150MB for single APK)
- Verify keystore is correct
- Ensure build completed successfully

### Issue: "App rejected"
- Read rejection reason carefully
- Fix issues mentioned
- Resubmit

### Issue: "Signing error"
- Verify keystore file exists
- Check environment variables are set
- Ensure passwords are correct

---

## Important Notes

1. **Keystore Security:**
   - ⚠️ **NEVER lose your keystore file or passwords!**
   - Keep backups in secure locations
   - Without it, you cannot update your app

2. **Application ID:**
   - Cannot be changed after first release
   - Choose carefully: `com.easybasket.app`

3. **Version Code:**
   - Must always increase
   - Never decrease or reuse

4. **Review Process:**
   - First release: 1-7 days
   - Updates: Usually faster (hours to 2 days)

---

## Quick Command Reference

```bash
# Clean build
flutter clean

# Get dependencies
flutter pub get

# Build release AAB (for Play Store)
flutter build appbundle --release

# Build release APK (for testing)
flutter build apk --release

# Check app size
du -h build/app/outputs/bundle/release/app-release.aab
```

---

## Support Resources

- [Google Play Console Help](https://support.google.com/googleplay/android-developer)
- [Flutter Deployment Guide](https://docs.flutter.dev/deployment/android)
- [Play Store Policies](https://play.google.com/about/developer-content-policy/)

---

**Good luck with your launch! 🚀**

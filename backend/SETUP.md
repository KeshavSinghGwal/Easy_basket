# Easy Basket Backend - Setup Complete ✅

## ✅ Completed Steps

1. **Dependencies Installed** - All npm packages are installed
2. **TypeScript Compilation** - Code compiles successfully
3. **Project Structure** - All files and folders are in place

## 📋 Configuration Required

### 1. Database Setup

Make sure your `.env` file has the correct database credentials:

```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=your_mysql_username
DB_PASS=your_mysql_password
DB_NAME=easy_basket
```

**Action Required:**
- Create MySQL database: `CREATE DATABASE easy_basket;`
- Update `.env` with your MySQL credentials
- The app will auto-create tables on first run (development mode)

### 2. JWT Secret

Update the JWT secret in `.env`:

```env
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production
```

**Action Required:** Change to a strong random string for production

### 3. Optional: Firebase (for FCM Notifications)

If you want push notifications, add Firebase service account:

```env
FIREBASE_SERVICE_ACCOUNT={"type":"service_account","project_id":"..."}
```

**Action Required:** 
- Get Firebase service account JSON from Firebase Console
- Paste the entire JSON as a string in `.env`

### 4. Optional: Twilio (for OTP / Phone Verification)

For real OTP over SMS (login flow):

```env
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_VERIFY_SERVICE_SID=VAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Action Required:**
- Sign up at https://www.twilio.com
- From Console: Account SID and Auth Token
- Create a Verify Service (Verify → Services → Create), copy the Service SID (starts with `VA`)
- Add all three to `.env`. If any are missing, the app falls back to dev OTP `1234`.

See `TWILIO_SETUP.md` for step-by-step setup.

### 5. Optional: Razorpay (for Payments)

For payment processing:

```env
RAZORPAY_KEY_ID=your_razorpay_key_id
RAZORPAY_KEY_SECRET=your_razorpay_key_secret
```

**Action Required:**
- Sign up at https://razorpay.com
- Get your API keys from dashboard
- Add to `.env`

## 🚀 Running the Server

### Development Mode
```bash
npm run dev
```

### Production Mode
```bash
npm run build
npm start
```

## 🧪 Testing the API

Once the server is running, test the health endpoint:

```bash
curl http://localhost:3000/
```

Expected response: `Easy Basket Backend is running`

## 📝 Quick Test - OTP Login

1. **Send OTP:**
```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "9876543210"}'
```

2. **Verify OTP (use 1234 in development):**
```bash
curl -X POST http://localhost:3000/api/auth/verify \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber": "9876543210", "otp": "1234"}'
```

You'll get a JWT token in the response. Use it for authenticated requests.

## 📚 API Documentation

See `README.md` for complete API documentation.

## ⚠️ Important Notes

- **Development OTP:** Use `1234` for testing in development mode
- **Database Sync:** Auto-creates tables in development (set `NODE_ENV=production` to disable)
- **CORS:** Currently allows all origins (update for production)

## 🎯 Next Steps

1. ✅ Dependencies installed
2. ✅ Code compiled
3. ⏳ Configure `.env` with your database credentials
4. ⏳ Start MySQL server
5. ⏳ Run `npm run dev` to start the backend
6. ⏳ Test the API endpoints

Your backend is ready! Just configure the database and you're good to go! 🚀


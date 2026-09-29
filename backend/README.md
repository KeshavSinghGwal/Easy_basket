# Easy Basket Backend API

Backend API for Easy Basket - Instant Grocery Delivery App

## Tech Stack

- **Runtime**: Node.js with TypeScript
- **Framework**: Express.js
- **Database**: MySQL with TypeORM
- **Authentication**: JWT
- **Payments**: Razorpay
- **Notifications**: Firebase Cloud Messaging (FCM)

## Setup

1. **Install Dependencies**
   ```bash
   npm install
   ```

2. **Environment Variables**
   Copy `.env.example` to `.env` and fill in your configuration:
   ```bash
   cp .env.example .env
   ```

3. **Database Setup**
   - Create a MySQL database named `easy_basket` (or your preferred name)
   - Update database credentials in `.env`
   - The app will auto-create tables on first run (development mode)

4. **Run the Server**
   ```bash
   # Development mode
   npm run dev

   # Production mode
   npm run build
   npm start
   ```

## API Endpoints

### Authentication (`/api/auth`)

- `POST /api/auth/login` - Send OTP to phone number
  ```json
  { "phoneNumber": "9876543210" }
  ```

- `POST /api/auth/verify` - Verify OTP and get JWT token
  ```json
  { "phoneNumber": "9876543210", "otp": "123456", "fcmToken": "optional" }
  ```

- `PUT /api/auth/profile` - Update user profile (requires auth)
  ```json
  { "name": "John Doe", "email": "john@example.com", "fcmToken": "token" }
  ```

### Products (`/api/products`)

- `GET /api/products` - Get all products (query: `?categoryId=1&search=rice`)
- `GET /api/products/:id` - Get product by ID
- `POST /api/products` - Create product (admin only)
- `PUT /api/products/:id` - Update product (admin only)
- `DELETE /api/products/:id` - Delete product (admin only)

### Categories (`/api/categories`)

- `GET /api/categories` - Get all categories
- `GET /api/categories/:id` - Get category by ID
- `POST /api/categories` - Create category (admin only)
- `PUT /api/categories/:id` - Update category (admin only)
- `DELETE /api/categories/:id` - Delete category (admin only)

### Addresses (`/api/addresses`)

- `GET /api/addresses` - Get user addresses (requires auth)
- `POST /api/addresses` - Create address (requires auth)
- `PUT /api/addresses/:id` - Update address (requires auth)
- `DELETE /api/addresses/:id` - Delete address (requires auth)

### Orders (`/api/orders`)

- `POST /api/orders` - Create order (requires auth)
  ```json
  {
    "items": [
      { "productId": 1, "quantity": 2 }
    ],
    "addressId": 1,
    "paymentMethod": "UPI",
    "notes": "Optional notes"
  }
  ```
- `GET /api/orders` - Get user orders (requires auth)
- `GET /api/orders/:id` - Get order by ID (requires auth)
- `GET /api/orders/status/:id` - Get order status (public)
- `PUT /api/orders/:id/cancel` - Cancel order (requires auth)

### Admin (`/api/admin`)

- `GET /api/admin/dashboard` - Get dashboard statistics
- `GET /api/admin/orders` - Get all orders (query: `?status=pending`)
- `PUT /api/admin/orders/:id/status` - Update order status
  ```json
  {
    "status": "accepted|preparing|out_for_delivery|delivered|cancelled",
    "deliveryBoyId": 5,
    "notes": "Optional notes"
  }
  ```
- `GET /api/admin/users` - Get all users (query: `?role=customer`)
- `PUT /api/admin/users/:id` - Update user

### Delivery (`/api/delivery`)

- `GET /api/delivery/orders` - Get assigned orders (query: `?status=out_for_delivery`)
- `PUT /api/delivery/orders/:id/status` - Update order status
  ```json
  { "status": "out_for_delivery|delivered" }
  ```
- `GET /api/delivery/stats` - Get delivery statistics

### Payment (`/api/payment`)

- `POST /api/payment/verify` - Verify payment
- `POST /api/payment/webhook/razorpay` - Razorpay webhook handler

## Authentication

All protected routes require a JWT token in the Authorization header:
```
Authorization: Bearer <token>
```

## User Roles

- `customer` - Default role for app users
- `admin` - Shop admin with full access
- `delivery` - Delivery boy role

## Order Status Flow

1. `pending` - Order placed, waiting for admin acceptance
2. `accepted` - Admin accepted the order
3. `preparing` - Order being prepared
4. `out_for_delivery` - Assigned to delivery boy, on the way
5. `delivered` - Order delivered successfully
6. `cancelled` - Order cancelled

## Database Schema

### Entities

- **User**: Customers, admins, and delivery boys
- **Category**: Product categories
- **Product**: Grocery items with stock management
- **Address**: User delivery addresses
- **Order**: Customer orders
- **OrderItem**: Individual items in an order

## Development Notes

- OTP: In development mode, use `1234` as OTP for testing
- Database: `synchronize: true` in development (auto-creates tables)
- FCM: Configure Firebase service account in `.env` for notifications
- Payments: Add Razorpay credentials in `.env` for payment processing

## Production Checklist

- [ ] Set `NODE_ENV=production` in `.env`
- [ ] Set `synchronize: false` in database config
- [ ] Use strong `JWT_SECRET`
- [ ] Configure proper CORS settings
- [ ] Set up database migrations
- [ ] Configure Firebase for FCM
- [ ] Set up Razorpay webhook endpoint
- [ ] Integrate SMS service for OTP (Twilio, MSG91, etc.)


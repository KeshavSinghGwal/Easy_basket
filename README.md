# 🛒 EasyBasket

A full-stack grocery delivery platform built with Flutter and Node.js/TypeScript.

## ✨ Features

### Customer

- Register and log in to the application.
- Browse groceries and products from multiple shops.
- Search and explore products by category.
- View detailed product information.
- Add products to the shopping cart.
- Manage delivery addresses.
- Place orders using available payment methods.
- Make online payments through Razorpay.
- Track order status and view order history.
- Manage profile information.
- Select and switch between supported languages.

### Administrator

- Log in to the administrative dashboard.
- View and manage customer orders.
- Manage products and product categories.
- Manage shops and grocery inventory.
- Monitor order status and delivery progress.
- Manage customer records.
- Handle payment and order-related information.
- Manage content and application data.

The project also contains backend services for authentication, order processing, payments, notifications, translations, and other application operations.

## 🛠️ Technology Stack

| **Area** | **Technologies** |
| --------------------------- | ----------------------------------------------------- |
| Mobile Frontend | Flutter, Dart |
| Backend | Node.js, Express.js, TypeScript |
| Database | MongoDB, Mongoose |
| Authentication | JWT, bcrypt |
| Payments | Razorpay |
| Caching & Queues | Redis, BullMQ |
| Notifications | Firebase Cloud Messaging |
| Cloud Storage | AWS S3 |
| API Communication | REST APIs, Dio |
| Development & Testing | VS Code, IntelliJ IDEA, Postman |
| Containerization | Docker |
| Version Control | Git, GitHub |

## 🏗️ Application Architecture

The application follows a client-server architecture with a Flutter mobile frontend and a Node.js/Express backend.

1. The Flutter application provides the user interface for customers and application users.
2. REST APIs are used to communicate between the Flutter frontend and the backend.
3. The Node.js and Express backend handles authentication, products, shops, carts, orders, payments, and application logic.
4. MongoDB is used to store application data.
5. Redis is used for caching and background job processing.
6. Razorpay is integrated for online payment processing.
7. AWS S3 is used for cloud-based file and image storage.
8. Firebase Cloud Messaging is used for push notification support.

JWT-based authentication is used to secure API access, while additional backend middleware handles validation, authorization, and application security.

## 📁 Project Structure

```text
Easy_basket/
├── backend/
│   ├── src/
│   │   ├── controllers/
│   │   ├── entities/
│   │   ├── middleware/
│   │   ├── migrations/
│   │   ├── routes/
│   │   ├── scripts/
│   │   ├── services/
│   │   └── utils/
│   ├── package.json
│   └── README.md
│
├── mobile/
│   ├── lib/
│   │   ├── config/
│   │   ├── core/
│   │   ├── models/
│   │   ├── providers/
│   │   ├── routes/
│   │   ├── screens/
│   │   ├── services/
│   │   ├── utils/
│   │   └── widgets/
│   ├── assets/
│   ├── android/
│   ├── ios/
│   ├── web/
│   ├── test/
│   ├── pubspec.yaml
│   └── README.md
│
├── screenshots/
│   ├── 01-home_user.jpeg
│   ├── 02-Manage_actions_admin.jpeg
│   ├── 03-Myorders_user.jpeg
│   ├── 04-Refund_admin.jpeg
│   ├── 05-manage-orders_admin.jpeg
│   ├── 06-payment_user.jpeg
│   ├── 07-products_user.jpeg
│   └── 08-profile_user.jpeg
│
├── .gitignore
└── README.md

## 👨‍💻 Author

**Keshav Singh Gwal**  
B.Tech, Computer Science and Engineering  


## 📱 Application Screenshots

<table>
  <tr>
    <td align="center">
      <strong>Home</strong><br>
      <img src="screenshots/01-home_user.jpeg" width="300">
    </td>
    <td align="center">
      <strong>Admin Actions</strong><br>
      <img src="screenshots/02-Manage_actions_admin.jpeg" width="300">
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>My Orders</strong><br>
      <img src="screenshots/03-Myorders_user.jpeg" width="300">
    </td>
    <td align="center">
      <strong>Admin Refunds</strong><br>
      <img src="screenshots/04-Refund_admin.jpeg" width="300">
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Admin Manage Orders</strong><br>
      <img src="screenshots/05-manage-orders_admin.jpeg" width="300">
    </td>
    <td align="center">
      <strong>Payment</strong><br>
      <img src="screenshots/06-payment_user.jpeg" width="300">
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Products</strong><br>
      <img src="screenshots/07-products_user.jpeg" width="300">
    </td>
    <td align="center">
      <strong>Profile</strong><br>
      <img src="screenshots/08-profile_user.jpeg" width="300">
    </td>
  </tr>
</table>

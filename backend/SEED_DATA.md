# 🌱 Database Seed Script

## Overview

This script populates your database with sample categories and products for testing and development.

## What Gets Created

### Categories (8)
- Fruits & Vegetables
- Dairy & Eggs
- Beverages
- Snacks
- Bakery
- Personal Care
- Household
- Spices & Masala

### Products (50+)
- Fresh produce (tomatoes, onions, potatoes, etc.)
- Dairy products (milk, eggs, butter, paneer)
- Beverages (soft drinks, juices, tea, coffee)
- Snacks (chips, biscuits, chocolates)
- Bakery items (bread, buns, cake)
- Personal care (soap, shampoo, toothpaste)
- Household items (detergent, cleaners)
- Spices and masalas

## How to Run

### Option 1: Using npm script
```bash
cd backend
npm run seed
```

### Option 2: Direct execution
```bash
cd backend
npx ts-node src/scripts/seed.ts
```

## Features

- ✅ **Idempotent**: Safe to run multiple times (won't create duplicates)
- ✅ **Smart**: Checks if categories/products already exist
- ✅ **Realistic**: Indian grocery prices and products
- ✅ **Complete**: Includes all required fields (price, stock, unit, etc.)

## Sample Data Details

- **Prices**: Realistic Indian grocery prices (₹20 - ₹300)
- **Stock**: Varying stock levels (15-150 units)
- **Units**: kg, liter, pack, piece, dozen, etc.
- **Images**: Placeholder Unsplash URLs (you can replace with actual images)

## Notes

- The script will **NOT** delete existing data by default
- If you want to clear existing data, uncomment the delete lines in the script
- Categories are created first (products need categories)
- All products are set as `isAvailable: true`

## After Running

1. Check your database - you should see 8 categories and 50+ products
2. Test the API endpoints:
   - `GET /api/categories` - See all categories
   - `GET /api/products` - See all products
   - `GET /api/products?categoryId=1` - Filter by category

## Customization

Edit `src/scripts/seed.ts` to:
- Add more categories
- Add more products
- Change prices/stock
- Update image URLs
- Add your own product data

---

**Happy Testing! 🛒**


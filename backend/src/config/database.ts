import { Address } from '../entities/Address';
import { Campaign } from '../entities/Campaign';
import { Category } from '../entities/Category';
import { DataSource } from 'typeorm';
import { Order } from '../entities/Order';
import { OrderEvent } from '../entities/OrderEvent';
import { OrderItem } from '../entities/OrderItem';
import { Payment } from '../entities/Payment';
import { Product } from '../entities/Product';
import { ProductVariant } from '../entities/ProductVariant';
import { Refund } from '../entities/Refund';
import { RefreshToken } from '../entities/RefreshToken';
import { RiderCashDeposit } from '../entities/RiderCashDeposit';
import { RiderProfile } from '../entities/RiderProfile';
import { RiderWallet } from '../entities/RiderWallet';
import { RoleChangeAudit } from '../entities/RoleChangeAudit';
import { ServiceArea } from '../entities/ServiceArea';
import { StoreStatus } from '../entities/StoreStatus';
import { User } from '../entities/User';
import { WebhookEvent } from '../entities/WebhookEvent';
import dotenv from 'dotenv';
import { Translation } from "../entities/Translation";
import { MissingTranslation } from "../entities/MissingTranslation";


dotenv.config();

export const AppDataSource = new DataSource({
  type: 'mysql',
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT) || 3306,
  username: process.env.DB_USER || 'root',
  password: process.env.DB_PASS || 'password',
  database: process.env.DB_NAME || 'easy_basket',
  synchronize: false, // Disabled to prevent index drop errors with foreign keys. Schema is already correct.
  logging: process.env.NODE_ENV === 'development',
  entities: [
  User,
  Product,
  Order,
  Category,
  Address,
  OrderItem,
  RefreshToken,
  ServiceArea,
  ProductVariant,
  Campaign,
  Payment,
  Refund,
  WebhookEvent,
  RiderProfile,
  RiderWallet,
  RiderCashDeposit,
  OrderEvent,
  RoleChangeAudit,
  Translation,
  MissingTranslation,
  // Was imported above but never registered here, so TypeORM had no metadata for it
  // and every store-status read threw EntityMetadataNotFoundError. The service fails
  // OPEN by design, which turned a permanent break into silent log noise — and left
  // the server-side STORE_CLOSED guard in createOrder permanently inert.
  StoreStatus,
],
  subscribers: [],
  migrations: [],
  timezone: 'Z', // RDS MySQL uses UTC — tell mysql2 to interpret times as UTC, not local
  extra: {
    connectionLimit: 10,
    connectTimeout: 10000, // 10 seconds connection timeout
  },
});

import { AppDataSource } from '../config/database';
import { User } from '../entities/User';
import { FCMService } from '../services/fcm.service';

async function checkNotifications() {
  try {
    // Initialize database
    if (!AppDataSource.isInitialized) {
      await AppDataSource.initialize();
      console.log('✅ Database initialized');
    }

    // Check Firebase initialization
    console.log('\n📱 Checking Firebase FCM Service...');
    // FCMService is initialized on module load, so it should be ready

    // Check admin users
    console.log('\n👤 Checking admin users...');
    const userRepository = AppDataSource.getRepository(User);
    const adminUsers = await userRepository.find({
      where: { role: 'admin', isActive: true },
    });

    console.log(`Found ${adminUsers.length} admin user(s):`);
    adminUsers.forEach((user) => {
      console.log(`  - User ID: ${user.id}`);
      console.log(`    Phone: ${user.phoneNumber}`);
      console.log(`    Name: ${user.name || 'N/A'}`);
      console.log(`    Has FCM Token: ${user.fcmToken ? 'YES' : 'NO'}`);
      if (user.fcmToken) {
        console.log(`    Token Length: ${user.fcmToken.length}`);
        console.log(`    Token Preview: ${user.fcmToken.substring(0, 30)}...`);
      }
      console.log('');
    });

    // Test notification sending
    if (adminUsers.length > 0 && adminUsers.some((u) => u.fcmToken)) {
      console.log('\n📤 Testing notification send...');
      const result = await FCMService.sendNotificationToRole(
        'admin',
        'Test Notification',
        'This is a test notification from the diagnostic script',
        { type: 'test', timestamp: new Date().toISOString() }
      );
      console.log(`✅ Test notification sent to ${result} admin user(s)`);
    } else {
      console.log('\n⚠️ No admin users with FCM tokens found. Cannot send test notification.');
    }

    await AppDataSource.destroy();
    console.log('\n✅ Diagnostic complete');
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

checkNotifications();

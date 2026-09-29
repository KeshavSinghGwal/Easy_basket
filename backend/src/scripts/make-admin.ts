import { AppDataSource } from '../config/database';
import { User } from '../entities/User';

const PHONE = '8360339165';

async function makeAdmin() {
  try {
    if (!AppDataSource.isInitialized) {
      await AppDataSource.initialize();
    }
    const userRepo = AppDataSource.getRepository(User);
    const user = await userRepo.findOne({ where: { phoneNumber: PHONE } });
    if (!user) {
      console.error(`User with phone ${PHONE} not found.`);
      process.exit(1);
    }
    user.role = 'admin';
    await userRepo.save(user);
    console.log(`User ${PHONE} is now admin.`);
    await AppDataSource.destroy();
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

makeAdmin();

import { AppDataSource } from '../config/database';
import { ServiceArea } from '../entities/ServiceArea';

/**
 * Seed only service areas (pincodes where delivery is allowed).
 * Does NOT touch categories or products — safe to run without corrupting existing data.
 */
async function seed() {
  try {
    console.log('🌱 Seeding service areas only (no categories/products)...');

    if (!AppDataSource.isInitialized) {
      await AppDataSource.initialize();
      console.log('✅ Database connected');
    }

    const serviceAreaRepository = AppDataSource.getRepository(ServiceArea);

    const serviceAreas = [
      {
        pincode: '140301',
        city: 'Khanna',
        state: 'Punjab',
        country: 'India',
        notes: 'Added for service',
      },
    ];

    for (const sa of serviceAreas) {
      const existing = await serviceAreaRepository.findOne({
        where: { pincode: sa.pincode, country: sa.country },
      });
      if (!existing) {
        const area = serviceAreaRepository.create({
          ...sa,
          isActive: true,
        });
        await serviceAreaRepository.save(area);
        console.log(`✅ Created service area: ${sa.pincode} (${sa.city}, ${sa.state})`);
      } else {
        console.log(`ℹ️  Service area already exists: ${sa.pincode}`);
      }
    }

    console.log('✅ Service area seed done.');
    await AppDataSource.destroy();
  } catch (error) {
    console.error('❌ Error seeding service areas:', error);
    process.exit(1);
  }
}

if (require.main === module) {
  seed();
}

export default seed;

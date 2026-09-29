import { Router } from 'express';
import { AddressController } from '../controllers/address.controller';
import { authenticate } from '../middleware/auth.middleware';

const router = Router();

router.use(authenticate);

router.get('/', AddressController.getUserAddresses);
router.post('/', AddressController.createAddress);
router.put('/:id', AddressController.updateAddress);
router.delete('/:id', AddressController.deleteAddress);

export default router;

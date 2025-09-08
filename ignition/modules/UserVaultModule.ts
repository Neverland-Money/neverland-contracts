import {buildModule} from '@nomicfoundation/hardhat-ignition/modules';
import DustLockModule from './DustLockModule';

const UserVaultModule = buildModule('UserVaultModule', (m) => {
	const aaveOracle = m.getParameter('aaveOracle');
	const executor = m.getParameter('executor');
	const rewardDIstributor = m.getParameter('rewardDistributor');

	const userVaultRegistry = m.contract('UserVaultRegistry', []);

	m.call(userVaultRegistry, 'setExecutor', [executor]);

	const userVaultImpl = m.contract('UserVault', []);

	const userVaultBeacon = m.contract('UpgradeableBeacon', [userVaultImpl]);
	
	const userVaultFactory = m.contract('UserVaultFactory', []);

	const {dustLock} = m.useModule(DustLockModule);

	const forwarder = m.staticCall(dustLock, "forwarder", []);

	const revenueReward = m.contract("RevenueReward", [forwarder, dustLock, rewardDIstributor, userVaultFactory]);

	m.call(userVaultFactory, 'initialize', [userVaultBeacon, userVaultRegistry, aaveOracle, revenueReward]);

	return {userVaultImpl, userVaultRegistry, userVaultBeacon, userVaultFactory, revenueReward};
});

export default UserVaultModule;

import {loadFixture} from '@nomicfoundation/hardhat-toolbox/network-helpers';
import UserVaultModule from '../../ignition/modules/UserVaultModule';
import {ethers, ignition} from 'hardhat';
import {expect} from 'chai';
import { UserVaultFactory, UserVault, UserVaultRegistry, RevenueReward } from '../../typechain-v6';
import DustModule from '../../ignition/modules/DustModule';
import {MonorailClient} from '../../script/hardhat/api/monorail';
import { getAddress } from 'ethers';
import DustLockModule from '../../ignition/modules/DustLockModule';
import EmissionsModule from '../../ignition/modules/EmissionsModule';

(BigInt.prototype as any).toJSON = function () {
	return this.toString();
};

const USDC = getAddress("0xf817257fed379853cDe0fa4F97AB987181B1E5Ea");
const USDT = getAddress("0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D");
const USER_WITH_DEBT = getAddress("0x0000B06460777398083CB501793a4d6393900000");
const MONORAIL_AGGREGATOR = getAddress("0x525b929fcd6a64aff834f4eecc6e860486ced700");
const AAVE_ORACLE = getAddress("0x58207F48394a02c933dec4Ee45feC8A55e9cdf38");

describe('UserVault', function () {
	// We define a fixture to reuse the same setup in every test.
	// We use loadFixture to run this setup once, snapshot that state,
	// and reset Hardhat Network to that snapshot in every test.
	async function deployProtocolFixture() {
		const signers = await ethers.getSigners();
		const deployer = signers[0];
		const user = signers[1];
		const user2 = signers[2];
		const treasury = signers[3];
        const executor = signers[4];

		// Get the current block number
		const blockNumber = await ethers.provider.getBlockNumber();
		console.log("Current block number:", blockNumber);

		// Check if modules deployments work
		const dustModule = await ignition.deploy(DustModule, {});		
		const dustLockModule = await ignition.deploy(DustLockModule, {});
		const emissionsModule = await ignition.deploy(EmissionsModule, {
			parameters: {
				EmissionsModule: {
					rewardsAdmin: deployer.address,
					dustVault: deployer.address,
					emissionsManager: deployer.address,
				},
			},
		});

		// deploy UserVaultModule
		const userVaultModule = await ignition.deploy(UserVaultModule, {
			parameters: {
				UserVaultModule: {
					aaveOracle: AAVE_ORACLE,
					executor: deployer.address,
					rewardDistributor: USER_WITH_DEBT,
				},
			},
		});
		
		const revenueReward = userVaultModule.revenueReward as unknown as RevenueReward;
        const userVaultFactory = userVaultModule.userVaultFactory as unknown as UserVaultFactory;
        const userVaultRegistry = userVaultModule.userVaultRegistry as unknown as UserVaultRegistry;

		const userWithDebtAddress = USER_WITH_DEBT;

		await userVaultRegistry.setSupportedAggregators(MONORAIL_AGGREGATOR, true);

        return {
            deployer, 
            user, 
            user2, 
            treasury, 
            executor, 
            userVaultModule,
            userVaultFactory,
			userVaultRegistry,
			userWithDebtAddress,
			dustModule,
			dustLockModule,
			revenueReward,
			emissionsModule
        };
    }

    describe('Deployment', function () {
		it('Should not revert', async function () {
			await loadFixture(deployProtocolFixture);
		});
	});

	describe('Swap E2E', function () {
		it('Should swap tokens correctly', async function () {
			const {userVaultFactory, userWithDebtAddress, userVaultRegistry} = await loadFixture(deployProtocolFixture);

			await userVaultFactory.getOrCreateUserVault(userWithDebtAddress);

			const userVaultAddress = await userVaultFactory.getUserVault(userWithDebtAddress);

			console.log("UserVault address:", userVaultAddress);

			const userVault = (await ethers.getContractAt("UserVault", userVaultAddress)) as UserVault;

			const usdc = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", USDC);
			const usdt = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", USDT);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdc.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdc.balanceOf(userVault)).to.equal(9000000n);

			// Define your Monorail app ID
			const appId = '456175259108973';

			// Initialize the Monorail client
			const monorail = new MonorailClient(appId);

			// Get a quote using the SDK
			const quote = await monorail.getQuote({
				from: USDC,	// USDC
				to: USDT, // USDT
				amount: (9n).toString(),
				sender: userVaultAddress,
				destination: userVaultAddress,
				// Optional parameters
				// max_slippage: 50, // 0.5%
				// deadline: 60, // 60 seconds
			});

			console.log("Quote:", quote);

			console.log("Transaction to:", quote.transaction!.to);

			console.log(await userVaultRegistry.isSupportedAggregator(quote.transaction!.to));

			await userVault.swapAndVerifySlippage(
				USDC, 
				quote.transaction!.to, 
				quote.transaction!.data,
				10000n
			);
			
			const usdtAfter = await usdt.balanceOf(userVault);
			const usdcAfter = await usdc.balanceOf(userVault);
			console.log("USDT after swap:", usdtAfter.toString());
			console.log("USDT after swap:", usdcAfter.toString());
			expect(usdtAfter).to.be.gte(0);
			expect(await usdc.balanceOf(userVault)).to.equal(0n);
		});
	});
});
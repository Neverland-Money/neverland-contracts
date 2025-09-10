import {loadFixture} from '@nomicfoundation/hardhat-toolbox/network-helpers';
import UserVaultModule from '../../ignition/modules/UserVaultModule';
import {ethers, ignition} from 'hardhat';
import {expect} from 'chai';
import { UserVaultFactory, UserVault, UserVaultRegistry, RevenueReward, IUserVault, DustLock, Dust } from '../../typechain-v6';
import {MonorailClient} from '../../script/hardhat/api/monorail';
import { getAddress } from 'ethers';

(BigInt.prototype as any).toJSON = function () {
	return this.toString();
};

const USDC = getAddress("0xf817257fed379853cDe0fa4F97AB987181B1E5Ea");
const USDT = getAddress("0x88b8E2161DEDC77EF4ab7585569D2415a1C1055D");
const WMON = getAddress("0x760AfE86e5de5fa0Ee542fc7B7B713e1c5425701");
const USER_WITH_DEBT = getAddress("0x0000B06460777398083CB501793a4d6393900000");
const MONORAIL_AGGREGATOR = getAddress("0x525b929fcd6a64aff834f4eecc6e860486ced700");
const AAVE_ORACLE = getAddress("0x58207F48394a02c933dec4Ee45feC8A55e9cdf38");
// Define your Monorail app ID
const MONORAIL_APP_ID = '456175259108973';

describe('UserVault E2E', function () {
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

		// deploy UserVaultModule
		const userVaultModule = await ignition.deploy(UserVaultModule, {
			parameters: {
				UserVaultModule: {
					aaveOracle: AAVE_ORACLE,
					executor: deployer.address,
					rewardDistributor: deployer.address,
				},
			},
		});
		
		const revenueReward = userVaultModule.revenueReward as unknown as RevenueReward;
        const userVaultFactory = userVaultModule.userVaultFactory as unknown as UserVaultFactory;
        const userVaultRegistry = userVaultModule.userVaultRegistry as unknown as UserVaultRegistry;
        const dustLock = await ethers.getContractAt("DustLock", await revenueReward.dustLock()) as DustLock;
        const dust = await ethers.getContractAt("Dust", await dustLock.token()) as Dust;

		const userWithDebtAddress = USER_WITH_DEBT;

		await userVaultRegistry.setSupportedAggregators(MONORAIL_AGGREGATOR, true);
		await userVaultRegistry.setMaxSwapSlippageBps(300n); // 3%

		const usdc = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", USDC);
		const usdt = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", USDT);

		await userVaultFactory.getOrCreateUserVault(userWithDebtAddress);

		const userVaultAddress = await userVaultFactory.getUserVault(userWithDebtAddress);

		const userVault = (await ethers.getContractAt("UserVault", userVaultAddress)) as UserVault;

		const monorail = new MonorailClient(MONORAIL_APP_ID);

		const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

		await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
		const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

		// Send 9 USDC to user vault
		await usdc.connect(usdcWhale).transfer(deployer, 9000000n);

		// Set RevenueReward etc.
		await dustLock.setRevenueReward(revenueReward);

		console.log(await revenueReward.dustLock());
		expect(await revenueReward.dustLock()).eq(await dustLock.getAddress());

		// crate dustlock for user
		await dust.approve(dustLock, 1n * (10n ** 18n));
		await dustLock.createLockFor(1n * (10n ** 18n), 7776000n, USER_WITH_DEBT);
		const tokenId = await dustLock.tokenId();
		expect(await dustLock.ownerOf(tokenId)).eq(USER_WITH_DEBT);

		// set self repaying loan
		await ethers.provider.send("hardhat_impersonateAccount", [USER_WITH_DEBT]);
		const userWithDebt = await ethers.getSigner(USER_WITH_DEBT);

		await revenueReward.connect(userWithDebt).enableSelfRepayLoan(tokenId);

		// top up rewards
		await usdc.approve(revenueReward, 9000000n);
		await revenueReward.notifyRewardAmount(USDC, 9000000n);

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
			revenueReward,
			usdc,
			usdt,
			dust,
			userVault,
			dustLock,
			monorail,
			tokenId
        };
    }

    describe('Deployment', function () {
		it('Should not revert', async function () {
			await loadFixture(deployProtocolFixture);
		});
	});

	describe('RepayUserDebt', function () {
		it('Should repay debt correctly w/o claiming rewards', async function () {
			const {userVaultRegistry, usdc, usdt, userVault, monorail} = await loadFixture(deployProtocolFixture);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdc.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdc.balanceOf(userVault)).to.equal(9000000n);

			// Get a quote using the SDK
			const quote = await monorail.getQuote({
				from: USDC,	// USDC
				to: USDT, // USDT
				amount: (9n).toString(),
				sender: await userVault.getAddress(),
				destination: await userVault.getAddress(),
				// Optional parameters
				// max_slippage: 50, // 0.5%
				// deadline: 60, // 60 seconds
			});

			console.log("Quote:", quote);

			console.log("Transaction to:", quote.transaction!.to);

			console.log(await userVaultRegistry.isSupportedAggregator(quote.transaction!.to));

			const repayUserDebtParmas : IUserVault.RepayUserDebtParamsStruct = {
				debtToken: USDT,
				poolAddress: "0x9861f6a26050e02Ff0C079657F5a3AFcD8D4af52",
				tokenIds: [],
				rewardToken: USDC,
				rewardTokenAmountToSwap: 9000000n,
				aggregatorAddress: quote.transaction!.to,
				aggregatorData: quote.transaction!.data!,
				maxSlippageBps: 100n,
			}

			await userVault.repayUserDebt(
				repayUserDebtParmas
			);
			
			const usdtAfter = await usdt.balanceOf(userVault);
			expect(usdtAfter).to.be.gte(0);
			expect(await usdc.balanceOf(userVault)).to.equal(0n);
			// TODO check debt is repaid
		});

		it('Should repay debt correctly w/ claiming rewards', async function () {
			const {userVaultRegistry, usdc, userVault, tokenId, monorail, revenueReward} = await loadFixture(deployProtocolFixture);

			const timestamp1 = (await ethers.provider.getBlock('latest')).timestamp;
			console.log("Current block timestamp:", timestamp1);

			// rewind time by 2 weeks (to be sure)
			await ethers.provider.send("evm_increaseTime", [1209600]);
			await ethers.provider.send("evm_mine", []);

			const timestamp2 = (await ethers.provider.getBlock('latest')).timestamp;
			console.log("Current block timestamp:", timestamp2);

			const earnedRewards = await revenueReward.earnedRewardsAll([USDC], [tokenId]);
			console.log("Earned rewards:", earnedRewards[1][0].toString());
			expect(earnedRewards[1][0]).to.be.gte(0);
			expect(await revenueReward.tokenRewardReceiver(tokenId)).eq(userVault);

			// Get a quote using the SDK
			const quote = await monorail.getQuote({
				from: USDC,	// USDC
				to: USDT, // USDT
				amount: (9n).toString(),
				sender: await userVault.getAddress(),
				destination: await userVault.getAddress(),
				// Optional parameters
				// max_slippage: 50, // 0.5%
				deadline: 2209600, // more than 2 weeks
			});

			console.log("Quote:", quote);

			console.log("Transaction to:", quote.transaction!.to);

			console.log(await userVaultRegistry.isSupportedAggregator(quote.transaction!.to));

			const repayUserDebtParmas : IUserVault.RepayUserDebtParamsStruct = {
				debtToken: USDT,
				poolAddress: "0x9861f6a26050e02Ff0C079657F5a3AFcD8D4af52",
				tokenIds: [tokenId],
				rewardToken: USDC,
				rewardTokenAmountToSwap: 9000000n,
				aggregatorAddress: quote.transaction!.to,
				aggregatorData: quote.transaction!.data!,
				maxSlippageBps: 100n,
			}

			await userVault.repayUserDebt(
				repayUserDebtParmas
			);
			
			expect(await usdc.balanceOf(userVault)).to.equal(0n);
			// TODO check the debt is repaid
		});
	});

	describe('getTokenIdsReward', function () {
		it('Should claim rewards correctly', async function () {
			const {usdc, userVault, tokenId, revenueReward} = await loadFixture(deployProtocolFixture);

			const timestamp1 = (await ethers.provider.getBlock('latest')).timestamp;
			console.log("Current block timestamp:", timestamp1);

			// rewind time by 2 weeks (to be sure)
			await ethers.provider.send("evm_increaseTime", [1209600]);
			await ethers.provider.send("evm_mine", []);

			const timestamp2 = (await ethers.provider.getBlock('latest')).timestamp;
			console.log("Current block timestamp:", timestamp2);

			const earnedRewards = await revenueReward.earnedRewardsAll([USDC], [tokenId]);
			console.log("Earned rewards:", earnedRewards[1][0].toString());
			expect(earnedRewards[1][0]).to.be.gte(0);
			expect(await revenueReward.tokenRewardReceiver(tokenId)).eq(userVault);
			expect(await usdc.balanceOf(userVault)).to.equal(0n);

			await userVault.getTokenIdsReward([tokenId], USDC);

			expect(await usdc.balanceOf(userVault)).to.equal(earnedRewards[1][0]);
		});
	});

	describe('swapAndVerify', function () {
		it('Should swap tokens correctly', async function () {
			const {userVaultRegistry, usdc, usdt, userVault, monorail} = await loadFixture(deployProtocolFixture);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdc.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdc.balanceOf(userVault)).to.equal(9000000n);

			// Get a quote using the SDK
			const quote = await monorail.getQuote({
				from: USDC,	// USDC
				to: USDT, // USDT
				amount: (9n).toString(),
				sender: await userVault.getAddress(),
				destination: await userVault.getAddress(),
				// Optional parameters
				// max_slippage: 50, // 0.5%
				// deadline: 60, // 60 seconds
			});

			console.log("Quote:", quote);

			console.log("Transaction to:", quote.transaction!.to);

			console.log(await userVaultRegistry.isSupportedAggregator(quote.transaction!.to));

			await userVault.swapAndVerify(
				USDC,
				9000000n,
				USDT,
				quote.transaction!.to,
				quote.transaction!.data!,
				100n
			);
			
			const usdtAfter = await usdt.balanceOf(userVault);
			expect(usdtAfter).to.be.gte(8910000); // 9 USDT - 1% slippage
			expect(await usdc.balanceOf(userVault)).to.equal(0n);
		});

		it('Should revert if token doesn\'t have oracle price', async function () {
			const {userVaultRegistry, usdc, userVault, monorail} = await loadFixture(deployProtocolFixture);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdc.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdc.balanceOf(userVault)).to.equal(9000000n);

			// Get a quote using the SDK
			const quote = await monorail.getQuote({
				from: USDC,	// USDC
				to: USDT, // USDT
				amount: (9n).toString(),
				sender: await userVault.getAddress(),
				destination: await userVault.getAddress(),
				// Optional parameters
				// max_slippage: 50, // 0.5%
				// deadline: 60, // 60 seconds
			});

			console.log("Quote:", quote);

			console.log("Transaction to:", quote.transaction!.to);

			console.log(await userVaultRegistry.isSupportedAggregator(quote.transaction!.to));


			let action = userVault.swapAndVerify(
				USDC,
				9000000n,
				"0x268E4E24E0051EC27b3D27A95977E71cE6875a05",
				quote.transaction!.to,
				quote.transaction!.data!,
				100n
			);
			
			await expect(action).to.be.reverted;
		});
	});

	describe('repayDebt', function () {
		it('Should repay debt correctly', async function () {
			const {usdt, userVault} = await loadFixture(deployProtocolFixture);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdt.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdt.balanceOf(userVault)).to.equal(9000000n);

			await userVault.repayDebt(
				"0x9861f6a26050e02Ff0C079657F5a3AFcD8D4af52",
				USDT,
				9000000n
			);

			// TODO check the debt is repaid
		});

		it('Should revert if user has no particular debt', async function () {
			const {usdc, userVault} = await loadFixture(deployProtocolFixture);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdc.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdc.balanceOf(userVault)).to.equal(9000000n);

			let action = userVault.repayDebt(
				"0x9861f6a26050e02Ff0C079657F5a3AFcD8D4af52",
				USDC,
				9000000n
			);

			await expect(action).to.be.revertedWith("39");
		});
	});

	describe('depositCollateral', function () {
		it('Should deposit collateral correctly', async function () {
			const {usdc, userVault} = await loadFixture(deployProtocolFixture);

			const usdcWhaleAddress = "0xFA735CcA8424e4eF30980653bf9015331d9929dB";

			await ethers.provider.send("hardhat_impersonateAccount", [usdcWhaleAddress]);
			const usdcWhale = await ethers.getSigner(usdcWhaleAddress);

			// Send 9 USDC to user vault
			await usdc.connect(usdcWhale).transfer(userVault, 9000000n);

			expect(await usdc.balanceOf(userVault)).to.equal(9000000n);

			await userVault.depositCollateral(
				"0x9861f6a26050e02Ff0C079657F5a3AFcD8D4af52",
				USDC,
				9000000n
			);

			// TODO: Check if collateral was deposited
		});
	});
});
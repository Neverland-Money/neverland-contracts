import {task} from 'hardhat/config';

import { attachProxyAdminV5 } from '@openzeppelin/hardhat-upgrades/dist/utils';

task('deploy-dust', 'Deploy DUST and veDUST contracts')
	.addParam('admin', 'The admin address for the ProxyAdmin and the DUST token')
	.setAction(async ({ admin }, hre) => {
		// const ProxyAdmin = await hre.ethers.getContractFactory("ProxyAdmin");
		// const proxyAdmin = await ProxyAdmin.deploy(admin);
		// await proxyAdmin.waitForDeployment();

		// const Dust = await hre.ethers.getContractFactory("Dust");
		// const dustProxy = await hre.upgrades.deployProxy(Dust, [admin], {
		// 	kind: "transparent",
		// 	initialOwner: admin,
		// 	verifySourceCode: true,
		// });
		// await dustProxy.waitForDeployment();
		// console.log("DUST (proxy) deployed to:", await dustProxy.getAddress());
	}
);

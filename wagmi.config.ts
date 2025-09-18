import { defineConfig } from '@wagmi/cli'
import { hardhat } from '@wagmi/cli/plugins';

export default defineConfig({
  out: 'artifacts/types/src/generated.ts',
  contracts: [],
  plugins: [
    hardhat({
      artifacts: './artifacts',
      project: '.',
      include: [`src/**`],
    }),
  ],
})

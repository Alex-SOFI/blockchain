import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
    polygonMumbai: {
      url: "https://polygon-mumbai-bor.publicnode.com",
      accounts: [
        '8586b56ffb239a764574ad29f427d95cf75804a2d491c7ab9348ad2b4e58681e'
      ],
      from: '0xED2dA4A525d93C83Db9AA76432f0311ed2B9A1c8'
    }
  },
  etherscan: {
    apiKey: {
      polygonMumbai: 'MKMHVQKQQ6ZZ84KS3ZG11FUDICGN3X8Z1T'
    }
  },
  sourcify: {
    enabled: true,
  }
};

export default config;

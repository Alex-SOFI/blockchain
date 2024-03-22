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
    },
    polygon: {
      url: "https://rpc-mainnet.maticvigil.com/",
      accounts: [
        '5db18592073467168889eb28ede6b88f93b98b45ce7eb85935e02697c283a07b'
      ],
      from: '0x42295f5e77f30755eaEB1B8347E87557654DB4cf'
    }
  },
  etherscan: {
    apiKey: {
      polygonMumbai: 'MKMHVQKQQ6ZZ84KS3ZG11FUDICGN3X8Z1T',
      polygon: 'MKMHVQKQQ6ZZ84KS3ZG11FUDICGN3X8Z1T'
    }
  },
  sourcify: {
    enabled: true,
  }
};

export default config;

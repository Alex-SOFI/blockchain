import { formatEther, parseEther } from "viem";
import hre from "hardhat";

const USDC_TOKEN = '0x0c86A754A29714C4Fe9C6F1359fa7099eD174c0b'
const ROUTER = '0xE592427A0AEce92De3Edee1F18E0157C05861564'
const FACTORY = '0x1F98431c8aD98523631AE4a59f267346ea31F984'

async function main() {
  const tokenManager = await hre.viem.deployContract("TokenManager", [USDC_TOKEN, ROUTER, FACTORY], {})
  const sofiToken = await hre.viem.deployContract("SofiToken", [tokenManager.address], {})

  await setTimeout(async () => {
    await hre.run("verify:verify", {
      address: tokenManager.address,
      constructorArguments: [USDC_TOKEN, ROUTER, FACTORY],
    });
  
    await hre.run("verify:verify", {
      address: sofiToken.address,
      constructorArguments: [tokenManager.address],
    });
  }, 180000)

  console.log("TokenManager Address", tokenManager.address)
  console.log("SofiToken Address", sofiToken.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

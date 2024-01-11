import { formatEther, parseEther } from "viem";
import hre from "hardhat";

const USDC_TOKEN = '0xb79399E8a168291ed7039f6DaEce274c0f68caA7'
const ROUTER = '0xE592427A0AEce92De3Edee1F18E0157C05861564'

async function main() {
  const tokenManager = await hre.viem.deployContract("TokenManager", [USDC_TOKEN, ROUTER], {})
  const sofiToken = await hre.viem.deployContract("SofiToken", [tokenManager.address], {})

  await setTimeout(() => console.log('Timeout'), 60000)

  await hre.run("verify:verify", {
    address: tokenManager.address,
    constructorArguments: [USDC_TOKEN, ROUTER],
  });

  await hre.run("verify:verify", {
    address: sofiToken.address,
    constructorArguments: [tokenManager.address],
  });

  console.log("TokenManager Address", tokenManager.address)
  console.log("SofiToken Address", sofiToken.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

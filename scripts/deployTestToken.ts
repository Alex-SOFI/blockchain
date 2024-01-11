import { formatEther, parseEther } from "viem";
import hre from "hardhat";

async function main() {
  const usdcToken = await hre.viem.deployContract("UsdcToken", [], {})

  await hre.run("verify:verify", {
    address: usdcToken.address,
    constructorArguments: [],
  });

  console.log("UsdcToken Address", usdcToken.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

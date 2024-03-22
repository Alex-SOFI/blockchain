import { formatEther, parseEther } from "viem";
import hre from "hardhat";

async function main() {
  console.log("Start deploy")
  const token = await hre.viem.deployContract("SampleToken", ["ETH", "ETH", 1000000000000000000000], {})

  console.log("Token Address", token.address)

  await setTimeout(async () => {
    await hre.run("verify:verify", {
      address: token.address,
      constructorArguments: ["ETH", "ETH", 1000000000000000000000],
    });
  }, 180000)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

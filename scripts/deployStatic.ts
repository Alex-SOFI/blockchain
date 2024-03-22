import { formatEther, parseEther } from "viem";
import hre from "hardhat";

const USDC_TOKEN = '0x0c86A754A29714C4Fe9C6F1359fa7099eD174c0b'

async function main() {
  const staticPool = await hre.viem.deployContract("StaticPool", [
    USDC_TOKEN,
    50,
    1000,
    '0xED2dA4A525d93C83Db9AA76432f0311ed2B9A1c8'
  ], {})

  await staticPool.write.bind([
    '0xfF9b1273f5722C16C4f0b9E9a5aeA83006FE6152',
    50,
    '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    '0xE592427A0AEce92De3Edee1F18E0157C05861564',
    10000
  ]);

  await setTimeout(async () => {
    await hre.run("verify:verify", {
      address: staticPool.address,
      constructorArguments: [
        USDC_TOKEN,
        50,
        1000,
        '0xED2dA4A525d93C83Db9AA76432f0311ed2B9A1c8'
      ],
    });

  }, 120000)

  console.log("Static Pool Address", staticPool.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

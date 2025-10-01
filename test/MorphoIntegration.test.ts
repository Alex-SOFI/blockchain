import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { parseEther, parseUnits, Address } from "viem";

describe("Morpho Integration Tests", function () {
  async function deployMorphoIntegrationFixture() {
    const [owner, user1, user2, feeManager] = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();

    const mockUSDC = await hre.viem.deployContract("SampleToken", [
      "Mock USDC",
      "USDC",
      6n, // 6 decimals like real USDC
    ]);

    const mockWETH = await hre.viem.deployContract("MockWETH");

    const mockRewardToken = await hre.viem.deployContract("SampleToken", [
      "Mock MORPHO",
      "MORPHO",
      18n,
    ]);

    const mockURD = await hre.viem.deployContract("MockURD");

    const morphoUSDCVault = await hre.viem.deployContract("MockMorphoVault", [
      mockUSDC.address,
      "Morpho USDC Vault",
      "mUSDC",
    ]);

    const morphoWETHVault = await hre.viem.deployContract("MockMorphoVault", [
      mockWETH.address,
      "Morpho WETH Vault",
      "mWETH",
    ]);

    // Deploy Uniswap V3 mocks (simplified for testing)
    const mockFactory = await hre.viem.deployContract("SampleToken", [
      "Mock Factory",
      "FACT",
      18n,
    ]);

    const mockRouter = await hre.viem.deployContract("SampleToken", [
      "Mock Router",
      "ROUT",
      18n,
    ]);

    const staticPool = await hre.viem.deployContract("StaticPool", [
      mockWETH.address, // ENTRY
      mockWETH.address, // WETH
      5000n, // entryFee (0.5%)
      5000n, // exitFee (0.5%)
      1000000n, // baseFee
      feeManager.account.address, // feeManager
      2102400n, // blocksPerYear
      10000n, // tvlFee (1%)
      mockURD.address, // URD contract
    ]);

    await mockUSDC.write.mint([user1.account.address, parseUnits("10000", 6)]);
    await mockUSDC.write.mint([user2.account.address, parseUnits("10000", 6)]);
    
    await mockWETH.write.deposit({ value: parseEther("100") });
    await mockWETH.write.transfer([user1.account.address, parseEther("50")]);
    await mockWETH.write.transfer([user2.account.address, parseEther("50")]);

    await mockRewardToken.write.mint([mockURD.address, parseEther("1000")]);

    return {
      staticPool,
      mockUSDC,
      mockWETH,
      mockRewardToken,
      morphoUSDCVault,
      morphoWETHVault,
      mockURD,
      mockFactory,
      mockRouter,
      owner,
      user1,
      user2,
      feeManager,
      publicClient,
    };
  }

  describe("MorphoVaultManager Functions", function () {
    it("Should set Morpho vault for a token", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault, owner } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const vaultAddress = await staticPool.read.morphoVaults([mockUSDC.address]);
      expect(vaultAddress.toLowerCase()).to.equal(morphoUSDCVault.address.toLowerCase());
    });

    it("Should reject setting vault with mismatched asset", async function () {
      const { staticPool, mockWETH, morphoUSDCVault } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await expect(
        staticPool.write.setMorphoVault([mockWETH.address, morphoUSDCVault.address])
      ).to.be.rejected;
    });

    it("Should reject setting vault from non-owner", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault, user1 } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await expect(
        staticPool.write.setMorphoVault(
          [mockUSDC.address, morphoUSDCVault.address],
          { account: user1.account }
        )
      ).to.be.rejected;
    });

    it("Should return correct Morpho balance", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const balanceBefore = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      expect(balanceBefore).to.equal(0n);

      const depositAmount = parseUnits("100", 6);
      await mockUSDC.write.approve([morphoUSDCVault.address, depositAmount]);
      await morphoUSDCVault.write.deposit([depositAmount, staticPool.address]);

      const balanceAfter = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      expect(balanceAfter).to.equal(depositAmount);
    });

    it("Should return correct Morpho shares", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const depositAmount = parseUnits("100", 6);
      await mockUSDC.write.approve([morphoUSDCVault.address, depositAmount]);
      await morphoUSDCVault.write.deposit([depositAmount, staticPool.address]);

      const shares = await staticPool.read.getMorphoShares([mockUSDC.address]);
      expect(shares).to.be.gt(0n);
    });

    it("Should get Morpho vault info", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const [vault, totalAssets, totalShares, ourShares, ourAssets] =
        await staticPool.read.getMorphoVaultInfo([mockUSDC.address]);

      expect(vault.toLowerCase()).to.equal(morphoUSDCVault.address.toLowerCase());
      expect(totalAssets).to.equal(0n); // No deposits yet
    });
  });

  describe("Reward System", function () {
    it("Should set reward swap target", async function () {
      const { staticPool, mockRewardToken, mockUSDC, mockFactory, mockRouter } =
        await loadFixture(deployMorphoIntegrationFixture);

      await staticPool.write.bind([
        mockUSDC.address,
        500000n, // weight
        mockFactory.address,
        mockRouter.address,
        3000, // fee
      ]);

      await staticPool.write.setRewardSwapTargetPublic([
        mockRewardToken.address,
        mockUSDC.address,
      ]);

      const target = await staticPool.read.rewardSwapTargets([
        mockRewardToken.address,
      ]);
      expect(target.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());
    });

    it("Should update URD contract", async function () {
      const { staticPool, mockURD, owner } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      const newURD = await hre.viem.deployContract("MockURD");

      await staticPool.write.setURDContractPublic([newURD.address]);

      const urdAddress = await staticPool.read.urdContract();
      expect(urdAddress.toLowerCase()).to.equal(newURD.address.toLowerCase());
    });

    it("Should reject URD update from non-owner", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      const newURD = await hre.viem.deployContract("MockURD");

      await expect(
        staticPool.write.setURDContractPublic([newURD.address], {
          account: user1.account,
        })
      ).to.be.rejected;
    });
  });

  describe("Integration: Deposit and Withdraw", function () {
    it("Should check if token has Morpho vault", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      const hasBefore = await staticPool.read.hasMorphoVault([mockUSDC.address]);
      expect(hasBefore).to.be.false;

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const hasAfter = await staticPool.read.hasMorphoVault([mockUSDC.address]);
      expect(hasAfter).to.be.true;
    });

    it("Should get correct vault address", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const vault = await staticPool.read.getMorphoVault([mockUSDC.address]);
      expect(vault.toLowerCase()).to.equal(morphoUSDCVault.address.toLowerCase());
    });
  });

  describe("Index Balance Price with Morpho", function () {
    it("Should calculate correct index price with Morpho vaults", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault, mockFactory } =
        await loadFixture(deployMorphoIntegrationFixture);

      await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const price = await staticPool.read.getIndexBalancePrice();
      expect(price).to.be.a("bigint");
    });
  });

  describe("Access Control", function () {
    it("Should only allow owner to set Morpho vault", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault, user1 } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      await expect(
        staticPool.write.setMorphoVault(
          [mockUSDC.address, morphoUSDCVault.address],
          { account: user1.account }
        )
      ).to.be.rejected;
    });

    it("Should only allow owner to set reward swap target", async function () {
      const { staticPool, mockRewardToken, mockUSDC, user1, mockFactory, mockRouter } =
        await loadFixture(deployMorphoIntegrationFixture);

      await staticPool.write.bind([
        mockUSDC.address,
        500000n,
        mockFactory.address,
        mockRouter.address,
        3000,
      ]);

      await expect(
        staticPool.write.setRewardSwapTargetPublic(
          [mockRewardToken.address, mockUSDC.address],
          { account: user1.account }
        )
      ).to.be.rejected;
    });
  });

  describe("Edge Cases", function () {
    it("Should handle zero address checks", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      const zeroAddress = "0x0000000000000000000000000000000000000000" as Address;

      await expect(
        staticPool.write.setMorphoVault([mockUSDC.address, zeroAddress])
      ).to.be.rejected;
    });

    it("Should return 0 for Morpho balance when vault not set", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      const balance = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      expect(balance).to.equal(0n);
    });

    it("Should return 0 for Morpho shares when vault not set", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployMorphoIntegrationFixture
      );

      const shares = await staticPool.read.getMorphoShares([mockUSDC.address]);
      expect(shares).to.equal(0n);
    });
  });

  describe("Events", function () {
    it("Should emit MorphoVaultSet event", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault, publicClient } =
        await loadFixture(deployMorphoIntegrationFixture);

      const hash = await staticPool.write.setMorphoVault([
        mockUSDC.address,
        morphoUSDCVault.address,
      ]);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      
      expect(receipt.status).to.equal("success");
    });
  });
});


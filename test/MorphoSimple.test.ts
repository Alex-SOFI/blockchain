import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { parseUnits, parseEther } from "viem";

describe("Morpho Mock Contracts Tests", function () {
  async function deployMockFixture() {
    const [owner, user1] = await hre.viem.getWalletClients();

    const mockUSDC = await hre.viem.deployContract("SampleToken", [
      "Mock USDC",
      "USDC",
      6n,
    ]);

    const morphoVault = await hre.viem.deployContract("MockMorphoVault", [
      mockUSDC.address,
      "Morpho USDC Vault",
      "mUSDC",
    ]);

    const mockURD = await hre.viem.deployContract("MockURD");

    await mockUSDC.write.mint([owner.account.address, parseUnits("10000", 6)]);
    await mockUSDC.write.mint([user1.account.address, parseUnits("10000", 6)]);

    return {
      morphoVault,
      mockUSDC,
      mockURD,
      owner,
      user1,
    };
  }

  describe("MockMorphoVault", function () {
    it("Should deploy with correct asset", async function () {
      const { morphoVault, mockUSDC } = await loadFixture(deployMockFixture);

      const asset = await morphoVault.read.asset();
      expect(asset.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());
    });

    it("Should allow deposits", async function () {
      const { morphoVault, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const depositAmount = parseUnits("100", 6);
      await mockUSDC.write.approve([morphoVault.address, depositAmount]);

      const sharesBefore = await morphoVault.read.balanceOf([owner.account.address]);
      expect(sharesBefore).to.equal(0n);

      await morphoVault.write.deposit([depositAmount, owner.account.address]);

      const sharesAfter = await morphoVault.read.balanceOf([owner.account.address]);
      expect(sharesAfter > 0n).to.be.true;
    });

    it("Should convert shares to assets correctly", async function () {
      const { morphoVault, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const depositAmount = parseUnits("100", 6);
      await mockUSDC.write.approve([morphoVault.address, depositAmount]);
      await morphoVault.write.deposit([depositAmount, owner.account.address]);

      const shares = await morphoVault.read.balanceOf([owner.account.address]);
      const assets = await morphoVault.read.convertToAssets([shares]);

      expect(assets).to.equal(depositAmount);
    });

    it("Should allow withdrawals", async function () {
      const { morphoVault, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const depositAmount = parseUnits("100", 6);
      await mockUSDC.write.approve([morphoVault.address, depositAmount]);
      await morphoVault.write.deposit([depositAmount, owner.account.address]);

      const balanceBefore = await mockUSDC.read.balanceOf([owner.account.address]);
      const shares = await morphoVault.read.balanceOf([owner.account.address]);

      await morphoVault.write.redeem([
        shares,
        owner.account.address,
        owner.account.address,
      ]);

      const balanceAfter = await mockUSDC.read.balanceOf([owner.account.address]);
      expect(balanceAfter > balanceBefore).to.be.true;
    });

    it("Should track total assets correctly", async function () {
      const { morphoVault, mockUSDC, owner, user1 } = await loadFixture(
        deployMockFixture
      );

      const depositAmount = parseUnits("100", 6);
      
      await mockUSDC.write.approve([morphoVault.address, depositAmount]);
      await morphoVault.write.deposit([depositAmount, owner.account.address]);

      await mockUSDC.write.approve([morphoVault.address, depositAmount], {
        account: user1.account,
      });
      await morphoVault.write.deposit([depositAmount, user1.account.address], {
        account: user1.account,
      });

      const totalAssets = await morphoVault.read.totalAssets();
      expect(totalAssets).to.equal(depositAmount * 2n);
    });

    it("Should simulate yield generation", async function () {
      const { morphoVault, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const depositAmount = parseUnits("100", 6);
      await mockUSDC.write.approve([morphoVault.address, depositAmount]);
      await morphoVault.write.deposit([depositAmount, owner.account.address]);

      const sharesBefore = await morphoVault.read.balanceOf([owner.account.address]);
      const assetsBefore = await morphoVault.read.convertToAssets([sharesBefore]);

      const yieldAmount = parseUnits("10", 6);
      await morphoVault.write.simulateYield([yieldAmount]);

      const assetsAfter = await morphoVault.read.convertToAssets([sharesBefore]);
      expect(assetsAfter > assetsBefore).to.be.true;
    });
  });

  describe("MockURD", function () {
    it("Should track claimed amounts", async function () {
      const { mockURD, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const claimed = await mockURD.read.claimed([
        owner.account.address,
        mockUSDC.address,
      ]);

      expect(claimed).to.equal(0n);
    });

    it("Should allow setting claimed amounts", async function () {
      const { mockURD, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const claimAmount = parseUnits("50", 6);
      await mockURD.write.setClaimedAmount([
        owner.account.address,
        mockUSDC.address,
        claimAmount,
      ]);

      const claimed = await mockURD.read.claimed([
        owner.account.address,
        mockUSDC.address,
      ]);

      expect(claimed).to.equal(claimAmount);
    });

    it("Should allow funding with rewards", async function () {
      const { mockURD, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const fundAmount = parseUnits("1000", 6);
      await mockUSDC.write.approve([mockURD.address, fundAmount]);
      await mockURD.write.fundRewards([mockUSDC.address, fundAmount]);

      const balance = await mockUSDC.read.balanceOf([mockURD.address]);
      expect(balance).to.equal(fundAmount);
    });

    it("Should claim rewards correctly", async function () {
      const { mockURD, mockUSDC, owner } = await loadFixture(deployMockFixture);

      const fundAmount = parseUnits("1000", 6);
      await mockUSDC.write.approve([mockURD.address, fundAmount]);
      await mockURD.write.fundRewards([mockUSDC.address, fundAmount]);

      const claimable = parseUnits("100", 6);
      const proof: `0x${string}`[] = [];

      const balanceBefore = await mockUSDC.read.balanceOf([owner.account.address]);

      await mockURD.write.claim([
        owner.account.address,
        mockUSDC.address,
        claimable,
        proof,
      ]);

      const balanceAfter = await mockUSDC.read.balanceOf([owner.account.address]);
      expect(balanceAfter - balanceBefore).to.equal(claimable);
    });
  });

  describe("ERC4626 Compliance", function () {
    it("Should implement all ERC4626 view functions", async function () {
      const { morphoVault, mockUSDC } = await loadFixture(deployMockFixture);

      const depositAmount = parseUnits("100", 6);

      const previewDeposit = await morphoVault.read.previewDeposit([depositAmount]);
      expect(previewDeposit > 0n).to.be.true;

      const shares = await morphoVault.read.previewDeposit([depositAmount]);
      const previewRedeem = await morphoVault.read.previewRedeem([shares]);
      expect(previewRedeem > 0n).to.be.true;

      const previewWithdraw = await morphoVault.read.previewWithdraw([depositAmount]);
      expect(previewWithdraw > 0n).to.be.true;

      const previewMint = await morphoVault.read.previewMint([shares]);
      expect(previewMint > 0n).to.be.true;
    });

    it("Should implement max functions", async function () {
      const { morphoVault, owner } = await loadFixture(deployMockFixture);

      const maxDeposit = await morphoVault.read.maxDeposit([owner.account.address]);
      expect(maxDeposit > 0n).to.be.true;

      const maxMint = await morphoVault.read.maxMint([owner.account.address]);
      expect(maxMint > 0n).to.be.true;
    });
  });
});


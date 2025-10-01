import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { parseEther, parseUnits, Address } from "viem";

describe("Morpho Vault Integration Advanced Tests", function () {
  
  async function deployMorphoVaultIntegrationFixture() {
    const [owner, user1, user2, user3, feeManager] = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();

    const mockWETH = await hre.viem.deployContract("MockWETH");
    const mockUSDC = await hre.viem.deployContract("SampleToken", ["USDC", "USDC", 6n]);
    const mockDAI = await hre.viem.deployContract("SampleToken", ["DAI", "DAI", 18n]);
    const mockUSDT = await hre.viem.deployContract("SampleToken", ["USDT", "USDT", 6n]);
    const mockWBTC = await hre.viem.deployContract("SampleToken", ["WBTC", "WBTC", 8n]);

    const morphoUSDCVault = await hre.viem.deployContract("MockMorphoVault", [
      mockUSDC.address,
      "Morpho USDC",
      "mUSDC",
    ]);

    const morphoDAIVault = await hre.viem.deployContract("MockMorphoVault", [
      mockDAI.address,
      "Morpho DAI",
      "mDAI",
    ]);

    const morphoWBTCVault = await hre.viem.deployContract("MockMorphoVault", [
      mockWBTC.address,
      "Morpho WBTC",
      "mWBTC",
    ]);

    const mockURD = await hre.viem.deployContract("MockURD");
    const mockFactory = await hre.viem.deployContract("SampleToken", ["Factory", "FACT", 18n]);
    const mockRouter = await hre.viem.deployContract("SampleToken", ["Router", "ROUT", 18n]);

    const staticPool = await hre.viem.deployContract("StaticPoolV2", [
      mockWETH.address,
      mockWETH.address,
      5000n,
      5000n,
      1000000n,
      feeManager.account.address,
      2102400n,
      10000n,
      mockURD.address,
    ]);

    await staticPool.write.bind([
      mockUSDC.address,
      300000n,
      mockFactory.address,
      mockRouter.address,
      3000,
    ]);

    await staticPool.write.bind([
      mockDAI.address,
      300000n,
      mockFactory.address,
      mockRouter.address,
      3000,
    ]);

    await staticPool.write.bind([
      mockUSDT.address,
      200000n,
      mockFactory.address,
      mockRouter.address,
      3000,
    ]);

    await staticPool.write.bind([
      mockWBTC.address,
      200000n,
      mockFactory.address,
      mockRouter.address,
      3000,
    ]);

    await staticPool.write.setMorphoVault([mockUSDC.address, morphoUSDCVault.address]);
    await staticPool.write.setMorphoVault([mockDAI.address, morphoDAIVault.address]);
    await staticPool.write.setMorphoVault([mockWBTC.address, morphoWBTCVault.address]);

    await mockWETH.write.deposit({ value: parseEther("1000") });
    await mockWETH.write.transfer([user1.account.address, parseEther("300")]);
    await mockWETH.write.transfer([user2.account.address, parseEther("300")]);
    await mockWETH.write.transfer([user3.account.address, parseEther("200")]);

    await mockUSDC.write.mint([staticPool.address, parseUnits("100000", 6)]);
    await mockDAI.write.mint([staticPool.address, parseEther("100000")]);
    await mockUSDT.write.mint([staticPool.address, parseUnits("100000", 6)]);
    await mockWBTC.write.mint([staticPool.address, parseUnits("100", 8)]);

    return {
      staticPool,
      mockWETH,
      mockUSDC,
      mockDAI,
      mockUSDT,
      mockWBTC,
      morphoUSDCVault,
      morphoDAIVault,
      morphoWBTCVault,
      mockURD,
      owner,
      user1,
      user2,
      user3,
      feeManager,
      publicClient,
    };
  }

  describe("Multiple Morpho Vaults", function () {
    it("Should distribute deposits across multiple Morpho Vaults", async function () {
      const { staticPool, user1, morphoUSDCVault, morphoDAIVault, morphoWBTCVault } =
        await loadFixture(deployMorphoVaultIntegrationFixture);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const usdcShares = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      const daiShares = await morphoDAIVault.read.balanceOf([staticPool.address]);
      const wbtcShares = await morphoWBTCVault.read.balanceOf([staticPool.address]);

      expect(usdcShares).to.be.greaterThan(0n);
      expect(daiShares).to.be.greaterThan(0n);
      expect(wbtcShares).to.be.greaterThan(0n);
    });

    it("Should track balances in multiple Morpho Vaults simultaneously", async function () {
      const { staticPool, user1, mockUSDC, mockDAI, mockWBTC } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const usdcBalance = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      const daiBalance = await staticPool.read.getMorphoBalance([mockDAI.address]);
      const wbtcBalance = await staticPool.read.getMorphoBalance([mockWBTC.address]);

      expect(usdcBalance).to.be.greaterThan(0n);
      expect(daiBalance).to.be.greaterThan(0n);
      expect(wbtcBalance).to.be.greaterThan(0n);

      const totalWeight = await staticPool.read._totalWeight();
      expect(totalWeight).to.equal(1000000n);
    });

    it("Should retrieve info for all Morpho Vaults", async function () {
      const { staticPool, user1, mockUSDC, mockDAI, mockWBTC } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const [vault1, totalAssets1, totalShares1, ourShares1, ourAssets1] =
        await staticPool.read.getMorphoVaultInfo([mockUSDC.address]);

      expect(totalAssets1).to.be.greaterThan(0n);
      expect(ourShares1).to.be.greaterThan(0n);

      const [vault2, totalAssets2, totalShares2, ourShares2, ourAssets2] =
        await staticPool.read.getMorphoVaultInfo([mockDAI.address]);

      expect(totalAssets2).to.be.greaterThan(0n);
      expect(ourShares2).to.be.greaterThan(0n);

      const [vault3, totalAssets3, totalShares3, ourShares3, ourAssets3] =
        await staticPool.read.getMorphoVaultInfo([mockWBTC.address]);

      expect(totalAssets3).to.be.greaterThan(0n);
      expect(ourShares3).to.be.greaterThan(0n);
    });
  });

  describe("Yield Generation", function () {
    it("Should account for yield from single Morpho Vault", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const indexPriceBefore = await staticPool.read.getIndexBalancePrice();

      const yieldAmount = parseUnits("1000", 6);
      await morphoUSDCVault.write.simulateYield([yieldAmount]);

      const indexPriceAfter = await staticPool.read.getIndexBalancePrice();

      expect(indexPriceAfter).to.be.greaterThan(indexPriceBefore);
    });

    it("Should account for yield from multiple Morpho Vaults", async function () {
      const { staticPool, user1, morphoUSDCVault, morphoDAIVault, morphoWBTCVault } =
        await loadFixture(deployMorphoVaultIntegrationFixture);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const indexPriceBefore = await staticPool.read.getIndexBalancePrice();

      await morphoUSDCVault.write.simulateYield([parseUnits("500", 6)]);
      await morphoDAIVault.write.simulateYield([parseEther("500")]);
      await morphoWBTCVault.write.simulateYield([parseUnits("0.5", 8)]);

      const indexPriceAfter = await staticPool.read.getIndexBalancePrice();

      expect(indexPriceAfter).to.be.greaterThan(indexPriceBefore);
      
      const increase = indexPriceAfter - indexPriceBefore;
      expect(increase > indexPriceBefore / 100n).to.be.true;
    });

    it("Should distribute yield proportionally between users", async function () {
      const { staticPool, user1, user2, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("60"),
      });

      const user1Tokens = await staticPool.read.balanceOf([user1.account.address]);

      await morphoUSDCVault.write.simulateYield([parseUnits("1000", 6)]);

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("40"),
      });

      const user2Tokens = await staticPool.read.balanceOf([user2.account.address]);

      expect(user1Tokens).to.be.greaterThan(user2Tokens);

      const user1Preview = await staticPool.read.previewRedeem([user1Tokens]);
      const user2Preview = await staticPool.read.previewRedeem([user2Tokens]);

      expect(user1Preview).to.be.greaterThan(user2Preview);
    });

    it("Should allow users to withdraw with yield", async function () {
      const { staticPool, user1, morphoUSDCVault, morphoDAIVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const depositAmount = parseEther("100");

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: depositAmount,
      });

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      const expectedBefore = await staticPool.read.previewRedeem([poolTokens]);

      await morphoUSDCVault.write.simulateYield([parseUnits("5000", 6)]);
      await morphoDAIVault.write.simulateYield([parseEther("5000")]);

      const expectedAfter = await staticPool.read.previewRedeem([poolTokens]);

      expect(expectedAfter).to.be.greaterThan(expectedBefore);
    });
  });

  describe("Vault Migration", function () {
    it("Should allow changing Morpho Vault for a token", async function () {
      const { staticPool, user1, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const oldShares = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      expect(oldShares).to.be.greaterThan(0n);

      const newMorphoVault = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDC.address,
        "New Morpho USDC",
        "nmUSDC",
      ]);

      await staticPool.write.setMorphoVault([mockUSDC.address, newMorphoVault.address]);

      const newVaultAddress = await staticPool.read.morphoVaults([mockUSDC.address]);
      expect(newVaultAddress.toLowerCase()).to.equal(newMorphoVault.address.toLowerCase());

      expect(oldShares).to.be.greaterThan(0n);
    });

    it("Should reset approval for old vault when changing", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const vault1 = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDC.address,
        "Vault1",
        "V1",
      ]);

      const vault2 = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDC.address,
        "Vault2",
        "V2",
      ]);

      await staticPool.write.setMorphoVault([mockUSDC.address, vault1.address]);

      const allowance1 = await mockUSDC.read.allowance([
        staticPool.address,
        vault1.address,
      ]);
      expect(allowance1).to.be.greaterThan(0n);

      await staticPool.write.setMorphoVault([mockUSDC.address, vault2.address]);

      const allowance1After = await mockUSDC.read.allowance([
        staticPool.address,
        vault1.address,
      ]);
      expect(allowance1After).to.equal(0n);

      const allowance2 = await mockUSDC.read.allowance([
        staticPool.address,
        vault2.address,
      ]);
      expect(allowance2).to.be.greaterThan(0n);
    });
  });

  describe("Mixed Vault Strategy", function () {
    it("Should support both Morpho and regular vaults simultaneously", async function () {
      const { staticPool, user1, mockUSDT, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const regularUSDTVault = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDT.address,
        "Regular USDT Vault",
        "rUSDT",
      ]);

      await staticPool.write.setVault([mockUSDT.address, regularUSDTVault.address]);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const morphoShares = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      expect(morphoShares).to.be.greaterThan(0n);

      const regularShares = await regularUSDTVault.read.balanceOf([staticPool.address]);
      expect(regularShares).to.be.greaterThan(0n);
    });

    it("Should calculate balance correctly with mixed vaults", async function () {
      const { staticPool, user1, mockUSDC, mockUSDT } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const regularVault = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDT.address,
        "USDT Vault",
        "vUSDT",
      ]);

      await staticPool.write.setVault([mockUSDT.address, regularVault.address]);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const usdcBalance = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      const morphoVault = await staticPool.read.morphoVaults([mockUSDC.address]);
      
      expect(usdcBalance).to.be.greaterThan(0n);
      expect(morphoVault).to.not.equal("0x0000000000000000000000000000000000000000");

      const usdtVault = await staticPool.read.tokenVaults([mockUSDT.address]);
      expect(usdtVault.toLowerCase()).to.equal(regularVault.address.toLowerCase());
    });
  });

  describe("Edge Cases", function () {
    it("Should handle deposit to empty vault", async function () {
      const { staticPool, user1, mockUSDC } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const emptyVault = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDC.address,
        "Empty Vault",
        "eVault",
      ]);

      await staticPool.write.setMorphoVault([mockUSDC.address, emptyVault.address]);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const shares = await emptyVault.read.balanceOf([staticPool.address]);
      expect(shares).to.be.greaterThan(0n);
    });

    it("Should handle withdrawal when vault is empty", async function () {
      const { staticPool, user1, user2, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const user1Tokens = await staticPool.read.balanceOf([user1.account.address]);
      await staticPool.write.redeem([user1Tokens], {
        account: user1.account,
      });

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("30"),
      });

      const user2Tokens = await staticPool.read.balanceOf([user2.account.address]);
      expect(user2Tokens).to.be.greaterThan(0n);
    });

    it("Should handle large share/asset imbalance in vault", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const extremeYield = parseUnits("100000", 6);
      await morphoUSDCVault.write.simulateYield([extremeYield]);

      const shares = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      const assets = await morphoUSDCVault.read.convertToAssets([shares]);

      expect(assets).to.be.greaterThan(shares);

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      const expectedRedeem = await staticPool.read.previewRedeem([poolTokens]);
      
      expect(expectedRedeem).to.be.greaterThan(0n);
    });

    it("Should handle multiple consecutive deposits and withdrawals", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      for (let i = 0; i < 5; i++) {
        await staticPool.write.mint([user1.account.address], {
          account: user1.account,
          value: parseEther("10"),
        });
      }

      const totalShares = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      expect(totalShares).to.be.greaterThan(0n);

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      
      for (let i = 0; i < 3; i++) {
        const withdrawAmount = poolTokens / 5n;
        await staticPool.write.redeem([withdrawAmount], {
          account: user1.account,
        });
      }

      const remainingTokens = await staticPool.read.balanceOf([user1.account.address]);
      expect(remainingTokens > 0n).to.be.true;
      expect(remainingTokens).to.be.lessThan(poolTokens);
    });
  });

  describe("Performance", function () {
    it("Should efficiently handle deposits with multiple Morpho Vaults", async function () {
      const { staticPool, user1, publicClient } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const hash = await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).to.equal("success");
    });

    it("Should efficiently handle withdrawals from multiple Morpho Vaults", async function () {
      const { staticPool, user1, publicClient } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);

      const hash = await staticPool.write.redeem([poolTokens], {
        account: user1.account,
      });

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).to.equal("success");
    });
  });

  describe("Real-World Scenarios", function () {
    it("DCA Strategy", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      const deposits: bigint[] = [];

      for (let i = 0; i < 5; i++) {
        await staticPool.write.mint([user1.account.address], {
          account: user1.account,
          value: parseEther("20"),
        });

        deposits.push(await staticPool.read.balanceOf([user1.account.address]));

        if (i < 4) {
          await morphoUSDCVault.write.simulateYield([parseUnits("100", 6)]);
        }
      }

      for (let i = 1; i < deposits.length; i++) {
        const tokensFromDeposit = deposits[i] - deposits[i - 1];
        expect(tokensFromDeposit).to.be.greaterThan(0n);
      }

      const finalBalance = await staticPool.read.balanceOf([user1.account.address]);
      expect(finalBalance).to.equal(deposits[deposits.length - 1]);
    });

    it("Rebalancing after weight changes", async function () {
      const { staticPool, user1, user2, mockUSDC, mockDAI } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const usdcBalance1 = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      const daiBalance1 = await staticPool.read.getMorphoBalance([mockDAI.address]);

      await staticPool.write.changeWeight([mockUSDC.address, 500000n]);
      await staticPool.write.changeWeight([mockDAI.address, 200000n]);

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("100"),
      });

      const usdcBalance2 = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      const daiBalance2 = await staticPool.read.getMorphoBalance([mockDAI.address]);

      const usdcIncrease = usdcBalance2 - usdcBalance1;
      const daiIncrease = daiBalance2 - daiBalance1;

      expect(usdcIncrease).to.be.greaterThan(daiIncrease);
    });

    it("Emergency withdrawal scenario", async function () {
      const { staticPool, user1, user2, user3, morphoUSDCVault, morphoDAIVault } =
        await loadFixture(deployMorphoVaultIntegrationFixture);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("80"),
      });

      await staticPool.write.mint([user3.account.address], {
        account: user3.account,
        value: parseEther("60"),
      });

      const totalSupply = await staticPool.read.totalSupply();
      expect(totalSupply).to.be.greaterThan(0n);

      const user1Tokens = await staticPool.read.balanceOf([user1.account.address]);
      const user2Tokens = await staticPool.read.balanceOf([user2.account.address]);
      const user3Tokens = await staticPool.read.balanceOf([user3.account.address]);

      await staticPool.write.redeem([user1Tokens], { account: user1.account });
      await staticPool.write.redeem([user2Tokens], { account: user2.account });
      await staticPool.write.redeem([user3Tokens], { account: user3.account });

      const finalSupply = await staticPool.read.totalSupply();
      expect(finalSupply).to.equal(0n);

      const usdcShares = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      const daiShares = await morphoDAIVault.read.balanceOf([staticPool.address]);
      
      expect(usdcShares).to.be.lessThan(100n);
      expect(daiShares).to.be.lessThan(parseEther("0.01"));
    });

    it("Compound yield with reinvestment", async function () {
      const { staticPool, user1, morphoUSDCVault, morphoDAIVault } = await loadFixture(
        deployMorphoVaultIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      let previousPrice = await staticPool.read.getIndexBalancePrice();

      for (let i = 0; i < 5; i++) {
        await morphoUSDCVault.write.simulateYield([parseUnits("200", 6)]);
        await morphoDAIVault.write.simulateYield([parseEther("200")]);

        const currentPrice = await staticPool.read.getIndexBalancePrice();
        expect(currentPrice).to.be.greaterThan(previousPrice);
        
        previousPrice = currentPrice;
      }

      const finalPrice = await staticPool.read.getIndexBalancePrice();
      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      const expectedRedeem = await staticPool.read.previewRedeem([poolTokens]);

      expect(expectedRedeem).to.be.greaterThan(parseEther("100"));
    });
  });
});


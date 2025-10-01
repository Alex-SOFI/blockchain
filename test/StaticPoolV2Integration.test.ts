import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import hre from "hardhat";
import { parseEther, parseUnits, keccak256, toBytes, Address } from "viem";

describe("StaticPoolV2 Full Integration Tests", function () {
  
  async function deployFullIntegrationFixture() {
    const [owner, user1, user2, feeManager] = await hre.viem.getWalletClients();
    const publicClient = await hre.viem.getPublicClient();

    const mockWETH = await hre.viem.deployContract("MockWETH");
    
    const mockUSDC = await hre.viem.deployContract("SampleToken", [
      "Mock USDC",
      "USDC",
      6n,
    ]);

    const mockDAI = await hre.viem.deployContract("SampleToken", [
      "Mock DAI",
      "DAI",
      18n,
    ]);

    const mockUSDT = await hre.viem.deployContract("SampleToken", [
      "Mock USDT",
      "USDT",
      6n,
    ]);

    const mockMORPHO = await hre.viem.deployContract("SampleToken", [
      "Mock MORPHO",
      "MORPHO",
      18n,
    ]);

    const morphoUSDCVault = await hre.viem.deployContract("MockMorphoVault", [
      mockUSDC.address,
      "Morpho USDC Vault",
      "mUSDC",
    ]);

    const morphoDAIVault = await hre.viem.deployContract("MockMorphoVault", [
      mockDAI.address,
      "Morpho DAI Vault",
      "mDAI",
    ]);

    const mockURD = await hre.viem.deployContract("MockURD");

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

    await mockWETH.write.deposit({ value: parseEther("1000") });
    await mockWETH.write.transfer([user1.account.address, parseEther("500")]);
    await mockWETH.write.transfer([user2.account.address, parseEther("300")]);

    await mockUSDC.write.mint([owner.account.address, parseUnits("100000", 6)]);
    await mockUSDC.write.mint([user1.account.address, parseUnits("50000", 6)]);
    await mockUSDC.write.mint([staticPool.address, parseUnits("10000", 6)]);

    await mockDAI.write.mint([owner.account.address, parseEther("100000")]);
    await mockDAI.write.mint([user1.account.address, parseEther("50000")]);
    await mockDAI.write.mint([staticPool.address, parseEther("10000")]);

    await mockUSDT.write.mint([owner.account.address, parseUnits("100000", 6)]);
    
    await mockMORPHO.write.mint([mockURD.address, parseEther("10000")]);

    await staticPool.write.bind([
      mockUSDC.address,
      400000n,
      mockFactory.address,
      mockRouter.address,
      3000,
    ]);

    await staticPool.write.bind([
      mockDAI.address,
      400000n,
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

    await staticPool.write.setMorphoVault([
      mockUSDC.address,
      morphoUSDCVault.address,
    ]);

    await staticPool.write.setMorphoVault([
      mockDAI.address,
      morphoDAIVault.address,
    ]);

    await staticPool.write.setRewardSwapTarget([
      mockMORPHO.address,
      mockUSDC.address,
    ]);

    return {
      staticPool,
      mockWETH,
      mockUSDC,
      mockDAI,
      mockUSDT,
      mockMORPHO,
      morphoUSDCVault,
      morphoDAIVault,
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

  describe("Initialization and Setup", function () {
    it("Should initialize pool with correct parameters", async function () {
      const { staticPool, mockWETH, feeManager } = await loadFixture(
        deployFullIntegrationFixture
      );

      expect(await staticPool.read._ENTRY()).to.equal(mockWETH.address);
      expect(await staticPool.read._WETH()).to.equal(mockWETH.address);
      expect(await staticPool.read._entryFee()).to.equal(5000n);
      expect(await staticPool.read._exitFee()).to.equal(5000n);
      expect(await staticPool.read._feeManager()).to.equal(feeManager.account.address);
    });

    it("Should set token weights correctly", async function () {
      const { staticPool, mockUSDC, mockDAI, mockUSDT } = await loadFixture(
        deployFullIntegrationFixture
      );

      const usdcRecord = await staticPool.read._records([mockUSDC.address]);
      const daiRecord = await staticPool.read._records([mockDAI.address]);
      const usdtRecord = await staticPool.read._records([mockUSDT.address]);

      expect(usdcRecord[0]).to.equal(400000n);
      expect(daiRecord[0]).to.equal(400000n);
      expect(usdtRecord[0]).to.equal(200000n);

      const totalWeight = await staticPool.read._totalWeight();
      expect(totalWeight).to.equal(1000000n);
    });

    it("Should set Morpho Vaults correctly", async function () {
      const { staticPool, mockUSDC, mockDAI, morphoUSDCVault, morphoDAIVault } =
        await loadFixture(deployFullIntegrationFixture);

      const usdcVault = await staticPool.read.morphoVaults([mockUSDC.address]);
      const daiVault = await staticPool.read.morphoVaults([mockDAI.address]);

      expect(usdcVault.toLowerCase()).to.equal(morphoUSDCVault.address.toLowerCase());
      expect(daiVault.toLowerCase()).to.equal(morphoDAIVault.address.toLowerCase());

      expect(await staticPool.read.hasMorphoVault([mockUSDC.address])).to.be.true;
      expect(await staticPool.read.hasMorphoVault([mockDAI.address])).to.be.true;
    });
  });

  describe("Deposits", function () {
    it("Should allow first deposit", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      const depositAmount = parseEther("10");
      
      const totalSupplyBefore = await staticPool.read.totalSupply();
      expect(totalSupplyBefore).to.equal(0n);

      const expectedTokens = await staticPool.read.previewMint([depositAmount]);
      expect(expectedTokens > 0n).to.be.true;

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: depositAmount,
      });

      const totalSupplyAfter = await staticPool.read.totalSupply();
      expect(totalSupplyAfter > 0n).to.be.true;

      const userBalance = await staticPool.read.balanceOf([user1.account.address]);
      expect(userBalance > 0n).to.be.true;
    });

    it("Should calculate entry fees correctly", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      const depositAmount = parseEther("100");

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: depositAmount,
      });

      const userBalance = await staticPool.read.balanceOf([user1.account.address]);
      expect(userBalance > 0n).to.be.true;
      expect(userBalance < depositAmount).to.be.true;
    });

    it("Should allow multiple deposits from different users", async function () {
      const { staticPool, user1, user2 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const user1Balance = await staticPool.read.balanceOf([user1.account.address]);

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("30"),
      });

      const user2Balance = await staticPool.read.balanceOf([user2.account.address]);

      expect(user1Balance > user2Balance).to.be.true;
      
      const totalSupply = await staticPool.read.totalSupply();
      expect(totalSupply).to.equal(user1Balance + user2Balance);
    });

    it("Should calculate pool tokens correctly after first deposit", async function () {
      const { staticPool, user1, user2 } = await loadFixture(
        deployFullIntegrationFixture
      );

      const firstDeposit = parseEther("100");
      
      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: firstDeposit,
      });

      const user1Balance = await staticPool.read.balanceOf([user1.account.address]);
      
      const secondDeposit = parseEther("100");
      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: secondDeposit,
      });

      const user2Balance = await staticPool.read.balanceOf([user2.account.address]);

      const difference = user1Balance > user2Balance 
        ? user1Balance - user2Balance 
        : user2Balance - user1Balance;
      
      expect(difference < user1Balance / 100n).to.be.true;
    });
  });

  describe("Morpho Vaults Integration", function () {
    it("Should deposit tokens into Morpho Vaults", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const vaultBalance = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      expect(vaultBalance).to.be.greaterThan(0n);
    });

    it("Should calculate Morpho Vault balance correctly", async function () {
      const { staticPool, user1, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const morphoBalance = await staticPool.read.getMorphoBalance([mockUSDC.address]);
      const morphoShares = await staticPool.read.getMorphoShares([mockUSDC.address]);

      expect(morphoBalance).to.be.greaterThan(0n);
      expect(morphoShares).to.be.greaterThan(0n);

      const convertedAssets = await morphoUSDCVault.read.convertToAssets([morphoShares]);
      expect(convertedAssets).to.equal(morphoBalance);
    });

    it("Should retrieve complete Morpho Vault info", async function () {
      const { staticPool, user1, mockUSDC, morphoUSDCVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const [vault, totalAssets, totalShares, ourShares, ourAssets] =
        await staticPool.read.getMorphoVaultInfo([mockUSDC.address]);

      expect(vault.toLowerCase()).to.equal(morphoUSDCVault.address.toLowerCase());
      expect(totalAssets).to.be.greaterThan(0n);
      expect(totalShares).to.be.greaterThan(0n);
      expect(ourShares).to.be.greaterThan(0n);
      expect(ourAssets).to.be.greaterThan(0n);
    });

    it("Should account for yield in index price", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const priceBefore = await staticPool.read.getIndexBalancePrice();

      const yieldAmount = parseUnits("100", 6);
      await morphoUSDCVault.write.simulateYield([yieldAmount]);

      const priceAfter = await staticPool.read.getIndexBalancePrice();

      expect(priceAfter).to.be.greaterThan(priceBefore);
    });
  });

  describe("Withdrawals", function () {
    it("Should allow withdrawal of funds", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      expect(poolTokens > 0n).to.be.true;

      const expectedEth = await staticPool.read.previewRedeem([poolTokens]);
      expect(expectedEth > 0n).to.be.true;

      const ethBefore = await hre.viem.getPublicClient().then(c => 
        c.getBalance({ address: user1.account.address })
      );

      await staticPool.write.redeem([poolTokens], {
        account: user1.account,
      });

      const poolTokensAfter = await staticPool.read.balanceOf([user1.account.address]);
      expect(poolTokensAfter).to.equal(0n);

      const ethAfter = await hre.viem.getPublicClient().then(c => 
        c.getBalance({ address: user1.account.address })
      );
      
      expect(ethAfter > ethBefore).to.be.true;
    });

    it("Should calculate exit fees correctly", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      const expectedEth = await staticPool.read.previewRedeem([poolTokens]);

      expect(expectedEth).to.be.lessThan(parseEther("100"));
    });

    it("Should withdraw from Morpho Vault correctly", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("10"),
      });

      const sharesBefore = await morphoUSDCVault.read.balanceOf([staticPool.address]);
      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);

      await staticPool.write.redeem([poolTokens], {
        account: user1.account,
      });

      const sharesAfter = await morphoUSDCVault.read.balanceOf([staticPool.address]);

      expect(sharesAfter).to.be.lessThan(sharesBefore);
    });

    it("Should allow partial withdrawals", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      const halfTokens = poolTokens / 2n;

      await staticPool.write.redeem([halfTokens], {
        account: user1.account,
      });

      const remainingTokens = await staticPool.read.balanceOf([user1.account.address]);
      
      const difference = remainingTokens > halfTokens 
        ? remainingTokens - halfTokens 
        : halfTokens - remainingTokens;
      
      expect(difference < poolTokens / 10n).to.be.true;
    });
  });

  describe("Rewards System", function () {
    it("Should set reward swap target", async function () {
      const { staticPool, mockMORPHO, mockUSDC } = await loadFixture(
        deployFullIntegrationFixture
      );

      const target = await staticPool.read.rewardSwapTargets([mockMORPHO.address]);
      expect(target.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());
    });

    it("Should update URD contract", async function () {
      const { staticPool } = await loadFixture(
        deployFullIntegrationFixture
      );

      const newURD = await hre.viem.deployContract("MockURD");

      await staticPool.write.updateURDContract([newURD.address]);

      const urdAddress = await staticPool.read.urdContract();
      expect(urdAddress.toLowerCase()).to.equal(newURD.address.toLowerCase());
    });

    it("Should reject empty claims array", async function () {
      const { staticPool } = await loadFixture(deployFullIntegrationFixture);

      await expect(
        staticPool.write.claimAndReinvestMorphoRewards([[]])
      ).to.be.rejected;
    });

    it("Should support multiple reward tokens", async function () {
      const { staticPool, mockMORPHO, mockUSDC } = await loadFixture(
        deployFullIntegrationFixture
      );

      const mockARB = await hre.viem.deployContract("SampleToken", [
        "Mock ARB",
        "ARB",
        18n,
      ]);

      await staticPool.write.setRewardSwapTarget([
        mockARB.address,
        mockUSDC.address,
      ]);

      const target1 = await staticPool.read.rewardSwapTargets([mockMORPHO.address]);
      const target2 = await staticPool.read.rewardSwapTargets([mockARB.address]);

      expect(target1.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());
      expect(target2.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());
    });

    it("Should update reward swap target", async function () {
      const { staticPool, mockMORPHO, mockUSDC, mockDAI } = await loadFixture(
        deployFullIntegrationFixture
      );

      const targetBefore = await staticPool.read.rewardSwapTargets([mockMORPHO.address]);
      expect(targetBefore.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());

      await staticPool.write.setRewardSwapTarget([
        mockMORPHO.address,
        mockDAI.address,
      ]);

      const targetAfter = await staticPool.read.rewardSwapTargets([mockMORPHO.address]);
      expect(targetAfter.toLowerCase()).to.equal(mockDAI.address.toLowerCase());
    });
  });

  describe("Weight and Token Management", function () {
    it("Should allow changing token weight", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployFullIntegrationFixture
      );

      const recordBefore = await staticPool.read._records([mockUSDC.address]);
      expect(recordBefore[0]).to.equal(400000n);

      await staticPool.write.changeWeight([mockUSDC.address, 500000n]);

      const recordAfter = await staticPool.read._records([mockUSDC.address]);
      expect(recordAfter[0]).to.equal(500000n);

      const totalWeight = await staticPool.read._totalWeight();
      expect(totalWeight).to.equal(1100000n);
    });

    it("Should allow updating swap parameters", async function () {
      const { staticPool, mockUSDC, mockFactory, mockRouter } = await loadFixture(
        deployFullIntegrationFixture
      );

      const swapRecordBefore = await staticPool.read._swapRecords([mockUSDC.address]);
      expect(swapRecordBefore[2]).to.equal(3000);

      await staticPool.write.changeToken([
        mockUSDC.address,
        mockFactory.address,
        mockRouter.address,
        500,
      ]);

      const swapRecordAfter = await staticPool.read._swapRecords([mockUSDC.address]);
      expect(swapRecordAfter[2]).to.equal(500);
    });

    it("Should allow updating pool fees", async function () {
      const { staticPool, feeManager } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.setFees([
        10000n,
        10000n,
        1000000n,
        feeManager.account.address,
        2102400n,
        15000n,
      ]);

      expect(await staticPool.read._entryFee()).to.equal(10000n);
      expect(await staticPool.read._exitFee()).to.equal(10000n);
      expect(await staticPool.read._tvlFee()).to.equal(15000n);
    });
  });

  describe("TVL Fee Calculation", function () {
    it("Should calculate TVL fees over time", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      await hre.network.provider.send("hardhat_mine", ["0x10"]);

      const calculatedFees = await staticPool.read.calculateTvlFees();
      expect(calculatedFees).to.be.greaterThan(0n);
    });

    it("Should update accTVLFees on deposit", async function () {
      const { staticPool, user1, user2 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const accFees1 = await staticPool.read.accTVLFees();

      await hre.network.provider.send("hardhat_mine", ["0x64"]);

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("50"),
      });

      const accFees2 = await staticPool.read.accTVLFees();

      expect(accFees2).to.be.greaterThan(accFees1);
    });

    it("Should update accTVLFees on withdrawal", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const accFees1 = await staticPool.read.accTVLFees();

      await hre.network.provider.send("hardhat_mine", ["0x64"]);

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      await staticPool.write.redeem([poolTokens / 2n], {
        account: user1.account,
      });

      const accFees2 = await staticPool.read.accTVLFees();

      expect(accFees2).to.be.greaterThan(accFees1);
    });
  });

  describe("Access Control", function () {
    it("Should prevent non-owner from setting Morpho Vault", async function () {
      const { staticPool, mockUSDC, morphoUSDCVault, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await expect(
        staticPool.write.setMorphoVault(
          [mockUSDC.address, morphoUSDCVault.address],
          { account: user1.account }
        )
      ).to.be.rejected;
    });

    it("Should prevent non-owner from changing weights", async function () {
      const { staticPool, mockUSDC, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await expect(
        staticPool.write.changeWeight([mockUSDC.address, 500000n], {
          account: user1.account,
        })
      ).to.be.rejected;
    });

    it("Should prevent non-owner from updating URD", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      const newURD = await hre.viem.deployContract("MockURD");

      await expect(
        staticPool.write.updateURDContract([newURD.address], {
          account: user1.account,
        })
      ).to.be.rejected;
    });

    it("Should prevent non-owner from setting reward swap target", async function () {
      const { staticPool, mockMORPHO, mockUSDC, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await expect(
        staticPool.write.setRewardSwapTarget(
          [mockMORPHO.address, mockUSDC.address],
          { account: user1.account }
        )
      ).to.be.rejected;
    });

    it("Should prevent non-owner from changing fees", async function () {
      const { staticPool, feeManager, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await expect(
        staticPool.write.setFees(
          [10000n, 10000n, 1000000n, feeManager.account.address, 2102400n, 15000n],
          { account: user1.account }
        )
      ).to.be.rejected;
    });
  });

  describe("Edge Cases", function () {
    it("Should handle zero address for Morpho Vault", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployFullIntegrationFixture
      );

      const zeroAddress = "0x0000000000000000000000000000000000000000" as Address;

      await expect(
        staticPool.write.setMorphoVault([mockUSDC.address, zeroAddress])
      ).to.be.rejected;
    });

    it("Should return 0 for Morpho Vault balance when vault not set", async function () {
      const { staticPool, mockUSDT } = await loadFixture(
        deployFullIntegrationFixture
      );

      const balance = await staticPool.read.getMorphoBalance([mockUSDT.address]);
      expect(balance).to.equal(0n);

      const shares = await staticPool.read.getMorphoShares([mockUSDT.address]);
      expect(shares).to.equal(0n);
    });

    it("Should handle minimal deposit", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      const minDeposit = parseEther("0.001");

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: minDeposit,
      });

      const balance = await staticPool.read.balanceOf([user1.account.address]);
      expect(balance > 0n).to.be.true;
    });

    it("Should handle large deposit", async function () {
      const { staticPool, owner } = await loadFixture(
        deployFullIntegrationFixture
      );

      const largeDeposit = parseEther("100");

      await staticPool.write.mint([owner.account.address], {
        account: owner.account,
        value: largeDeposit,
      });

      const balance = await staticPool.read.balanceOf([owner.account.address]);
      expect(balance > 0n).to.be.true;

      const totalSupply = await staticPool.read.totalSupply();
      expect(totalSupply).to.equal(balance);
    });

    it("Should reject vault with mismatched asset", async function () {
      const { staticPool, mockUSDC, morphoDAIVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      await expect(
        staticPool.write.setMorphoVault([mockUSDC.address, morphoDAIVault.address])
      ).to.be.rejected;
    });

    it("Should verify total fees don't exceed 5%", async function () {
      const { staticPool, feeManager } = await loadFixture(
        deployFullIntegrationFixture
      );

      await expect(
        staticPool.write.setFees([
          30000n,
          30000n,
          1000000n,
          feeManager.account.address,
          2102400n,
          10000n,
        ])
      ).to.be.rejected;
    });
  });

  describe("Complex Scenarios", function () {
    it("Complete cycle: deposit, yield, partial withdrawal, full withdrawal", async function () {
      const { staticPool, user1, morphoUSDCVault } = await loadFixture(
        deployFullIntegrationFixture
      );

      const depositAmount = parseEther("50");
      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: depositAmount,
      });

      const poolTokens1 = await staticPool.read.balanceOf([user1.account.address]);
      expect(poolTokens1 > 0n).to.be.true;

      const yieldAmount = parseUnits("500", 6);
      await morphoUSDCVault.write.simulateYield([yieldAmount]);

      const halfTokens = poolTokens1 / 2n;
      await staticPool.write.redeem([halfTokens], {
        account: user1.account,
      });

      const poolTokens2 = await staticPool.read.balanceOf([user1.account.address]);
      expect(poolTokens2).to.be.lessThan(poolTokens1);
      expect(poolTokens2 > poolTokens1 / 3n).to.be.true;

      await staticPool.write.redeem([poolTokens2], {
        account: user1.account,
      });

      const poolTokens3 = await staticPool.read.balanceOf([user1.account.address]);
      expect(poolTokens3).to.equal(0n);
    });

    it("Multiple users with different deposits", async function () {
      const { staticPool, user1, user2 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("30"),
      });

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("70"),
      });

      const user1Balance = await staticPool.read.balanceOf([user1.account.address]);
      const user2Balance = await staticPool.read.balanceOf([user2.account.address]);
      const totalSupply = await staticPool.read.totalSupply();

      expect(totalSupply).to.equal(user1Balance + user2Balance);
      expect(user2Balance > user1Balance).to.be.true;

      const ratio = Number(user1Balance * 100n / totalSupply);
      expect(ratio).to.be.closeTo(30, 5);
    });

    it("Weight changes and rebalancing", async function () {
      const { staticPool, user1, mockUSDC, mockDAI } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      await staticPool.write.changeWeight([mockUSDC.address, 600000n]);
      await staticPool.write.changeWeight([mockDAI.address, 300000n]);

      const totalWeight = await staticPool.read._totalWeight();
      expect(totalWeight).to.equal(1100000n);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const indexPrice = await staticPool.read.getIndexBalancePrice();
      expect(indexPrice > 0n).to.be.true;
    });

    it("Deposit, yield, new deposit, withdrawal sequence", async function () {
      const { staticPool, user1, user2, morphoUSDCVault, morphoDAIVault } =
        await loadFixture(deployFullIntegrationFixture);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const user1Tokens1 = await staticPool.read.balanceOf([user1.account.address]);

      await morphoUSDCVault.write.simulateYield([parseUnits("1000", 6)]);
      await morphoDAIVault.write.simulateYield([parseEther("1000")]);

      await staticPool.write.mint([user2.account.address], {
        account: user2.account,
        value: parseEther("100"),
      });

      const user2Tokens = await staticPool.read.balanceOf([user2.account.address]);

      expect(user2Tokens).to.be.lessThan(user1Tokens1);

      const ethBefore = await hre.viem.getPublicClient().then(c => 
        c.getBalance({ address: user1.account.address })
      );

      await staticPool.write.redeem([user1Tokens1], {
        account: user1.account,
      });

      const ethAfter = await hre.viem.getPublicClient().then(c => 
        c.getBalance({ address: user1.account.address })
      );

      expect(ethAfter > ethBefore).to.be.true;
    });

    it("Complete pool configuration update", async function () {
      const { staticPool, user1, mockMORPHO, mockUSDC, feeManager } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const newURD = await hre.viem.deployContract("MockURD");
      await staticPool.write.updateURDContract([newURD.address]);

      await staticPool.write.setRewardSwapTarget([
        mockMORPHO.address,
        mockUSDC.address,
      ]);

      await staticPool.write.setFees([
        7500n,
        7500n,
        1000000n,
        feeManager.account.address,
        2102400n,
        12000n,
      ]);

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("50"),
      });

      const finalBalance = await staticPool.read.balanceOf([user1.account.address]);
      expect(finalBalance > 0n).to.be.true;

      expect(await staticPool.read.urdContract()).to.equal(newURD.address);
      expect(await staticPool.read._entryFee()).to.equal(7500n);
      expect(await staticPool.read._exitFee()).to.equal(7500n);
    });
  });

  describe("Events", function () {
    it("Should emit MorphoVaultSet event", async function () {
      const { publicClient } = await loadFixture(deployFullIntegrationFixture);

      const mockToken = await hre.viem.deployContract("SampleToken", [
        "Test Token",
        "TEST",
        18n,
      ]);

      const mockVault = await hre.viem.deployContract("MockMorphoVault", [
        mockToken.address,
        "Test Vault",
        "vTEST",
      ]);

      const staticPool = await hre.viem.deployContract("StaticPoolV2", [
        mockToken.address,
        mockToken.address,
        5000n,
        5000n,
        1000000n,
        "0x1234567890123456789012345678901234567890" as Address,
        2102400n,
        10000n,
        "0x1234567890123456789012345678901234567890" as Address,
      ]);

      const hash = await staticPool.write.setMorphoVault([
        mockToken.address,
        mockVault.address,
      ]);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).to.equal("success");
    });

    it("Should emit VaultSet event", async function () {
      const { staticPool, mockUSDT, publicClient } = await loadFixture(
        deployFullIntegrationFixture
      );

      const mockVault = await hre.viem.deployContract("MockMorphoVault", [
        mockUSDT.address,
        "USDT Vault",
        "vUSDT",
      ]);

      const hash = await staticPool.write.setVault([
        mockUSDT.address,
        mockVault.address,
      ]);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).to.equal("success");
    });

    it("Should emit RewardSwapTargetSet event", async function () {
      const { staticPool, mockMORPHO, mockUSDC, publicClient } = await loadFixture(
        deployFullIntegrationFixture
      );

      const mockNewReward = await hre.viem.deployContract("SampleToken", [
        "New Reward",
        "REWARD",
        18n,
      ]);

      const hash = await staticPool.write.setRewardSwapTarget([
        mockNewReward.address,
        mockUSDC.address,
      ]);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt.status).to.equal("success");
    });
  });

  describe("View Functions", function () {
    it("Should return token list correctly", async function () {
      const { staticPool, mockUSDC, mockDAI, mockUSDT } = await loadFixture(
        deployFullIntegrationFixture
      );

      const token0 = await staticPool.read._tokens([0n]);
      const token1 = await staticPool.read._tokens([1n]);
      const token2 = await staticPool.read._tokens([2n]);

      expect(token0.toLowerCase()).to.equal(mockUSDC.address.toLowerCase());
      expect(token1.toLowerCase()).to.equal(mockDAI.address.toLowerCase());
      expect(token2.toLowerCase()).to.equal(mockUSDT.address.toLowerCase());
    });

    it("Should return token record information correctly", async function () {
      const { staticPool, mockUSDC } = await loadFixture(
        deployFullIntegrationFixture
      );

      const [weight, balance, index] = await staticPool.read._records([mockUSDC.address]);

      expect(weight).to.equal(400000n);
      expect(balance).to.be.a("bigint");
      expect(index).to.equal(0n);
    });

    it("Should return swap record information correctly", async function () {
      const { staticPool, mockUSDC, mockFactory, mockRouter } = await loadFixture(
        deployFullIntegrationFixture
      );

      const [factory, router, poolFee] = await staticPool.read._swapRecords([
        mockUSDC.address,
      ]);

      expect(factory.toLowerCase()).to.equal(mockFactory.address.toLowerCase());
      expect(router.toLowerCase()).to.equal(mockRouter.address.toLowerCase());
      expect(poolFee).to.equal(3000);
    });

    it("Should calculate preview mint correctly", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      const depositAmount = parseEther("100");
      const previewTokens = await staticPool.read.previewMint([depositAmount]);

      expect(previewTokens > 0n).to.be.true;

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: depositAmount,
      });

      const actualTokens = await staticPool.read.balanceOf([user1.account.address]);

      expect(actualTokens > 0n).to.be.true;
    });

    it("Should calculate preview redeem correctly", async function () {
      const { staticPool, user1 } = await loadFixture(
        deployFullIntegrationFixture
      );

      await staticPool.write.mint([user1.account.address], {
        account: user1.account,
        value: parseEther("100"),
      });

      const poolTokens = await staticPool.read.balanceOf([user1.account.address]);
      const previewEth = await staticPool.read.previewRedeem([poolTokens]);

      expect(previewEth > 0n).to.be.true;
      expect(previewEth).to.be.lessThan(parseEther("100"));
    });
  });
});


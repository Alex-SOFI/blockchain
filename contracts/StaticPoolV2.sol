// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./BaseStaticPool.sol";
import "./MorphoVaultManager.sol";
import "./modules/RewardsManager.sol";
import "./libraries/SwapHelpers.sol";
import "./libraries/FeeCalculator.sol";
import "./interfaces/IMorpho.sol";

contract StaticPoolV2 is BaseStaticPool, MorphoVaultManager, RewardsManager {
    using SafeERC20 for IERC20;
    using SwapHelpers for *;
    using FeeCalculator for *;

    mapping(address => address) public tokenVaults;

    event VaultSet(address indexed token, address indexed vault);
    event CompoundFailed(address indexed token, address indexed vault, string reason);

    error ZeroVault();
    error ApprovalFailed();
    error EmptyClaims();

    constructor(
        address ENTRY,
        address WETH,
        uint entryFee,
        uint exitFee,
        uint baseFee,
        address feeManager,
        uint blocksPerYear,
        uint tvlFee,
        address urdContract
    ) 
        BaseStaticPool(ENTRY, WETH, entryFee, exitFee, baseFee, feeManager, blocksPerYear, tvlFee)
        MorphoVaultManager(urdContract)
    {}

    /**
     * @notice Sets Morpho vault for a token
     * @param token Token address
     * @param vault Morpho vault address
     */
    function setMorphoVault(address token, address vault) external onlyOwner {
        _setMorphoVault(token, vault);
    }

    /**
     * @notice Sets regular ERC4626 vault
     * @param token Token address  
     * @param vault Vault address
     */
    function setVault(address token, address vault) external onlyOwner {
        if (vault == address(0)) revert ZeroVault();
        
        bool success = IERC20(token).approve(vault, type(uint256).max);
        if (!success) revert ApprovalFailed();
        
        tokenVaults[token] = vault;
        emit VaultSet(token, vault);
    }

    /**
     * @notice Sets reward swap target
     * @param rewardToken Reward token
     * @param targetToken Target token
     */
    function setRewardSwapTarget(address rewardToken, address targetToken) public onlyOwner {
        _setRewardSwapTarget(rewardToken, targetToken);
    }

    /**
     * @notice Updates URD contract
     * @param _urdContract New URD address
     */
    function updateURDContract(address _urdContract) external onlyOwner {
        setURDContract(_urdContract);
    }

    /**
     * @notice Previews mint amount
     * @param tokenAmountIn Amount of tokens to deposit
     * @return poolAmountOut Amount of pool tokens to receive
     */
    function previewMint(uint tokenAmountIn) public view returns (uint poolAmountOut) {
        uint amountWithoutFee = FeeCalculator.calculateNetAmount(tokenAmountIn, _entryFee);
        
        if (totalSupply() == 0) {
            return amountWithoutFee;
        }
        
        uint indexPrice = getIndexBalancePrice();
        if (indexPrice == 0) {
            return amountWithoutFee;
        }
        
        poolAmountOut = (amountWithoutFee * totalSupply()) / indexPrice;
    }

    /**
     * @notice Mints pool tokens by depositing ETH/WETH
     * @param receiver Address to receive pool tokens
     */
    function mint(address receiver) public payable nonReentrant {
        uint tokenAmountIn = msg.value;
        uint amountFee = FeeCalculator.calculateFee(tokenAmountIn, _entryFee);
        uint amountWithoutFee = tokenAmountIn - amountFee;
        uint amountTokenOut = previewMint(tokenAmountIn);
        
        uint[] memory balancesTokens = new uint[](_tokens.length);

        if (msg.value > 0) {
            IWETH9(_WETH).deposit{value: msg.value}();
        } else {
            IERC20(_ENTRY).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
        }

        IERC20(_ENTRY).safeTransfer(_feeManager, amountFee);

        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint weight = _records[token].weight;

            if (weight != 0) {
                uint tokenBalanceBefore = _getTokenBalance(token);
                uint amountToSwap = SwapHelpers.calculateSwapAmount(
                    amountWithoutFee,
                    weight,
                    _totalWeight
                );

                SwapHelpers.SwapParams memory params = SwapHelpers.SwapParams({
                    router: _swapRecords[token].router,
                    tokenIn: _ENTRY,
                    tokenOut: token,
                    fee: _swapRecords[token].poolFee,
                    amountIn: amountToSwap,
                    recipient: address(this)
                });

                SwapHelpers.executeSwap(params);
                
                uint swappedAmount = IERC20(token).balanceOf(address(this));
                _depositToVault(token, swappedAmount);
                
                uint tokenBalanceAfter = _getTokenBalance(token);
                balancesTokens[i] = tokenBalanceAfter - tokenBalanceBefore;
            } else {
                balancesTokens[i] = 0;
            }
        }

        joinPool(amountTokenOut, balancesTokens, receiver);
    }

    /**
     * @notice Previews redeem amount
     * @param tokenAmountIn Amount of pool tokens to redeem
     * @return amountOut Amount of ETH to receive
     */
    function previewRedeem(uint tokenAmountIn) public view returns (uint amountOut) {
        uint amountWithoutFee = FeeCalculator.calculateNetAmount(tokenAmountIn, _exitFee);
        uint indexPrice = getIndexBalancePrice();
        
        if (totalSupply() == 0) {
            return 0;
        }
        
        amountOut = (amountWithoutFee * indexPrice) / totalSupply();
    }

    /**
     * @notice Redeems pool tokens for ETH
     * @param tokenAmountIn Amount of pool tokens to redeem
     */
    function redeem(uint tokenAmountIn) public nonReentrant {
        uint amountFee = FeeCalculator.calculateFee(tokenAmountIn, _exitFee);
        uint amountWithoutFee = tokenAmountIn - amountFee;
        uint balanceBefore = IERC20(_ENTRY).balanceOf(address(this));

        uint[] memory balancesTokens = new uint[](_tokens.length);
        
        for (uint i = 0; i < _tokens.length; ++i) {
            address token = _tokens[i];
            uint24 poolFee = _swapRecords[token].poolFee;
            
            uint bBalance = SwapHelpers.normalizeAmount(
                _records[token].balance,
                IERC20Metadata(token).decimals()
            );
            
            uint amountTokenInForSwap = (amountWithoutFee * bBalance) / totalSupply();
            
            _withdrawFromVault(token, amountTokenInForSwap);

            uint denormalizedAmount = SwapHelpers.denormalizeAmount(
                amountTokenInForSwap,
                IERC20Metadata(token).decimals()
            );
            
            if (amountTokenInForSwap > 0) {
                SwapHelpers.SwapParams memory params = SwapHelpers.SwapParams({
                    router: _swapRecords[token].router,
                    tokenIn: token,
                    tokenOut: _ENTRY,
                    fee: poolFee,
                    amountIn: denormalizedAmount,
                    recipient: msg.sender
                });

                SwapHelpers.executeSwap(params);
                balancesTokens[i] = denormalizedAmount;
            } else {
                balancesTokens[i] = 0;
            }
        }

        uint balanceAfter = IERC20(_ENTRY).balanceOf(address(this));
        uint diffBalances = balanceAfter - balanceBefore;
        
        IWETH9(_WETH).withdraw(diffBalances);
        (bool success, ) = msg.sender.call{value: diffBalances}("");
        require(success, "ETH transfer failed");

        exitPool(tokenAmountIn, balancesTokens);
    }

    /**
     * @notice Gets total index balance price
     * @return amountOut Total value in ENTRY token
     */
    function getIndexBalancePrice() public view returns(uint amountOut) {
        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint tokenBalance = _getTokenBalance(token);

            if (tokenBalance > 0) {
                address factory = _swapRecords[token].factory;
                uint24 poolFee = _swapRecords[token].poolFee;
                
                address pool = IUniswapV3Factory(factory).getPool(
                    address(_ENTRY),
                    token,
                    poolFee
                );
                amountOut += getAmountOut(pool, token, tokenBalance);
            }
        }
    }

    /**
     * @notice Claims and reinvests Morpho rewards
     * @param claims Array of claim data
     * @return claimedAmounts Amounts claimed
     */
    function claimAndReinvestMorphoRewards(
        ClaimData[] memory claims
    ) external nonReentrant returns (uint256[] memory claimedAmounts) {
        if (claims.length == 0) revert EmptyClaims();
        claimedAmounts = new uint256[](claims.length);

        for (uint256 i = 0; i < claims.length; i++) {
            ClaimData memory claimData = claims[i];
            
            uint256 claimed = _claimRewardsInternal(
                address(this),
                claimData.rewardToken,
                claimData.claimable,
                claimData.proof
            );
            
            if (claimed > 0) {
                address targetToken = rewardSwapTargets[claimData.rewardToken];
                if (targetToken != address(0)) {
                    _processRewardReinvestment(claimData.rewardToken, targetToken, claimed);
                }
            }
            
            claimedAmounts[i] = claimed;
        }

        return claimedAmounts;
    }

    /**
     * @notice Gets Morpho vault info
     * @param token Token address
     */
    function getMorphoVaultInfo(address token) external view returns (
        address vault,
        uint256 totalAssets,
        uint256 totalShares,
        uint256 ourShares,
        uint256 ourAssets
    ) {
        vault = morphoVaults[token];
        if (vault != address(0)) {
            IMetaMorpho morphoVault = IMetaMorpho(vault);
            totalAssets = morphoVault.totalAssets();
            totalShares = morphoVault.totalSupply();
            ourShares = morphoVault.balanceOf(address(this));
            ourAssets = getMorphoBalance(token);
        }
    }

    // ========== Internal Functions ==========

    /**
     * @notice Gets token balance (from vault or direct)
     */
    function _getTokenBalance(address token) internal view returns (uint256) {
        address morphoVault = morphoVaults[token];
        if (morphoVault != address(0)) {
            return getMorphoBalance(token);
        }
        
        address regularVault = tokenVaults[token];
        if (regularVault != address(0)) {
            uint shareBalance = IERC4626(regularVault).balanceOf(address(this));
            return IERC4626(regularVault).convertToAssets(shareBalance);
        }
        
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Deposits to vault (Morpho or regular)
     */
    function _depositToVault(address token, uint256 amount) internal {
        if (amount == 0) return;

        address morphoVault = morphoVaults[token];
        if (morphoVault != address(0)) {
            _depositToMorpho(token, amount);
            return;
        }

        address regularVault = tokenVaults[token];
        if (regularVault != address(0)) {
            IERC4626(regularVault).deposit(amount, address(this));
        }
    }

    /**
     * @notice Withdraws from vault
     */
    function _withdrawFromVault(address token, uint256 amountNeeded) internal {
        if (amountNeeded == 0) return;

        address morphoVault = morphoVaults[token];
        if (morphoVault != address(0)) {
            uint256 totalShares = getMorphoShares(token);
            uint256 totalBalance = getMorphoBalance(token);
            uint256 sharesToWithdraw = (totalShares * amountNeeded) / totalBalance;
            
            if (sharesToWithdraw > 0) {
                _withdrawFromMorpho(token, sharesToWithdraw);
            }
            return;
        }

        address regularVault = tokenVaults[token];
        if (regularVault != address(0)) {
            IERC4626 vaultContract = IERC4626(regularVault);
            uint256 totalShares = vaultContract.balanceOf(address(this));
            uint256 totalAssets = vaultContract.convertToAssets(totalShares);
            uint256 sharesToWithdraw = (totalShares * amountNeeded) / totalAssets;
            
            if (sharesToWithdraw > 0) {
                vaultContract.redeem(sharesToWithdraw, address(this), address(this));
            }
        }
    }

    /**
     * @notice Processes reward reinvestment
     */
    function _processRewardReinvestment(
        address rewardToken,
        address targetToken,
        uint256 amount
    ) internal {
        SwapRecord memory swapRecord = _swapRecords[targetToken];
        
        // Swap rewards
        uint256 swapped = _swapRewards(
            rewardToken,
            targetToken,
            amount,
            swapRecord.router,
            swapRecord.poolFee
        );
        
        // Deposit to vault
        address morphoVault = morphoVaults[targetToken];
        address regularVault = tokenVaults[targetToken];
        
        uint256 deposited = _depositRewards(
            targetToken,
            swapped,
            morphoVault,
            regularVault
        );
        
        if (deposited > 0) {
            _records[targetToken].balance = _getTokenBalance(targetToken);
        }
    }

    function _claimRewardsInternal(
        address user,
        address rewardToken,
        uint256 claimable,
        bytes32[] memory proof
    ) internal returns (uint256 amount) {
        if (urdContract == address(0)) revert("URD not set");
        if (user == address(0)) revert ZeroAddress();
        if (rewardToken == address(0)) revert ZeroAddress();
        
        amount = IUniversalRewardsDistributor(urdContract).claim(
            user,
            rewardToken,
            claimable,
            proof
        );
        
        emit RewardsClaimed(user, rewardToken, amount);
        return amount;
    }

    function exitPool(uint poolAmountIn, uint[] memory minAmountOut) private {
        uint poolTotal = totalSupply();

        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint balance = _records[token].balance;
            uint tokenAmountOut = (poolAmountIn * balance) / poolTotal;

            require(tokenAmountOut >= minAmountOut[i], "ERR_LIMIT_OUT");
            _records[token].balance = _records[token].balance - tokenAmountOut;
        }

        uint feeAmount = FeeCalculator.calculateTVLFee(
            totalSupply(),
            _tvlFee,
            block.number - _lastFeeBlock,
            _blocksPerYear
        );
        
        accTVLFees = accTVLFees + feeAmount;
        _lastFeeBlock = block.number;

        _burn(msg.sender, poolAmountIn);
    }

    function joinPool(
        uint poolAmountOut,
        uint[] memory balancesTokens,
        address receiver
    ) private {
        for (uint i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint tokenBalance = balancesTokens[i];
            _records[token].balance = _records[token].balance + tokenBalance;
        }

        uint feeAmount = FeeCalculator.calculateTVLFee(
            totalSupply(),
            _tvlFee,
            block.number - _lastFeeBlock,
            _blocksPerYear
        );
        
        accTVLFees = accTVLFees + feeAmount;
        _lastFeeBlock = block.number;

        _mint(receiver, poolAmountOut);
    }

    /// @notice Structure for claiming rewards data
    struct ClaimData {
        address rewardToken;
        uint256 claimable;
        bytes32[] proof;
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../interfaces/IMorpho.sol";

abstract contract RewardsManager {
    using SafeERC20 for IERC20;

    mapping(address => address) public rewardSwapTargets;

    event RewardSwapTargetSet(address indexed rewardToken, address indexed targetToken);

    error ZeroAddress();
    error InvalidTarget();

    /**
     * @notice Sets target token for reward swapping
     * @param rewardToken Reward token address
     * @param targetToken Target token address
     */
    function _setRewardSwapTarget(
        address rewardToken,
        address targetToken
    ) internal virtual {
        if (rewardToken == address(0)) revert ZeroAddress();
        if (targetToken == address(0)) revert ZeroAddress();
        
        rewardSwapTargets[rewardToken] = targetToken;
        emit RewardSwapTargetSet(rewardToken, targetToken);
    }

    /**
     * @notice Internal function to swap and reinvest rewards
     * @param rewardToken Reward token to swap
     * @param targetToken Target token to receive
     * @param amount Amount to swap
     * @param swapRouter Router address for swap
     * @param fee Pool fee
     * @return swappedAmount Amount of target tokens received
     */
    function _swapRewards(
        address rewardToken,
        address targetToken,
        uint256 amount,
        address swapRouter,
        uint24 fee
    ) internal virtual returns (uint256 swappedAmount) {
        if (amount == 0) return 0;

        IERC20(rewardToken).safeIncreaseAllowance(swapRouter, amount);

        bytes memory swapData = abi.encodeWithSignature(
            "exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))",
            rewardToken,
            targetToken,
            fee,
            address(this),
            amount,
            0, // amountOutMinimum
            0  // sqrtPriceLimitX96
        );

        (bool success, bytes memory result) = swapRouter.call(swapData);
        require(success, "Swap failed");

        swappedAmount = abi.decode(result, (uint256));
    }

    /**
     * @notice Deposits swapped rewards into vault
     * @param token Token to deposit
     * @param amount Amount to deposit
     * @param morphoVault Morpho vault address (if available)
     * @param regularVault Regular vault address (fallback)
     * @return deposited Amount deposited
     */
    function _depositRewards(
        address token,
        uint256 amount,
        address morphoVault,
        address regularVault
    ) internal virtual returns (uint256 deposited) {
        if (amount == 0) return 0;

        if (morphoVault != address(0)) {
            IERC20(token).safeIncreaseAllowance(morphoVault, amount);
            IERC4626(morphoVault).deposit(amount, address(this));
            deposited = amount;
        } else if (regularVault != address(0)) {
            uint256 allowance = IERC20(token).allowance(address(this), regularVault);
            if (allowance < amount) {
                IERC20(token).approve(regularVault, type(uint256).max);
            }
            
            IERC4626(regularVault).deposit(amount, address(this));
            deposited = amount;
        }
    }

    /**
     * @notice Gets reward swap target for a reward token
     * @param rewardToken Reward token address
     * @return target Target token address
     */
    function getRewardSwapTarget(address rewardToken) external view returns (address target) {
        return rewardSwapTargets[rewardToken];
    }
}


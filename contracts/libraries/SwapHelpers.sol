// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library SwapHelpers {
    using SafeERC20 for IERC20;

    error ZeroAmount();
    error ZeroAddress();

    struct SwapParams {
        address router;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        address recipient;
    }

    /**
     * @notice Executes a Uniswap V3 swap
     * @param params Swap parameters
     * @return amountOut Amount of tokens received
     */
    function executeSwap(SwapParams memory params) internal returns (uint256 amountOut) {
        if (params.amountIn == 0) revert ZeroAmount();
        if (params.router == address(0)) revert ZeroAddress();

        IERC20(params.tokenIn).safeIncreaseAllowance(params.router, params.amountIn);

        bytes memory data = abi.encodeWithSignature(
            "exactInputSingle((address,address,uint24,address,uint256,uint256,uint160))",
            params.tokenIn,
            params.tokenOut,
            params.fee,
            params.recipient,
            params.amountIn,
            0, // amountOutMinimum
            0  // sqrtPriceLimitX96
        );

        (bool success, bytes memory result) = params.router.call(data);
        require(success, "Swap failed");

        amountOut = abi.decode(result, (uint256));
    }

    /**
     * @notice Calculates token amount for swap based on weight
     * @param totalAmount Total amount to distribute
     * @param weight Token weight
     * @param totalWeight Sum of all weights
     * @return amount Amount for this token
     */
    function calculateSwapAmount(
        uint256 totalAmount,
        uint256 weight,
        uint256 totalWeight
    ) internal pure returns (uint256) {
        if (totalWeight == 0) revert ZeroAmount();
        return (totalAmount * weight) / totalWeight;
    }

    /**
     * @notice Normalizes token amount to 18 decimals
     * @param amount Original amount
     * @param decimals Token decimals
     * @return normalized Normalized amount
     */
    function normalizeAmount(
        uint256 amount,
        uint256 decimals
    ) internal pure returns (uint256 normalized) {
        uint256 standardDecimals = 18;
        
        if (decimals < standardDecimals) {
            normalized = amount * (10 ** (standardDecimals - decimals));
        } else {
            normalized = amount;
        }
    }

    /**
     * @notice Denormalizes amount from 18 decimals
     * @param amount Normalized amount
     * @param decimals Target decimals
     * @return denormalized Denormalized amount
     */
    function denormalizeAmount(
        uint256 amount,
        uint256 decimals
    ) internal pure returns (uint256 denormalized) {
        uint256 standardDecimals = 18;
        
        if (decimals < standardDecimals) {
            denormalized = amount / (10 ** (standardDecimals - decimals));
        } else {
            denormalized = amount;
        }
    }
}


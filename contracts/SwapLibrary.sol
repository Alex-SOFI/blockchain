// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ISwapOdosRouter.sol";

library SwapLibrary {
    using SafeERC20 for IERC20;

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint amountIn;
        uint amountOutMinimum;
        address recipient;
    }

    function performUniswapV3Swap(
        ISwapRouter router,
        SwapParams memory params
    ) internal returns (uint amountOut) {
        IERC20(params.tokenIn).safeIncreaseAllowance(address(router), params.amountIn);

        ISwapRouter.ExactInputSingleParams memory routerParams = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                fee: params.fee,
                recipient: params.recipient,
                deadline: block.timestamp,
                amountIn: params.amountIn,
                amountOutMinimum: params.amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        amountOut = router.exactInputSingle(routerParams);
    }

    function performOdosSwap(
        ISwapOdosRouter router,
        SwapParams memory params,
        address executor,
        bytes memory pathDefinition
    ) internal returns (uint amountOut) {
        IERC20(params.tokenIn).safeIncreaseAllowance(address(router), params.amountIn);

        ISwapOdosRouter.swapTokenInfo memory tokenInfo = ISwapOdosRouter.swapTokenInfo({
            inputToken: params.tokenIn,
            inputAmount: params.amountIn,
            inputReceiver: address(this),
            outputToken: params.tokenOut,
            outputQuote: 0,
            outputMin: params.amountOutMinimum,
            outputReceiver: params.recipient
        });

        amountOut = router.swap(tokenInfo, pathDefinition, executor, 0);
    }

    function getAmountOut(
        address pool,
        address tokenIn,
        uint amountIn
    ) internal view returns (uint amountOut) {
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        uint priceX96 = uint(sqrtPriceX96) * uint(sqrtPriceX96);
        address token0 = IUniswapV3Pool(pool).token0();
        uint8 token0Decimals = IERC20Metadata(token0).decimals();
        uint decimalsNumerator = 10**token0Decimals;
        uint price = (priceX96 * decimalsNumerator) / (1 << 192);

        if (token0 == tokenIn) {
            amountOut = (amountIn * price) / decimalsNumerator;
        } else {
            amountOut = (amountIn * 10**18) / price;
        }
    }
}
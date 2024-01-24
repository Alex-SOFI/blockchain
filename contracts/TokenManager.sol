// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

interface ISofiToken {
  function mint(address _to, uint _amount) external;
  function burn(address _to, uint _amount) external;
}

contract TokenManager is Ownable {
  using Math for uint;
  ISofiToken private token;
  IERC20 private usdcToken;

  ISwapRouter public immutable swapRouter;
  IUniswapV3Factory public immutable swapFactory;

  address public constant SWAP_TOKEN = 0xfF9b1273f5722C16C4f0b9E9a5aeA83006FE6152;
  uint24 public constant poolFee = 3000;
  uint public entryFee = 5000;
  uint public baseFee = 1000000;

  constructor(IERC20 _usdcToken, ISwapRouter _swapRouter, IUniswapV3Factory _swapFactory) Ownable(msg.sender) {
    usdcToken = _usdcToken;
    swapRouter = _swapRouter;
    swapFactory = _swapFactory;
  }

  function mint(uint _amountIn, uint24 _poolFee) public {
    TransferHelper.safeTransferFrom(address(usdcToken), msg.sender, address(this), _amountIn);
    TransferHelper.safeApprove(address(usdcToken), address(swapRouter), _amountIn);
    address pool = swapFactory.getPool(
      address(usdcToken),
      address(SWAP_TOKEN),
      _poolFee
    );
    TransferHelper.safeApprove(address(usdcToken), pool, _amountIn);

    ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: SWAP_TOKEN,
                fee: _poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

    uint256 amountOut = swapRouter.exactInputSingle(params);
    
    token.mint(msg.sender, amountOut);
  }

  function redeem(uint _amountIn, uint24 _poolFee) public {
    TransferHelper.safeTransferFrom(address(token), msg.sender, address(this), _amountIn);
    TransferHelper.safeApprove(address(token), address(swapRouter), _amountIn);
    address pool = swapFactory.getPool(
      address(usdcToken),
      address(SWAP_TOKEN),
      _poolFee
    );
    TransferHelper.safeApprove(address(SWAP_TOKEN), pool, _amountIn);
    uint balanceSwapToken = IERC20(SWAP_TOKEN).balanceOf(address(this));

    ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: SWAP_TOKEN,
                tokenOut: address(usdcToken),
                fee: _poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

    uint256 amountOut = swapRouter.exactInputSingle(params);
    
    token.burn(msg.sender, _amountIn);
  }

  function setToken(address _token) public onlyOwner {
    token = ISofiToken(_token);
  }

  function estimateMint(uint _amount, uint24 _poolFee) view public returns(uint) {
    address pool = swapFactory.getPool(
      address(usdcToken),
      address(SWAP_TOKEN),
      _poolFee
    );
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    (, uint priceX96) = Math.tryMul(uint(sqrtPriceX96), uint(sqrtPriceX96));
    (, uint unshiftedPrice) = Math.tryMul(priceX96, 1e18);
    uint price = unshiftedPrice >> (96 * 2);
    uint amountWithoutFee = Math.mulDiv(_amount, entryFee, baseFee);
    uint outputSwaptoken = Math.mulDiv(amountWithoutFee, price, 1e18*2);
    uint balanceSwapToken = IERC20(SWAP_TOKEN).balanceOf(address(this));
    uint balanceToken = IERC20(token).balanceOf(address(this));
    uint outputTokenAmount = Math.mulDiv(balanceToken, outputSwaptoken, balanceSwapToken);
    return outputTokenAmount;
  }

  function estimateRedeem(uint _amount) pure public returns(uint) {
    return _amount;
  }
}
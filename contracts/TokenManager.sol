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
  function totalSupply() view external returns(uint);
}

contract TokenManager is Ownable {
  using Math for uint;
  uint256 constant MAX_INT = 2**256 - 1;

  ISofiToken private sofiToken;
  IERC20 private usdcToken;

  ISwapRouter public immutable swapRouter;
  IUniswapV3Factory public immutable swapFactory;

  address public constant SWAP_TOKEN = 0xfF9b1273f5722C16C4f0b9E9a5aeA83006FE6152;
  uint24 public constant poolFee = 3000;
  uint public entryFee = 5000;
  uint public baseFee = 1000000;

  struct TokenOptions {
    address factory;
    address router;
    address token;
    uint24 poolFee;
    uint share; // 1000 = 1%
  }
  mapping(address => TokenOptions) public tokensOptions;
  address[] public tokens;

  constructor(IERC20 _usdcToken, ISwapRouter _swapRouter, IUniswapV3Factory _swapFactory) Ownable(msg.sender) {
    usdcToken = _usdcToken;
    swapRouter = _swapRouter;
    swapFactory = _swapFactory;
  }

  function addTokenOption(address _factory, address _router, address _token, uint24 _poolFee, uint _share) public onlyOwner {
    tokensOptions[_token] = TokenOptions(
      _factory,
      _router,
      _token,
      _poolFee,
      _share
    );
  }

  function setTokens(address[] memory _tokens) public onlyOwner {
    tokens = _tokens;
  }

  function mint(address _receiver, uint _amountIn) public {
    TransferHelper.safeTransferFrom(address(usdcToken), msg.sender, address(this), _amountIn);
    uint feeAmount = Math.mulDiv(_amountIn, entryFee, baseFee);
    (, uint amountInWithoutFee) = Math.trySub(_amountIn, feeAmount);
    uint normalizedTotal = 0;
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      address pool = IUniswapV3Factory(swapFactory).getPool(
        address(usdcToken),
        token.token,
        token.poolFee
      );
      uint priceToken = _getPrice(pool);
      uint balanceToken = IERC20(token.token).balanceOf(address(this));
      normalizedTotal += priceToken * balanceToken;
    }
    uint balanceSofiToken = ISofiToken(sofiToken).totalSupply();
    uint outputSofiAmount = 0;
    if (balanceSofiToken == 0) {
      outputSofiAmount = amountInWithoutFee;
    } else {
      outputSofiAmount = Math.mulDiv(amountInWithoutFee, balanceSofiToken, amountInWithoutFee + normalizedTotal);
    }
    
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      address pool = IUniswapV3Factory(swapFactory).getPool(
        address(usdcToken),
        token.token,
        token.poolFee
      );
      TransferHelper.safeApprove(address(usdcToken), token.router, _amountIn);
      TransferHelper.safeApprove(address(usdcToken), pool, _amountIn);
      ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: address(usdcToken),
            tokenOut: token.token,
            fee: token.poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: Math.mulDiv(amountInWithoutFee, token.share, baseFee),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
      swapRouter.exactInputSingle(params);
    }

    sofiToken.mint(_receiver, outputSofiAmount);
  }

  function redeem(uint _amountIn) public {
    sofiToken.burn(address(this), _amountIn);
  }

  function setToken(address _token) public onlyOwner {
    sofiToken = ISofiToken(_token);
  }

  function estimateMint(uint _amountIn) view public returns(uint) {
    uint feeAmount = Math.mulDiv(_amountIn, entryFee, baseFee);
    (, uint amountInWithoutFee) = Math.trySub(_amountIn, feeAmount);
    uint normalizedTotal = 0;
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      address pool = IUniswapV3Factory(swapFactory).getPool(
        address(usdcToken),
        token.token,
        token.poolFee
      );
      uint priceToken = _getPrice(pool);
      uint balanceToken = IERC20(token.token).balanceOf(address(this));
      normalizedTotal += priceToken * balanceToken;
    }
    uint balanceSofiToken = ISofiToken(sofiToken).totalSupply();
    uint outputSofiAmount = 0;
    if (balanceSofiToken == 0) {
      outputSofiAmount = amountInWithoutFee;
    } else {
      outputSofiAmount = Math.mulDiv(amountInWithoutFee, balanceSofiToken, amountInWithoutFee + normalizedTotal);
    }
    return outputSofiAmount;
  }

  function estimateRedeem(uint _amount) view public returns(uint) {
    uint normalizedTotal = 0;
    uint balanceSofiToken = ISofiToken(sofiToken).totalSupply();
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      address pool = IUniswapV3Factory(swapFactory).getPool(
        address(usdcToken),
        token.token,
        token.poolFee
      );
      uint priceToken = _getPrice(pool);
      uint balanceToken = IERC20(token.token).balanceOf(address(this));
      normalizedTotal += priceToken * balanceToken;
    }
    uint outputAmountTotal = Math.mulDiv(_amount, balanceSofiToken, normalizedTotal);

    return outputAmountTotal;
  }

  function _getPrice(address _pool) view public returns(uint) {
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(_pool).slot0();
    (, uint priceX96) = Math.tryMul(uint(sqrtPriceX96), uint(sqrtPriceX96));
    (, uint unshiftedPrice) = Math.tryMul(priceX96, 1e18);
    return unshiftedPrice >> (96 * 2);
  }
}
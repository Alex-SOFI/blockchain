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
    uint mintTokens = MAX_INT;
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      TransferHelper.safeApprove(address(usdcToken), token.router, _amountIn);
      address pool = IUniswapV3Factory(swapFactory).getPool(
        address(usdcToken),
        token.token,
        token.poolFee
      );
      TransferHelper.safeApprove(address(usdcToken), pool, _amountIn);
      ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: address(usdcToken),
            tokenOut: token.token,
            fee: token.poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: Math.mulDiv(_amountIn, token.share, baseFee),
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
      uint balanceSwapToken = IERC20(token.token).balanceOf(address(this));
      uint amountOut = swapRouter.exactInputSingle(params);
      uint balanceToken = ISofiToken(sofiToken).totalSupply();

      uint outputAmount = Math.mulDiv(balanceToken, amountOut, balanceSwapToken);

      if (outputAmount < mintTokens) {
        mintTokens = outputAmount;
      }
    }

    sofiToken.mint(_receiver, mintTokens);
  }

  function redeem(uint _amountIn) public {
    TransferHelper.safeTransferFrom(address(sofiToken), msg.sender, address(this), _amountIn);
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      TransferHelper.safeApprove(address(sofiToken), address(token.router), _amountIn);
      address pool = swapFactory.getPool(
        address(usdcToken),
        address(token.token),
        token.poolFee
      );
      TransferHelper.safeApprove(address(token.token), pool, _amountIn);
      uint balanceSwapToken = IERC20(token.token).balanceOf(address(this));
      uint balanceToken = ISofiToken(sofiToken).totalSupply();
      ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
          tokenIn: token.token,
          tokenOut: address(usdcToken),
          fee: token.poolFee,
          recipient: msg.sender,
          deadline: block.timestamp,
          amountIn: Math.mulDiv(_amountIn, balanceSwapToken, balanceToken),
          amountOutMinimum: 0,
          sqrtPriceLimitX96: 0
        });
      
      swapRouter.exactInputSingle(params);
    }

    sofiToken.burn(msg.sender, _amountIn);
  }

  function setToken(address _token) public onlyOwner {
    sofiToken = ISofiToken(_token);
  }

  function estimateMint(uint _amount) view public returns(uint) {
    uint mintTokens = MAX_INT;
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      address pool = swapFactory.getPool(
        address(usdcToken),
        address(token.token),
        token.poolFee
      );
      (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
      (, uint priceX96) = Math.tryMul(uint(sqrtPriceX96), uint(sqrtPriceX96));
      (, uint unshiftedPrice) = Math.tryMul(priceX96, 1e18);
      uint price = unshiftedPrice >> (96 * 2);
      uint amountWithoutFee = Math.mulDiv(_amount, entryFee, baseFee);
      uint outputSwaptoken = Math.mulDiv(amountWithoutFee, price, 1e18*2);
      uint balanceSwapToken = IERC20(token.token).balanceOf(address(this));
      uint balanceToken = ISofiToken(sofiToken).totalSupply();
      uint outputTokenAmount = Math.mulDiv(balanceToken, outputSwaptoken, balanceSwapToken);

      if (outputTokenAmount < mintTokens) {
        mintTokens = outputTokenAmount;
      }    
    }
    return mintTokens;
  }

  function estimateRedeem(uint _amount) view public returns(uint) {
    uint outputAmountTotal = 0;
    for (uint i = 0; i < tokens.length; i++) {
      TokenOptions memory token = tokensOptions[tokens[i]];
      address pool = swapFactory.getPool(
        address(token.token),
        address(usdcToken),
        token.poolFee
      );
      (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
      (, uint priceX96) = Math.tryMul(uint(sqrtPriceX96), uint(sqrtPriceX96));
      (, uint unshiftedPrice) = Math.tryMul(priceX96, 1e18);
      uint price = unshiftedPrice >> (96 * 2);
      uint balanceToken = ISofiToken(sofiToken).totalSupply();
      uint balanceSwapToken = IERC20(token.token).balanceOf(address(this));
      uint outputAmountToken = Math.mulDiv(_amount, balanceSwapToken, balanceToken);
      uint outputSwapToken = Math.mulDiv(outputAmountToken, price, 1e18*2);
      outputAmountTotal += outputSwapToken;
    }

    return outputAmountTotal;
  }
}
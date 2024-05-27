// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import { IWETH9 } from "./WETH9.sol";

interface IToken {
  function mint(address _to, uint _amount) external;
  function burn(address _to, uint _amount) external;
  function totalSupply() view external returns(uint);
}

contract StaticPool is ERC20, Ownable, ReentrancyGuard {
  using Math for uint;

  struct Record {
    uint weight;
    uint balance;
    uint index;
  }

  struct SwapRecord {
    address factory;
    address router;
    uint24 poolFee;
    address pool;
  }

  address[] public _tokens;
  mapping(address => Record) public _records;
  mapping(address => SwapRecord) public _swapRecords;
  
  uint public _totalWeight;

  address public _USDC;
  address public _WETH;
  uint public _tvlFee;
  uint public _entryFee;
  uint public _exitFee;
  uint public _baseFee;
  address public _feeManager;
  uint public _lastFeeBlock;
  uint public _blocksPerYear;
  uint public accTVLFees = 0;

  constructor(address USDC, address WETH, uint entryFee, uint exitFee, uint baseFee, address feeManager, uint blocksPerYear, uint tvlFee) ERC20("SOPHIE", "SOPHIE") Ownable(msg.sender) {
    _entryFee = entryFee;
    _baseFee = baseFee;
    _USDC = USDC;
    _feeManager = feeManager;
    _exitFee = exitFee;
    _tvlFee = tvlFee;
    _lastFeeBlock = block.number;
    _blocksPerYear = blocksPerYear;
    _WETH = WETH;
  }

  function bind(address token, uint weight, address factory, address router, uint24 poolFee) public onlyOwner {
    address pool = IUniswapV3Factory(factory).getPool(
      address(_USDC),
      token,
      poolFee
    );

    _records[token] = Record({
      weight: weight,
      balance: 0,
      index: _tokens.length
    });
    _swapRecords[token] = SwapRecord({
      factory: factory,
      router: router,
      poolFee: poolFee,
      pool: pool
    });
    _tokens.push(token);
    _totalWeight += weight;
  }

  function changeWeight(address token, uint weight) public onlyOwner {
    _records[token].weight = weight;
  }

  function changeToken(address token, address factory, address router, uint24 poolFee) public onlyOwner {
    _swapRecords[token].factory = factory;
    _swapRecords[token].router = router;
    _swapRecords[token].poolFee = poolFee;
  }

  function exitPool(uint poolAmountIn, uint[] memory minAmountOut) public {
    uint poolTotal = totalSupply();

    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      uint balance = _records[token].balance;
      uint tokenAmountOut = Math.mulDiv(poolAmountIn, balance, poolTotal);

      require(tokenAmountOut >= minAmountOut[i], "ERR_LIMIT_OUT");

      (,uint updatedBalance) = Math.trySub(_records[token].balance, tokenAmountOut);
      _records[token].balance = updatedBalance;
    }

    uint feeAmount = calculateTvlFees();
    accTVLFees = accTVLFees + feeAmount;
    _lastFeeBlock = block.number;

    _burn(msg.sender, poolAmountIn);
  }

  function redeem(uint tokenAmountIn) public nonReentrant {
    uint amountFee = getAmountFee(tokenAmountIn, _exitFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);
    uint balanceBefore = IERC20(_USDC).balanceOf(address(this));

    uint[] memory balancesTokens = new uint[](_tokens.length);
    
    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      address router = _swapRecords[token].router;
      address pool = _swapRecords[token].pool;
      uint24 poolFee = _swapRecords[token].poolFee;
      uint balance = _records[token].balance;
      uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, balance, totalSupply());

      TransferHelper.safeApprove(token, router, amountTokenInForSwap);
      TransferHelper.safeApprove(token, pool, amountTokenInForSwap);
      ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: token,
            tokenOut: _USDC,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountTokenInForSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
      uint tokenBalanceBefore = IERC20(token).balanceOf(msg.sender);
      ISwapRouter(router).exactInputSingle(params);
      uint tokenBalanceAfter = IERC20(token).balanceOf(msg.sender);
      balancesTokens[i] = tokenBalanceBefore - tokenBalanceAfter;
    }

    uint balanceAfter = IERC20(_USDC).balanceOf(address(this));
    (,uint diffBalances) = Math.trySub(balanceAfter, balanceBefore);
    IWETH9(_WETH).withdraw(diffBalances);

    (bool sent,) = address(msg.sender).call{value: diffBalances}("");
    require(sent, "StaticPool: Failed to send");

    exitPool(amountWithoutFee, balancesTokens);
  }

  function redeemNative(uint tokenAmountIn) public nonReentrant {
    uint amountFee = getAmountFee(tokenAmountIn, _exitFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);
    uint[] memory balancesTokens = new uint[](_tokens.length);
    
    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      uint balance = _records[token].balance;
      uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, balance, totalSupply());

      TransferHelper.safeTransfer(token, address(msg.sender), amountTokenInForSwap);
      balancesTokens[i] = amountTokenInForSwap;
    }

    exitPool(amountWithoutFee, balancesTokens);
  }

  function joinPool(uint poolAmountOut, uint[] memory maxAmountsIn, address receiver) public {
    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      (,uint updatedBalance) = Math.tryAdd(_records[token].balance, maxAmountsIn[i]);
      _records[token].balance = updatedBalance;
    }
    
    uint feeAmount = calculateTvlFees();
    accTVLFees = accTVLFees + feeAmount;
    _lastFeeBlock = block.number;

    _mint(receiver, poolAmountOut);
  }

  function mint(address receiver, uint tokenAmountIn) public payable {
    if (msg.value > 0) {
      tokenAmountIn = msg.value;
    }

    uint amountFee = getAmountFee(tokenAmountIn, _entryFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);
    uint amountTokenOut = estimateMint(tokenAmountIn);
    uint[] memory balancesTokens = new uint[](_tokens.length);

    if (msg.value > 0) {
      IWETH9(_WETH).deposit{value: msg.value}();
    } else {
      TransferHelper.safeTransferFrom(address(_USDC), msg.sender, address(this), tokenAmountIn);
    }
    
    TransferHelper.safeTransfer(address(_USDC), _feeManager, amountFee);

    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      address router = _swapRecords[token].router;
      address pool = _swapRecords[token].pool;
      uint24 poolFee = _swapRecords[token].poolFee;
      uint weight = _records[token].weight;
      uint tokenBalanceBefore = IERC20(token).balanceOf(address(this));

      uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, weight, _totalWeight);

      TransferHelper.safeApprove(_USDC, router, amountTokenInForSwap);
      TransferHelper.safeApprove(_USDC, pool, amountTokenInForSwap);
      ISwapRouter.ExactInputSingleParams memory params =
        ISwapRouter.ExactInputSingleParams({
            tokenIn: _USDC,
            tokenOut: token,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountTokenInForSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
      ISwapRouter(router).exactInputSingle(params);

      uint tokenBalanceAfter = IERC20(token).balanceOf(address(this));
      balancesTokens[i] = tokenBalanceAfter - tokenBalanceBefore;
    }

    joinPool(amountTokenOut, balancesTokens, receiver);
  }

  function setFees(uint entryFee, uint exitFee, uint baseFee, address feeManager, uint blocksPerYear, uint tvlFee) public onlyOwner {
    _entryFee = entryFee;
    _baseFee = baseFee;
    _feeManager = feeManager;
    _exitFee = exitFee;
    _blocksPerYear = blocksPerYear;
    _tvlFee = tvlFee;

    uint feeAmount = calculateTvlFees();
    accTVLFees = accTVLFees + feeAmount;
    _lastFeeBlock = block.number;
  }


  function mintTvlFees() public onlyOwner {
    uint feeAmount = calculateTvlFees();

    (, uint total) = Math.tryAdd(feeAmount, accTVLFees);
    _mint(_feeManager, total);
    _lastFeeBlock = block.number;
    accTVLFees = 0;
  }

  function estimateMint(uint tokenAmountIn) view public returns(uint) {
    uint indexAmount = getIndexBalancePrice();
    uint amountFee = getAmountFee(tokenAmountIn, _entryFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);

    if (indexAmount != 0) {
      return Math.mulDiv(amountWithoutFee, totalSupply(), indexAmount);
    } else {
      return amountWithoutFee;
    }
  }

  function estimateRedeem(uint tokenAmountIn) view public returns(uint) {
    uint indexAmount = getIndexBalancePrice();
    uint amountFee = getAmountFee(tokenAmountIn, _exitFee);
    uint totalSupply = totalSupply();

    require(totalSupply != 0, "StaticPool: totalSupply equals zero");

    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);

    return Math.mulDiv(amountWithoutFee, indexAmount, totalSupply);
  }

  function getAmountOut(address pool, address tokenIn, uint amountIn) view public returns(uint amountOut) {
    (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    (, uint priceX96) = Math.tryMul(uint(sqrtPriceX96), uint(sqrtPriceX96));
    uint unshiftedPrice = priceX96 >> 96;
    (, unshiftedPrice) = Math.tryMul(unshiftedPrice, 1e18);
    uint price = unshiftedPrice >> 96;
    address token0 = IUniswapV3Pool(pool).token0();

    if (token0 == tokenIn) {
      (, amountOut) = Math.tryMul(amountIn, price); 
    } else {
      amountOut = Math.mulDiv(amountIn, 10**18, price); 
    }
  }

  function getIndexBalancePrice() view public returns(uint amountOut) {
    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      address factory = _swapRecords[token].factory;
      uint24 poolFee = _swapRecords[token].poolFee;
      
      address pool = IUniswapV3Factory(factory).getPool(
        address(_USDC),
        token,
        poolFee
      );
      uint balanceToken = IERC20(token).balanceOf(address(this));
      amountOut += getAmountOut(pool, token, balanceToken);
    }
  }

  function getAmountFee(uint amountIn, uint fee) view public returns(uint) {
    return Math.mulDiv(amountIn, fee, _baseFee);
  }

  function calculateTvlFees() public view returns (uint) {
    uint diffBlocks = block.number - _lastFeeBlock;
    (, uint nominator) = Math.tryMul(totalSupply(), _tvlFee);
    (, uint denominator) = Math.tryMul(_blocksPerYear, _baseFee);
    (, uint tokensPerBlock) = Math.tryDiv(nominator, denominator);
    return diffBlocks * tokensPerBlock;
  }

  receive() external payable {}
}
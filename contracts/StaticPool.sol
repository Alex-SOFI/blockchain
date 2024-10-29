// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./BaseStaticPool.sol";
import "./SwapLibrary.sol";

contract StaticPool is BaseStaticPool {
  using SafeERC20 for IERC20;
  using SwapLibrary for ISwapRouter;
  using SwapLibrary for ISwapOdosRouter;

  // Add vault mapping
  mapping(address => address) public tokenVaults;

  event VaultSet(address indexed token, address indexed vault);

  constructor(
    address ENTRY,
    address WETH,
    uint entryFee,
    uint exitFee,
    uint baseFee,
    address feeManager,
    uint blocksPerYear,
    uint tvlFee
  ) BaseStaticPool(ENTRY, WETH, entryFee, exitFee, baseFee, feeManager, blocksPerYear, tvlFee) {}

  // Add function to set vault for a token
  function setVault(address token, address vault) external onlyOwner {
      require(vault != address(0), "StaticPool: vault cannot be zero address");
      require(IERC20(token).approve(vault, type(uint256).max), "StaticPool: vault approval failed");
      tokenVaults[token] = vault;
      emit VaultSet(token, vault);
  }

  function exitPool(uint poolAmountIn, uint[] memory minAmountOut) private {
    uint poolTotal = totalSupply();

    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      uint balance = _records[token].balance;
      uint tokenAmountOut = Math.mulDiv(poolAmountIn, balance, poolTotal);

      require(tokenAmountOut >= minAmountOut[i], "ERR_LIMIT_OUT");

      address vault = tokenVaults[token];
      if (vault != address(0)) {
        uint shares = IERC4626(vault).balanceOf(address(this));
        uint assetsToWithdraw = Math.mulDiv(shares, tokenAmountOut, balance);
        IERC4626(vault).withdraw(assetsToWithdraw, address(this), address(this));
      }

      (,uint updatedBalance) = Math.trySub(_records[token].balance, tokenAmountOut);
      _records[token].balance = updatedBalance;
    }

    uint feeAmount = calculateTvlFees();
    accTVLFees = accTVLFees + feeAmount;
    _lastFeeBlock = _arbSys.arbBlockNumber();

    _burn(msg.sender, poolAmountIn);
  }

  function redeem(uint tokenAmountIn) public nonReentrant {
    uint amountFee = getAmountFee(tokenAmountIn, _exitFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);
    uint balanceBefore = IERC20(_ENTRY).balanceOf(address(this));

    uint[] memory balancesTokens = new uint[](_tokens.length);
    
    for (uint i = 0; i < _tokens.length; ++i) {
        address token = _tokens[i];
        address router = _swapRecords[token].router;
        uint24 poolFee = _swapRecords[token].poolFee;
        uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, _records[token].balance, totalSupply());

        if (amountTokenInForSwap > 0) {
            SwapLibrary.SwapParams memory params = SwapLibrary.SwapParams({
                tokenIn: token,
                tokenOut: _ENTRY,
                fee: poolFee,
                amountIn: amountTokenInForSwap,
                amountOutMinimum: 0,
                recipient: address(this)
            });

            uint amountOut = SwapLibrary.performUniswapV3Swap(ISwapRouter(router), params);
            balancesTokens[i] = amountOut;
        } else {
            balancesTokens[i] = 0;
        }
    }

    uint balanceAfter = IERC20(_ENTRY).balanceOf(address(this));
    (,uint diffBalances) = Math.trySub(balanceAfter, balanceBefore);
    IWETH9(_WETH).withdraw(diffBalances);

    (bool sent,) = address(msg.sender).call{value: diffBalances, gas: 100000}("");
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
      if (balance > 0) {
        uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, balance, totalSupply());
        IERC20(token).safeTransfer(address(msg.sender), amountTokenInForSwap);
        balancesTokens[i] = amountTokenInForSwap;
      } else {
        balancesTokens[i] = 0;
      }
    }

    exitPool(amountWithoutFee, balancesTokens);
  }

  function joinPool(uint poolAmountOut, uint[] memory maxAmountsIn, address receiver) private {
    for (uint i = 0; i < _tokens.length; i++) {
      address token = _tokens[i];
      (,uint updatedBalance) = Math.tryAdd(_records[token].balance, maxAmountsIn[i]);
      _records[token].balance = updatedBalance;
    }
    
    uint feeAmount = calculateTvlFees();
    accTVLFees = accTVLFees + feeAmount;
    _lastFeeBlock = _arbSys.arbBlockNumber();

    _mint(receiver, poolAmountOut);
  }

  // Override getIndexBalancePrice to account for vault shares
  function getIndexBalancePrice() public view returns(uint amountOut) {
      for (uint i = 0; i < _tokens.length; i++) {
          address token = _tokens[i];
          address vault = tokenVaults[token];
          uint shareBalance;
          uint tokenBalance;
          
          if (vault != address(0)) {
              // If token has a vault, calculate underlying token amount from shares
              shareBalance = IERC4626(vault).balanceOf(address(this));
              tokenBalance = IERC4626(vault).convertToAssets(shareBalance);
          } else {
              // If no vault, use direct token balance
              tokenBalance = IERC20(token).balanceOf(address(this));
          }

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

  function mint(address receiver) public payable nonReentrant {
    uint tokenAmountIn = msg.value;

    uint amountFee = getAmountFee(tokenAmountIn, _entryFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);
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
      address router = _swapRecords[token].router;
      address pool = _swapRecords[token].pool;
      uint24 poolFee = _swapRecords[token].poolFee;
      uint weight = _records[token].weight;

      if (weight != 0) {
        uint tokenBalanceBefore = IERC20(token).balanceOf(address(this));

        address vault = tokenVaults[token];
                
        if (vault != address(0)) {
          tokenBalanceBefore = IERC4626(vault).convertToAssets(
              IERC4626(vault).balanceOf(address(this))
          );
        } else {
          tokenBalanceBefore = IERC20(token).balanceOf(address(this));
        }

        uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, weight, _totalWeight);

        IERC20(_ENTRY).safeIncreaseAllowance(router, amountTokenInForSwap);
        IERC20(_ENTRY).safeIncreaseAllowance(pool, amountTokenInForSwap);
        ISwapRouter.ExactInputSingleParams memory params =
          ISwapRouter.ExactInputSingleParams({
              tokenIn: _ENTRY,
              tokenOut: token,
              fee: poolFee,
              recipient: address(this),
              deadline: block.timestamp,
              amountIn: amountTokenInForSwap,
              amountOutMinimum: 0,
              sqrtPriceLimitX96: 0
          });
        ISwapRouter(router).exactInputSingle(params);

        // After swap, deposit into vault if available
        if (vault != address(0)) {
          uint swappedAmount = IERC20(token).balanceOf(address(this));
          IERC4626(vault).deposit(swappedAmount, address(this));
          
          uint tokenBalanceAfter = IERC4626(vault).convertToAssets(
              IERC4626(vault).balanceOf(address(this))
          );
          balancesTokens[i] = tokenBalanceAfter - tokenBalanceBefore;
        } else {
          uint tokenBalanceAfter = IERC20(token).balanceOf(address(this));
          balancesTokens[i] = tokenBalanceAfter - tokenBalanceBefore;
        }
      } else {
        balancesTokens[i] = 0;
      }
    }

    joinPool(amountTokenOut, balancesTokens, receiver);
  }

  function mintTvlFees() public onlyOwner {
    uint feeAmount = calculateTvlFees();

    (, uint total) = Math.tryAdd(feeAmount, accTVLFees);
    _mint(_feeManager, total);
    _lastFeeBlock = _arbSys.arbBlockNumber();
    accTVLFees = 0;
  }

  function previewMint(uint tokenAmountIn) view public returns(uint) {
    uint indexAmount = getIndexBalancePrice();
    uint amountFee = getAmountFee(tokenAmountIn, _entryFee);
    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);

    if (indexAmount != 0) {
      return Math.mulDiv(amountWithoutFee, totalSupply(), indexAmount);
    } else {
      return amountWithoutFee;
    }
  }

  function previewRedeem(uint tokenAmountIn) view public returns(uint) {
    uint indexAmount = getIndexBalancePrice();
    uint amountFee = getAmountFee(tokenAmountIn, _exitFee);
    uint _totalSupply = totalSupply();

    require(_totalSupply != 0, "StaticPool: totalSupply equals zero");

    (,uint amountWithoutFee) = Math.trySub(tokenAmountIn, amountFee);

    return Math.mulDiv(amountWithoutFee, indexAmount, _totalSupply);
  }
}
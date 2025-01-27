// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "./BaseStaticPool.sol";
import "./SwapLibrary.sol";

interface ISwapRouterCustom {
  struct ExactInputSingleParams {
      address tokenIn;
      address tokenOut;
      uint24 fee;
      address recipient;
      uint256 amountIn;
      uint256 amountOutMinimum;
      uint160 sqrtPriceLimitX96;
  }

  /// @notice Swaps `amountIn` of one token for as much as possible of another token
  /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
  /// @return amountOut The amount of the received token
  function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract StaticPool is BaseStaticPool {
  using SafeERC20 for IERC20;
  using SwapLibrary for ISwapRouterCustom;

  struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
  }

  // Add vault mapping
  mapping(address => address) public tokenVaults;

  event VaultSet(address indexed token, address indexed vault);
  event RewardsReinvested(address indexed token, address indexed vault, uint256 rewardAmount);
  event CompoundFailed(address indexed token, address indexed vault, string reason);

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
    _lastFeeBlock = block.number;

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
        uint bBalance = normalizeAmount(_records[token].balance, IERC20Metadata(token).decimals());
        uint amountTokenInForSwap = Math.mulDiv(amountWithoutFee, bBalance, totalSupply());
        address vault = tokenVaults[token];
        
        if (vault != address(0) && amountTokenInForSwap > 0) {
            IERC4626 vaultContract = IERC4626(vault);
            uint256 totalShares = vaultContract.balanceOf(address(this));
            uint256 sharesToWithdraw = Math.mulDiv(totalShares, amountTokenInForSwap, bBalance);
            
            // Выводим токены из vault в контракт пула
            vaultContract.redeem(
                sharesToWithdraw,
                address(this),
                address(this)
            );
        }

        uint denormalizedAmount = denormalizeAmount(amountTokenInForSwap, IERC20Metadata(token).decimals());
        if (amountTokenInForSwap > 0) {
            SwapLibrary.SwapParams memory params = SwapLibrary.SwapParams({
                tokenIn: token,
                tokenOut: _ENTRY,
                fee: poolFee,
                amountIn: denormalizedAmount,
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
    _lastFeeBlock = block.number;

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
        ISwapRouterCustom.ExactInputSingleParams memory params =
          ISwapRouterCustom.ExactInputSingleParams({
              tokenIn: _ENTRY,
              tokenOut: token,
              fee: poolFee,
              recipient: address(this),
              amountIn: amountTokenInForSwap,
              amountOutMinimum: 0,
              sqrtPriceLimitX96: 0
          });
        ISwapRouterCustom(router).exactInputSingle(params);

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
    _lastFeeBlock = block.number;
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

  function reinvestVaultRewards(address[] calldata tokens) 
      external 
      nonReentrant 
      returns (uint256[] memory amounts) 
  {
      require(tokens.length > 0, "StaticPool: empty tokens array");
      amounts = new uint256[](tokens.length);

      for (uint256 i = 0; i < tokens.length; i++) {
          address token = tokens[i];
          address vault = tokenVaults[token];
          
          require(vault != address(0), "StaticPool: vault not set");

          try this._reinvestSingleVault(token, vault) returns (uint256 reinvestedAmount) {
              amounts[i] = reinvestedAmount;
              emit RewardsReinvested(token, vault, reinvestedAmount);
          } catch Error(string memory reason) {
              emit CompoundFailed(token, vault, reason);
              amounts[i] = 0;
          }
      }

      return amounts;
  }

  function _reinvestSingleVault(address token, address vault) 
    external 
    returns (uint256 reinvestedAmount) 
  {
    require(msg.sender == address(this), "StaticPool: only internal call");
    
    IERC4626 vaultContract = IERC4626(vault);
    
    uint256 actualTokenBalance = IERC20(token).balanceOf(address(this));
    
    if (actualTokenBalance > 0) {
        reinvestedAmount = actualTokenBalance;
        
        uint256 allowance = IERC20(token).allowance(address(this), vault);
        if (allowance < actualTokenBalance) {
            IERC20(token).approve(vault, type(uint256).max);
        }
        
        vaultContract.deposit(actualTokenBalance, address(this));
        
        _records[token].balance = vaultContract.convertToAssets(
            vaultContract.balanceOf(address(this))
        );
    }
    
    return reinvestedAmount;
  }

  function normalizeAmount(uint256 amount, uint256 amountDecimals) internal pure returns (uint256 normalizedAmount) {
    uint256 standartDecimals = 18;
    if (amountDecimals < standartDecimals) {
      (, normalizedAmount) = Math.tryMul(amount, 10 ** (standartDecimals - amountDecimals));
    } else {
      normalizedAmount = amount;
    }
  }

  function denormalizeAmount(uint256 amount, uint256 tokenDecimals) internal pure returns (uint256) {
    uint256 standardDecimals = 18;
    if (tokenDecimals < standardDecimals) {
      uint256 divisor = 10 ** (standardDecimals - tokenDecimals);
      return amount / divisor; // Простое деление, так как Math.mulDiv не подходит для деления
    } else {
      return amount;
    }
  }
}
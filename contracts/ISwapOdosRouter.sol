// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

interface ISwapOdosRouter {
  struct swapTokenInfo {
    address inputToken;
    uint256 inputAmount;
    address inputReceiver;
    address outputToken;
    uint256 outputQuote;
    uint256 outputMin;
    address outputReceiver;
  }

  function swap(
    swapTokenInfo memory tokenInfo,
    bytes calldata pathDefinition,
    address executor,
    uint32 referralCode
  )
    external
    payable
    returns (uint256 amountOut);
}
// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

interface ISofiToken {
  function mint(address _to, uint _amount) external;
}

contract TokenManager is Ownable {
  ISofiToken private token;
  IERC20 private usdcToken;

  ISwapRouter public immutable swapRouter;

  address public constant SWAP_TOKEN = 0xfF9b1273f5722C16C4f0b9E9a5aeA83006FE6152;
  uint24 public constant poolFee = 3000;

  constructor(IERC20 _usdcToken, ISwapRouter _swapRouter) Ownable(msg.sender) {
    usdcToken = _usdcToken;
    swapRouter = _swapRouter;
  }

  function mint(uint _amountIn, uint24 _poolFee) public {
    TransferHelper.safeTransferFrom(address(usdcToken), msg.sender, address(this), _amountIn);
    TransferHelper.safeApprove(address(usdcToken), address(swapRouter), _amountIn);

    ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdcToken),
                tokenOut: SWAP_TOKEN,
                fee: _poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

    uint256 amountOut = swapRouter.exactInputSingle(params);
    
    token.mint(msg.sender, amountOut);
  }

  function redeem() public {

  }

  function setToken(address _token) public onlyOwner {
    token = ISofiToken(_token);
  }

  function estimateMint(uint _amount) pure public returns(uint) {
    return _amount;
  }
}
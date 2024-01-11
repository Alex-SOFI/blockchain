// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UsdcToken is ERC20 {
  constructor() ERC20("USDC Token", "USDC") {}

  function mint(address _to, uint _amount) public {
    _mint(_to, _amount);
  }
}
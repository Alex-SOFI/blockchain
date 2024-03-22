// contracts/MyNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract SampleToken is ERC20 {
  constructor(string memory name_, string memory symbol_, uint initialSupply_) ERC20(name_, symbol_) {
    _mint(msg.sender, initialSupply_);
  }

  function mint(address _to, uint _amount) public {
    _mint(_to, _amount);
  }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockURD {
    using SafeERC20 for IERC20;
    
    mapping(address => mapping(address => uint256)) public claimed;
    
    function claim(
        address account,
        address reward,
        uint256 claimable,
        bytes32[] calldata proof
    ) external returns (uint256 amount) {
        uint256 alreadyClaimed = claimed[account][reward];
        
        require(claimable > alreadyClaimed, "MockURD: nothing to claim");
        
        amount = claimable - alreadyClaimed;
        claimed[account][reward] = claimable;
        
        uint256 balance = IERC20(reward).balanceOf(address(this));
        if (balance >= amount) {
            IERC20(reward).safeTransfer(account, amount);
        }
        
        return amount;
    }
    
    function fundRewards(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
    
    function setClaimedAmount(address account, address reward, uint256 amount) external {
        claimed[account][reward] = amount;
    }
}


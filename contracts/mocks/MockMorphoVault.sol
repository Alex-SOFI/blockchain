// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockMorphoVault is ERC20 {
    using SafeERC20 for IERC20;
    
    IERC20 public immutable asset;
    address public curator;
    uint96 public fee;
    address public feeRecipient;
    address public guardian;
    
    uint256 private _totalAssets;
    
    constructor(
        address _asset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        asset = IERC20(_asset);
        curator = msg.sender;
        feeRecipient = msg.sender;
        guardian = msg.sender;
        fee = 0; // 0% fee for testing
    }
    
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(assets > 0, "MockVault: zero deposit");
        
        shares = convertToShares(assets);
        
        asset.safeTransferFrom(msg.sender, address(this), assets);
        
        _mint(receiver, shares);
        
        _totalAssets += assets;
        
        return shares;
    }
    
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        shares = convertToShares(assets);
        
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        _burn(owner, shares);
        _totalAssets -= assets;
        
        asset.safeTransfer(receiver, assets);
        
        return shares;
    }
    
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        
        assets = convertToAssets(shares);
        
        _burn(owner, shares);
        _totalAssets -= assets;
        
        asset.safeTransfer(receiver, assets);
        
        return assets;
    }
    
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        _totalAssets += assets;
        
        return assets;
    }
    
    function totalAssets() public view returns (uint256) {
        return _totalAssets;
    }
    
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets;
        }
        return (assets * supply) / _totalAssets;
    }
    
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        return (shares * _totalAssets) / supply;
    }
    
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }
    
    function previewMint(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }
    
    function previewWithdraw(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }
    
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }
    
    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }
    
    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }
    
    function maxWithdraw(address owner) external view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }
    
    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }
    
    // Simulate yield generation
    function simulateYield(uint256 yieldAmount) external {
        _totalAssets += yieldAmount;
    }
    
    // For testing - set fee
    function setFee(uint96 _fee) external {
        fee = _fee;
    }
}


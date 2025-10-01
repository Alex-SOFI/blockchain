// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IMorpho.sol";

abstract contract MorphoVaultManager {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    mapping(address => address) public morphoVaults;
    
    address public urdContract;
    
    event MorphoVaultSet(address indexed token, address indexed vault);
    
    event RewardsClaimed(
        address indexed user, 
        address indexed rewardToken, 
        uint256 amount
    );
    
    event RewardsReinvested(
        address indexed token, 
        address indexed vault,
        uint256 amount
    );
    
    event URDContractUpdated(address indexed oldURD, address indexed newURD);
    
    /**
     * @notice Constructor sets the initial URD contract
     * @param _urdContract Address of the Universal Rewards Distributor
     */
    constructor(address _urdContract) {
        require(_urdContract != address(0), "MorphoVaultManager: URD cannot be zero");
        urdContract = _urdContract;
    }
    
    /**
     * @notice Sets a Morpho vault for a specific token
     * @dev Should be called by owner only (enforced in child contract)
     * @param token The underlying token address
     * @param vault The Morpho vault address
     */
    function _setMorphoVault(address token, address vault) internal virtual {
        require(token != address(0), "MorphoVaultManager: token cannot be zero");
        require(vault != address(0), "MorphoVaultManager: vault cannot be zero");
        
        require(
            IMetaMorpho(vault).asset() == token, 
            "MorphoVaultManager: asset mismatch"
        );
        
        if (morphoVaults[token] != address(0)) {
            IERC20(token).approve(morphoVaults[token], 0);
        }
        
        morphoVaults[token] = vault;
        IERC20(token).approve(vault, type(uint256).max);
        
        emit MorphoVaultSet(token, vault);
    }
    
    /**
     * @notice Deposits tokens into a Morpho vault
     * @dev Internal function, returns shares minted
     * @param token The token to deposit
     * @param amount The amount to deposit
     * @return shares The number of vault shares received
     */
    function _depositToMorpho(
        address token,
        uint256 amount
    ) internal returns (uint256 shares) {
        address vault = morphoVaults[token];
        require(vault != address(0), "MorphoVaultManager: vault not set");
        require(amount > 0, "MorphoVaultManager: zero amount");
        
        shares = IMetaMorpho(vault).deposit(amount, address(this));
    }
    
    /**
     * @notice Withdraws tokens from a Morpho vault by redeeming shares
     * @dev Internal function, returns assets withdrawn
     * @param token The token to withdraw
     * @param shares The number of shares to redeem
     * @return assets The amount of tokens received
     */
    function _withdrawFromMorpho(
        address token,
        uint256 shares
    ) internal returns (uint256 assets) {
        address vault = morphoVaults[token];
        require(vault != address(0), "MorphoVaultManager: vault not set");
        require(shares > 0, "MorphoVaultManager: zero shares");
        
        assets = IMetaMorpho(vault).redeem(
            shares,
            address(this),
            address(this)
        );
    }
    
    /**
     * @notice Gets the current token balance in a Morpho vault
     * @dev Converts vault shares to underlying token amount
     * @param token The token to check
     * @return balance The token balance in the vault
     */
    function getMorphoBalance(address token) public view returns (uint256 balance) {
        address vault = morphoVaults[token];
        if (vault == address(0)) return 0;
        
        uint256 shares = IMetaMorpho(vault).balanceOf(address(this));
        if (shares == 0) return 0;
        
        balance = IMetaMorpho(vault).convertToAssets(shares);
    }
    
    /**
     * @notice Gets the vault shares balance for a token
     * @param token The token to check
     * @return shares The number of vault shares owned
     */
    function getMorphoShares(address token) public view returns (uint256 shares) {
        address vault = morphoVaults[token];
        if (vault == address(0)) return 0;
        
        shares = IMetaMorpho(vault).balanceOf(address(this));
    }
    
    /**
     * @notice Claims rewards from Universal Rewards Distributor
     * @dev Internal function, should be wrapped by child contract with reentrancy protection
     * @param user The user claiming rewards
     * @param rewardToken The reward token address
     * @param claimable The cumulative claimable amount
     * @param proof The Merkle proof for verification
     * @return amount The amount actually claimed
     */
    function claimRewards(
        address user,
        address rewardToken,
        uint256 claimable,
        bytes32[] calldata proof
    ) public returns (uint256 amount) {
        require(urdContract != address(0), "MorphoVaultManager: URD not set");
        require(user != address(0), "MorphoVaultManager: user cannot be zero");
        require(rewardToken != address(0), "MorphoVaultManager: reward token cannot be zero");
        
        amount = IUniversalRewardsDistributor(urdContract).claim(
            user,
            rewardToken,
            claimable,
            proof
        );
        
        emit RewardsClaimed(user, rewardToken, amount);
    }
    
    /**
     * @notice Updates the URD contract address
     * @dev Internal function, should be called from child contract with access control
     * @param _urdContract The new URD contract address
     */
    function setURDContract(address _urdContract) internal virtual {
        require(
            _urdContract != address(0), 
            "MorphoVaultManager: URD cannot be zero"
        );
        
        address oldURD = urdContract;
        urdContract = _urdContract;
        
        emit URDContractUpdated(oldURD, _urdContract);
    }
    
    /**
     * @notice Gets the Morpho vault address for a token
     * @param token The token address
     * @return vault The vault address (address(0) if not set)
     */
    function getMorphoVault(address token) external view returns (address vault) {
        vault = morphoVaults[token];
    }
    
    /**
     * @notice Checks if a token has a Morpho vault configured
     * @param token The token address
     * @return hasVault True if vault is configured
     */
    function hasMorphoVault(address token) public view returns (bool) {
        return morphoVaults[token] != address(0);
    }
}


// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IMetaMorpho
 * @notice Interface for Morpho Vault (MetaMorpho) - ERC4626 compliant vault
 * @dev Extends ERC4626 standard with Morpho-specific functionality
 */
interface IMetaMorpho is IERC4626 {
    /**
     * @notice Returns the curator address of the vault
     * @dev Curator manages the vault's allocation strategy
     * @return curator The address of the curator
     */
    function curator() external view returns (address);
    
    /**
     * @notice Returns the current performance fee
     * @dev Fee is in basis points (e.g., 500 = 5%)
     * @return fee The performance fee in basis points
     */
    function fee() external view returns (uint96);
    
    /**
     * @notice Returns the fee recipient address
     * @dev Address that receives performance fees
     * @return feeRecipient The address receiving fees
     */
    function feeRecipient() external view returns (address);
    
    /**
     * @notice Returns the vault's guardian address
     * @dev Guardian can pause the vault in emergency situations
     * @return guardian The address of the guardian
     */
    function guardian() external view returns (address);
}

/**
 * @title IUniversalRewardsDistributor
 * @notice Interface for Morpho's Universal Rewards Distributor (URD)
 * @dev Distributes rewards using Merkle proof verification
 */
interface IUniversalRewardsDistributor {
    /**
     * @notice Claims rewards for an account
     * @dev Uses Merkle proof to verify eligibility
     * @param account The address claiming rewards
     * @param reward The address of the reward token
     * @param claimable The cumulative amount claimable (not the delta)
     * @param proof The Merkle proof for verification
     * @return amount The actual amount claimed (claimable - already claimed)
     */
    function claim(
        address account,
        address reward,
        uint256 claimable,
        bytes32[] calldata proof
    ) external returns (uint256 amount);
    
    /**
     * @notice Returns the amount already claimed by an account for a specific reward token
     * @param account The address to check
     * @param reward The reward token address
     * @return claimed The amount already claimed
     */
    function claimed(address account, address reward) 
        external 
        view 
        returns (uint256);
}


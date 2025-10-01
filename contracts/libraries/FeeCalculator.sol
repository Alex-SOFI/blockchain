// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

library FeeCalculator {
    uint256 private constant BASE = 1000000;

    error InvalidFee();
    error ZeroAmount();

    /**
     * @notice Calculates fee amount
     * @param amount Total amount
     * @param feeRate Fee rate (in base units)
     * @return feeAmount Calculated fee
     */
    function calculateFee(
        uint256 amount,
        uint256 feeRate
    ) internal pure returns (uint256 feeAmount) {
        if (amount == 0) return 0;
        feeAmount = (amount * feeRate) / BASE;
    }

    /**
     * @notice Calculates amount after fee deduction
     * @param amount Total amount
     * @param feeRate Fee rate
     * @return netAmount Amount after fee
     */
    function calculateNetAmount(
        uint256 amount,
        uint256 feeRate
    ) internal pure returns (uint256 netAmount) {
        uint256 fee = calculateFee(amount, feeRate);
        netAmount = amount - fee;
    }

    /**
     * @notice Calculates TVL-based fees
     * @param totalSupply Current total supply
     * @param tvlFeeRate TVL fee rate
     * @param blocksSinceLastFee Blocks since last fee collection
     * @param blocksPerYear Blocks per year
     * @return feeAmount TVL fee amount
     */
    function calculateTVLFee(
        uint256 totalSupply,
        uint256 tvlFeeRate,
        uint256 blocksSinceLastFee,
        uint256 blocksPerYear
    ) internal pure returns (uint256 feeAmount) {
        if (totalSupply == 0 || blocksSinceLastFee == 0) return 0;
        
        uint256 annualFee = (totalSupply * tvlFeeRate) / BASE;
        feeAmount = (annualFee * blocksSinceLastFee) / blocksPerYear;
    }

    /**
     * @notice Validates fee rates
     * @param entryFee Entry fee rate
     * @param exitFee Exit fee rate  
     * @param baseFee Base fee rate
     * @param tvlFee TVL fee rate
     * @return valid True if all fees are valid
     */
    function validateFees(
        uint256 entryFee,
        uint256 exitFee,
        uint256 baseFee,
        uint256 tvlFee
    ) internal pure returns (bool valid) {
        if (entryFee >= baseFee) revert InvalidFee();
        if (exitFee >= baseFee) revert InvalidFee();
        
        if (tvlFee >= baseFee) revert InvalidFee();
        
        uint256 totalFees = entryFee + exitFee;
        uint256 maxTotalFee = (baseFee * 20) / 100; // 20% of base = 5% if base is 25%
        
        if (totalFees > maxTotalFee) revert InvalidFee();
        
        return true;
    }

    /**
     * @notice Calculates fee share for distribution
     * @param totalFees Total fees collected
     * @param userShare User's share (in basis points)
     * @return feeShare User's fee share
     */
    function calculateFeeShare(
        uint256 totalFees,
        uint256 userShare
    ) internal pure returns (uint256 feeShare) {
        if (totalFees == 0) return 0;
        feeShare = (totalFees * userShare) / BASE;
    }
}


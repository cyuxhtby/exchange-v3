// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ISovereignVaultMinimal} from "@valantislabs/contracts/pools/interfaces/ISovereignVaultMinimal.sol";

/**
    @title Extended interface for Sovereign Pool's custom vault.
 */
interface ISovereignVault is ISovereignVaultMinimal {
    /**
        @notice Updates the reserves for a given pool and tokens.
        @param _pool Address of the Sovereign Pool.
        @param _tokens Array of token addresses.
        @param _amounts Array of token amounts.
     */
    function updateReserves(address _pool, address[] calldata _tokens, uint256[] calldata _amounts) external;

    /**
        @notice Deposits tokens into the vault for a specified pool.
        @param _pool Address of the Sovereign Pool.
        @param _token Address of the token to deposit.
        @param _amount Amount of tokens to deposit.
     */
    function deposit(address _pool, address _token, uint256 _amount) external;

    /**
        @notice Withdraws tokens from the vault for a specified pool.
        @param _pool Address of the Sovereign Pool.
        @param _token Address of the token to withdraw.
        @param _amount Amount of tokens to withdraw.
     */
    function withdraw(address _pool, address _token, uint256 _amount) external;

    /**
        @notice Claims pool manager fees.
        @param _feePoolManager0 Amount of token0 fees to claim.
        @param _feePoolManager1 Amount of token1 fees to claim.
     */
    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external;

    /**
        @notice Registers a new pool with the vault.
        @param _pool Address of the pool to register.
        @param _tokens Array of token addresses associated with the pool.
        @param _alm Address of the ALM associated with the pool.
     */
    function registerPool(address _pool, address[] memory _tokens, address _alm) external;

    /**
        @notice Deactivates a pool in the vault.
        @param _pool Address of the pool to deactivate.
     */
    function deactivatePool(address _pool) external;

    /**
        @notice Quotes to recipient from the vault.
        @param _isZeroToOne Direction of the swap.
        @param _amount Amount of tokens.
        @param _recipient Address of the recipient.
     */
    function quoteToRecipient(bool _isZeroToOne, uint256 _amount, address _recipient) external;

    /**
        @notice Approves the pool to spend a specific amount of tokens for a swap
        @dev This is called by the ALM before executing a swap
        @param _tokenOut Address of the token to be swapped out
        @param _amount Amount of tokens to approve for the swap
     */
    function approvePoolAllowance(address _tokenOut, uint256 _amount) external;


    /**
        @notice Approves the pool to spend a specific amount of tokens for a swap
        @dev This is called by the ALM before executing a swap
        @param _pool Address of a given pool
        @param _token Address of the token to be swapped out
        @param _amount Amount of tokens to approve for the swap
     */
    function approvePool(address _pool, address _token, uint256 _amount) external;

    function transferFromVault(address _token, address _to, uint256 _amount) external;

    function approvePoolForSwap(address _token, uint256 _amount) external ;
}
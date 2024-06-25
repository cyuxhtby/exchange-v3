// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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
}
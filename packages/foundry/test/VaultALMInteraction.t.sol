// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Base.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {SovereignPoolSwapParams, SovereignPoolSwapContextData} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";

contract VaultALMInteraction is Base {
    function setUp() public override {
        super.setUp();
    }

    function testDeposit() public {
        uint256 depositAmount = 100e18;

        // Approve tokens for deposit
        vm.startPrank(USER1);
        token0.approve(address(alm), depositAmount);
        token1.approve(address(alm), depositAmount);
        vm.stopPrank();

        // Deposit
        vm.prank(USER1);
        (uint256 amount0Deposited, uint256 amount1Deposited) = alm.depositLiquidity(depositAmount, depositAmount, "");

        // Check deposit amounts
        assertEq(amount0Deposited, depositAmount, "Incorrect amount of token0 deposited");
        assertEq(amount1Deposited, depositAmount, "Incorrect amount of token1 deposited");

        // Check vault balances
        assertEq(token0.balanceOf(address(vault)), depositAmount, "Incorrect vault balance for token0");
        assertEq(token1.balanceOf(address(vault)), depositAmount, "Incorrect vault balance for token1");

        // Check pool reserves in vault
        uint256[] memory reserves = vault.getReservesForPool(address(pool), vault.getTokensForPool(address(pool)));
        assertEq(reserves[0], depositAmount, "Incorrect pool reserve for token0 in vault");
        assertEq(reserves[1], depositAmount, "Incorrect pool reserve for token1 in vault");
    }

    function testSimpleSwap() public {}
}
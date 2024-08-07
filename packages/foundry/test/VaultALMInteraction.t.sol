// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Base.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {SovereignPoolSwapParams, SovereignPoolSwapContextData} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";

contract VaultALMInteraction is Base {
    uint256 constant SWAP_AMOUNT = 10e18;

    function setUp() public override {
        super.setUp();
        addInitialLiquidity();
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
        assertEq(token0.balanceOf(address(vault)), INITIAL_LIQUIDITY + depositAmount, "Incorrect vault balance for token0");
        assertEq(token1.balanceOf(address(vault)), INITIAL_LIQUIDITY + depositAmount, "Incorrect vault balance for token1");

        // Check pool reserves in vault
        uint256[] memory reserves = vault.getReservesForPool(address(pool), vault.getTokensForPool(address(pool)));
        assertEq(reserves[0], INITIAL_LIQUIDITY + depositAmount, "Incorrect pool reserve for token0 in vault");
        assertEq(reserves[1], INITIAL_LIQUIDITY + depositAmount, "Incorrect pool reserve for token1 in vault");
    }

    function testSwapToken0ForToken1() public {
        uint256 expectedOutputAmount = calculateExpectedOutput(SWAP_AMOUNT, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        
        vm.startPrank(USER2);
        token0.approve(address(pool), SWAP_AMOUNT);
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(
            SovereignPoolSwapParams({
                isSwapCallback: false,
                isZeroToOne: true,
                amountIn: SWAP_AMOUNT,
                amountOutMin: expectedOutputAmount,
                deadline: block.timestamp + 1 hours,
                recipient: USER2,
                swapTokenOut: address(token1),
                swapContext: SovereignPoolSwapContextData({
                    externalContext: "",
                    verifierContext: "",
                    swapCallbackContext: "",
                    swapFeeModuleContext: ""
                })
            })
        );
        vm.stopPrank();

        assertSwapResult(true, amountInUsed, amountOut, expectedOutputAmount);
    }

    function testSwapToken1ForToken0() public {
        uint256 expectedOutputAmount = calculateExpectedOutput(SWAP_AMOUNT, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY);
        
        vm.startPrank(USER2);
        token1.approve(address(pool), SWAP_AMOUNT);
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(
            SovereignPoolSwapParams({
                isSwapCallback: false,
                isZeroToOne: false,
                amountIn: SWAP_AMOUNT,
                amountOutMin: expectedOutputAmount,
                deadline: block.timestamp + 1 hours,
                recipient: USER2,
                swapTokenOut: address(token0),
                swapContext: SovereignPoolSwapContextData({
                    externalContext: "",
                    verifierContext: "",
                    swapCallbackContext: "",
                    swapFeeModuleContext: ""
                })
            })
        );
        vm.stopPrank();

        assertSwapResult(false, amountInUsed, amountOut, expectedOutputAmount);
    }

    function assertSwapResult(bool isZeroToOne, uint256 amountInUsed, uint256 amountOut, uint256 expectedOutputAmount) internal view {
        assertEq(amountInUsed, SWAP_AMOUNT, "Amount in used does not match swap amount");
        assertEq(amountOut, expectedOutputAmount, "Amount out does not match expected output amount");

        if (isZeroToOne) {
            assertEq(token0.balanceOf(USER2), INITIAL_BALANCE - SWAP_AMOUNT, "Incorrect user balance token0");
            assertEq(token1.balanceOf(USER2), INITIAL_BALANCE + expectedOutputAmount, "Incorrect user balance token1");
        } else {
            assertEq(token1.balanceOf(USER2), INITIAL_BALANCE - SWAP_AMOUNT, "Incorrect user balance token1");
            assertEq(token0.balanceOf(USER2), INITIAL_BALANCE + expectedOutputAmount, "Incorrect user balance token0");
        }

        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        uint256[] memory reserves = vault.getReservesForPool(address(pool), tokens);
        
        if (isZeroToOne) {
            assertEq(reserves[0], INITIAL_LIQUIDITY + SWAP_AMOUNT, "Incorrect pool reserve token0");
            assertEq(reserves[1], INITIAL_LIQUIDITY - expectedOutputAmount, "Incorrect pool reserve token1");
        } else {
            assertEq(reserves[1], INITIAL_LIQUIDITY + SWAP_AMOUNT, "Incorrect pool reserve token1");
            assertEq(reserves[0], INITIAL_LIQUIDITY - expectedOutputAmount, "Incorrect pool reserve token0");
        }
    }
}
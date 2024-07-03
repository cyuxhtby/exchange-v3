// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {ALM} from "../contracts/ALM.sol";
import {ALMRegistry} from "../contracts/ALMRegistry.sol";
import {Pool} from "../contracts/Pool.sol";
import {SovereignPoolConstructorArgs} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";
import {MockToken} from "../contracts/MockToken.sol";

contract Base is Test {
    Vault public vault;
    ALM public alm;
    ALM public alm2;
    ALMRegistry public almRegistry;
    Pool public pool;
    Pool public pool2;
    MockToken public token0;
    MockToken public token1;
    MockToken public token2;
    MockToken public token3;

    address public constant POOL_MANAGER = address(1);
    address public constant USER1 = address(2);
    address public constant USER2 = address(3);

    uint256 public constant INITIAL_BALANCE = 2000e18;
    uint256 public constant INITIAL_LIQUIDITY = 1000e18;

    function setUp() public virtual {
        token0 = new MockToken("Token0", "TKN0");
        token1 = new MockToken("Token1", "TKN1");
        token2 = new MockToken("Token2", "TKN2");
        token3 = new MockToken("Token3", "TKN3");

        vault = new Vault();
        almRegistry = new ALMRegistry();
        
        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs(
            address(token0),
            address(token1),
            address(0), // No protocol factory for now
            address(POOL_MANAGER),
            address(vault),
            address(0), // No verifier module
            false, // Not rebase token
            false, // Not rebase token
            0, // Value not relevant
            0, // Value not relevant
            0 // Zero fees for now
        );
        pool = new Pool(args);
        alm = new ALM(address(pool), address(vault), address(almRegistry));

        // Setup ALM in pool
        vm.prank(POOL_MANAGER);
        pool.setALM(address(alm));

        // Register pool in vault
        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        vault.registerPool(address(pool), tokens, address(alm));

        // Register ALM in ALMRegistry
        almRegistry.registerALM(address(token0), address(token1), address(alm));

        // Mint test tokens
        token0.mint(USER1, INITIAL_BALANCE);
        token1.mint(USER1, INITIAL_BALANCE);
        token0.mint(USER2, INITIAL_BALANCE);
        token1.mint(USER2, INITIAL_BALANCE);

        // Setup second pool to test ALM chaining
        SovereignPoolConstructorArgs memory args2 = SovereignPoolConstructorArgs(
            address(token2),
            address(token3),
            address(0),
            address(POOL_MANAGER),
            address(vault),
            address(0),
            false,
            false,
            0,
            0,
            0
        );
        pool2 = new Pool(args2);
        alm2 = new ALM(address(pool2), address(vault), address(almRegistry));

        // Setup ALM in pool2
        vm.prank(POOL_MANAGER);
        pool2.setALM(address(alm2));

        // Register pool2 in vault
        address[] memory tokens2 = new address[](2);
        tokens2[0] = address(token2);
        tokens2[1] = address(token3);
        vault.registerPool(address(pool2), tokens2, address(alm2));

        // Register ALM2 in ALMRegistry
        almRegistry.registerALM(address(token2), address(token3), address(alm2));
        // Intermediate ALM
        almRegistry.registerALM(address(token1), address(token2), address(alm2));

        // Mint test tokens for second pool
        token2.mint(USER1, INITIAL_BALANCE);
        token3.mint(USER1, INITIAL_BALANCE);
        token2.mint(USER2, INITIAL_BALANCE);
        token3.mint(USER2, INITIAL_BALANCE);
    }

    function mintAndApprove(address user, MockToken token, uint256 amount) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(pool), amount);
    }

    function addInitialLiquidity() internal {
        vm.startPrank(USER1);
        token0.approve(address(alm), INITIAL_LIQUIDITY);
        token1.approve(address(alm), INITIAL_LIQUIDITY);
        token2.approve(address(alm2), INITIAL_LIQUIDITY);
        token3.approve(address(alm2), INITIAL_LIQUIDITY);
        alm.depositLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, "");
        alm2.depositLiquidity(INITIAL_LIQUIDITY, INITIAL_LIQUIDITY, "");
        vm.stopPrank();
    }

    function calculateExpectedOutput(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        return (reserveOut * amountIn) / (reserveIn + amountIn);
    }
}
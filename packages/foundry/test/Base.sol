// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../contracts/Vault.sol";
import {ALM} from "../contracts/ALM.sol";
import {ALMRegistry} from "../contracts/ALMRegistry.sol";
import {Pool} from "../contracts/Pool.sol";
import {SovereignPoolConstructorArgs} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";
import {MockToken} from "../contracts/MockToken.sol";

contract Base is Test {
    Vault public vault;
    ALM public alm;
    ALMRegistry public almRegistry;
    Pool public pool;
    MockToken public token0;
    MockToken public token1;

    address public constant POOL_MANAGER = address(1);
    address public constant USER1 = address(2);
    address public constant USER2 = address(3);

    function setUp() public virtual {
        token0 = new MockToken("Token0", "TKN0");
        token1 = new MockToken("Token1", "TKN1");

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
        token0.mint(USER1, 1000e18);
        token1.mint(USER1, 1000e18);
        token0.mint(USER2, 1000e18);
        token1.mint(USER2, 1000e18);
    }

    function mintAndApprove(address user, MockToken token, uint256 amount) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(pool), amount);
    }

}
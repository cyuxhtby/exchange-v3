// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import "../contracts/MockTokens.sol";
import "../contracts/ALM.sol";
import "../contracts/Vault.sol";
import "../contracts/Pool.sol";
import "../contracts/PoolFactory.sol";
import "../contracts/ALMRegistry.sol";
import "./DeployHelpers.s.sol";

contract Deploy is ScaffoldETHDeploy {
    error InvalidPrivateKey(string);

    MockTokens public mockTokens;
    PoolFactory public poolFactory;
    Vault public vault;
    ALMRegistry public registry;

    struct PoolInfo {
        address pool;
        address alm;
    }

    PoolInfo[] public deployedPools;

    function run() external {
        uint256 deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }

        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        deployContracts(deployer);

        vm.stopBroadcast();

        exportDeployments();
    }

    function deployContracts(address deployer) internal {
        mockTokens = new MockTokens();
        console.log("MockTokens deployed at:", address(mockTokens));

        string[8] memory symbols = ["DAI", "USDC", "USDT", "WETH", "WBTC", "UNI", "LINK", "AAVE"];
        uint256 initialMint = 1000000 * 10**18; // 1 mill
        for(uint i = 0; i < symbols.length; i++) {
            mockTokens.mint(symbols[i], deployer, initialMint);
            console.log(symbols[i], "minted, address:", mockTokens.getTokenAddress(symbols[i]));
        }

        poolFactory = new PoolFactory();
        console.log("PoolFactory deployed at:", address(poolFactory));

        vault = new Vault();
        console.log("Vault deployed at:", address(vault));

        deployPoolAndALM("DAI", "USDC");
        deployPoolAndALM("WETH", "USDC");
        deployPoolAndALM("WBTC", "USDT");

        registry = new ALMRegistry();
        console.log("ALMRegistry deployed at: ", address(registry));
    }

    function deployPoolAndALM(string memory token0Symbol, string memory token1Symbol) internal {
        address token0 = mockTokens.getTokenAddress(token0Symbol);
        address token1 = mockTokens.getTokenAddress(token1Symbol);

        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: token0,
            token1: token1,
            sovereignVault: address(vault),
            verifierModule: address(this),
            protocolFactory: address(this),
            poolManager: address(this),
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            defaultSwapFeeBips: 30 // 0.3% fee
        });

        bytes memory constructorArgs = abi.encode(args);
        address pool = poolFactory.deploy(bytes32(0), constructorArgs);
        console.log(string.concat(token0Symbol, "-", token1Symbol, " Pool deployed at: "), pool);

        ALM alm = new ALM(pool, address(vault), address(registry));
        console.log(string.concat(token0Symbol, "-", token1Symbol, " ALM deployed at: "), address(alm));

        deployedPools.push(PoolInfo(pool, address(alm)));
    }
}
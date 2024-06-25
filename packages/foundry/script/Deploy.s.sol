// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import "../contracts/Pool.sol";
import "../contracts/MockTokens.sol";
import "./DeployHelpers.s.sol";

contract Deploy is ScaffoldETHDeploy {
    error InvalidPrivateKey(string);

    function run() external {
        uint256 deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }

        vm.startBroadcast(deployerPrivateKey);

         MockTokens mockTokens = new MockTokens();

        address deployer = vm.addr(deployerPrivateKey);
        uint256 initialMint = 1000000 * 10**18;
        
        string[8] memory symbols = ["DAI", "USDC", "USDT", "WETH", "WBTC", "UNI", "LINK", "AAVE"];
        for(uint i = 0; i < symbols.length; i++) {
            mockTokens.mint(symbols[i], deployer, initialMint);
            console.logString(string.concat(
                symbols[i], " deployed at: ", 
                vm.toString(mockTokens.getTokenAddress(symbols[i]))
            ));
        }
        console.logString(string.concat("MockTokens deployed at: ", vm.toString(address(mockTokens))));

        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: 0x68B1D87F95878fE05B998F19b66F4baba5De1aed,
            token1: 0x3Aa5ebB10DC797CAC828524e59A333d0A371443c,
            sovereignVault: address(0),
            verifierModule: address(0),
            protocolFactory: address(this),
            poolManager: address(this),
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            defaultSwapFeeBips: 0
        });

        Pool pool = new Pool(args);
        console.logString(
            string.concat(
                "Pool deployed at: ", vm.toString(address(pool))
            )
        );

        vm.stopBroadcast();

        exportDeployments();
    }
}
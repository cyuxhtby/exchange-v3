//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// import "../contracts/YourContract.sol";
import "../contracts/MockToken.sol";
import "../contracts/Pool.sol"; 
import "./DeployHelpers.s.sol";

contract DeployScript is ScaffoldETHDeploy {
    error InvalidPrivateKey(string);

    function run() external {
        uint256 deployerPrivateKey = setupLocalhostEnv();
        if (deployerPrivateKey == 0) {
            revert InvalidPrivateKey(
                "You don't have a deployer account. Make sure you have set DEPLOYER_PRIVATE_KEY in .env or use `yarn generate` to generate a new random account"
            );
        }
        vm.startBroadcast(deployerPrivateKey);

        YourContract yourContract =
            new YourContract(vm.addr(deployerPrivateKey));
        console.logString(
            string.concat(
                "YourContract deployed at: ", vm.toString(address(yourContract))
            )
        );

        MockToken mockToken = 
            new MockToken("Token1", "TKN1");
        console.logString(
            string.concat(
                "MockToken deployed at: ", vm.toString(address(mockToken))
            )
        );

        Pool pool = 
            new Pool();
        console.logString(
            string.concat(
                "Pool deployed at: ", vm.toString(address(pool))
            )
        );
         vm.stopBroadcast();

        /**
         * This function generates the file containing the contracts Abi definitions.
         * These definitions are used to derive the types needed in the custom scaffold-eth hooks, for example.
         * This function should be called last.
         */
        exportDeployments();
    }

    function test() public {}
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPoolDeployer} from "@valantislabs/contracts/protocol-factory/interfaces/IPoolDeployer.sol";

import {Pool} from "./Pool.sol";
import {SovereignPoolConstructorArgs} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";

contract PoolFactory is IPoolDeployer {
     /************************************************
     *  STORAGE
     ***********************************************/

    /**
        @notice Nonce used to derive unique CREATE2 salts. 
     */
    uint256 public nonce;

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function deploy(bytes32, bytes calldata _constructorArgs) external override returns (address deployment) {
        SovereignPoolConstructorArgs memory args = abi.decode(_constructorArgs, (SovereignPoolConstructorArgs));

        // Salt to trigger a create2 deployment,
        // as create is prone to re-org attacks
        bytes32 salt = keccak256(abi.encode(nonce, block.chainid, _constructorArgs));
        deployment = address(new Pool{ salt: salt }(args));

        nonce++;
    }
}
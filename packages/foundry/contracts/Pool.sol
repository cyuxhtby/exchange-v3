// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SovereignPool} from "@valantislabs/contracts/pools/SovereignPool.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {SovereignPoolConstructorArgs} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";

contract Pool is SovereignPool {

        SovereignPoolConstructorArgs args = SovereignPoolConstructorArgs({
            token0: address(this),
            token1: address(this),
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

    constructor() SovereignPool(args){}

}
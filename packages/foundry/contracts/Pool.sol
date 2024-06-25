// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SovereignPool} from "@valantislabs/contracts/pools/SovereignPool.sol";
import {SovereignPoolConstructorArgs} from "@valantislabs/contracts/pools/structs/SovereignPoolStructs.sol";

contract Pool is SovereignPool {

    constructor(SovereignPoolConstructorArgs memory args) SovereignPool(args) {}

}
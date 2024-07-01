// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19; 

contract ALMRegistry {
    mapping(bytes32 => address) public almForTokenPair;

    function registerALM(address token0, address token1, address alm) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        almForTokenPair[key] = alm;
    }

    function getALM(address token0, address token1) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return almForTokenPair[key];
    }
}

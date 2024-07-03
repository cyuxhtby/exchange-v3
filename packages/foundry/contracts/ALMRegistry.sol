// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ALMRegistry {
    mapping(bytes32 => address) public almForTokenPair;
    mapping(address => address[]) public connectedTokens;

    function registerALM(address token0, address token1, address alm) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        almForTokenPair[key] = alm;

        if (!_isConnected(token0, token1)) {
            connectedTokens[token0].push(token1);
            connectedTokens[token1].push(token0);
        }
    }

    function getALM(address token0, address token1) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return almForTokenPair[key];
    }

    function getConnectedTokens(address token) external view returns (address[] memory) {
        return connectedTokens[token];
    }

    function _isConnected(address token0, address token1) internal view returns (bool) {
        address[] memory connected = connectedTokens[token0];
        for (uint i = 0; i < connected.length; i++) {
            if (connected[i] == token1) {
                return true;
            }
        }
        return false;
    }

    function getPoolForTokenPair(address token0, address token1) external view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return almForTokenPair[key];
    }
}
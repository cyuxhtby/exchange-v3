// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTokens {
    struct TokenInfo {
        string name;
        string symbol;
        uint8 decimals;
        address tokenAddress;
    }

    TokenInfo[] public tokens;
    mapping(string => uint256) public symbolToIndex;

    constructor() {
        _createToken("Dai Stablecoin", "DAI", 18);
        _createToken("USD Coin", "USDC", 6);
        _createToken("Tether USD", "USDT", 6);
        _createToken("Wrapped Ether", "WETH", 18);
        _createToken("Wrapped Bitcoin", "WBTC", 8);
        _createToken("Uniswap", "UNI", 18);
        _createToken("ChainLink Token", "LINK", 18);
        _createToken("Aave Token", "AAVE", 18);
    }

    function _createToken(string memory name, string memory symbol, uint8 decimals) internal {
        MockToken newToken = new MockToken(name, symbol, decimals);
        tokens.push(TokenInfo(name, symbol, decimals, address(newToken)));
        symbolToIndex[symbol] = tokens.length - 1;
    }

    function mint(string memory symbol, address to, uint256 amount) external {
        require(symbolToIndex[symbol] < tokens.length, "Token does not exist");
        MockToken(tokens[symbolToIndex[symbol]].tokenAddress).mint(to, amount);
    }

    function getTokenAddress(string memory symbol) external view returns (address) {
        require(symbolToIndex[symbol] < tokens.length, "Token does not exist");
        return tokens[symbolToIndex[symbol]].tokenAddress;
    }

    function getTokenCount() external view returns (uint256) {
        return tokens.length;
    }
}

contract MockToken is ERC20 {
    address public immutable factory;
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        factory = msg.sender;
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == factory, "Only factory can mint");
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISovereignVaultMinimal} from "@valantislabs/contracts/pools/interfaces/ISovereignVaultMinimal.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @dev sources liquidity from new pools and does not currently support other liquidity sources or native yield strategies
contract Vault is ISovereignVaultMinimal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error SovereignVault__getReservesForPool_invalidPool();
    error SovereignVault__claimPoolManagerFees_onlyPool();
    error SovereignVault__quoteToRecipient_onlyALM();
    error SovereignVault__addPoolTokens_tokensAlreadySet();
    error SovereignVault__updateReserves_arrayLengthMismatch();
    error SovereignVault__withdraw_insufficientReserves();
    error SovereignVault__multiHopSwap_invalidPath();
    error SovereignVault__verifyPath_arrayLengthMismatch();

    address public alm;

    struct Reserve {
        uint256 amount;
    }

    mapping(address => mapping(address => Reserve)) private poolReserves; // pool => token => reserve
    mapping(address => address[]) private poolTokens;
    mapping(address => uint256) private poolManagerFees0;
    mapping(address => uint256) private poolManagerFees1;
    mapping(address => bool) private tokenExists;

    address[] public tokenList;

    function setALM(address _alm) external {
        alm = _alm;
    }

    function addPoolTokens(address _pool, address[] memory _tokens) external {
        if (poolTokens[_pool].length != 0) revert SovereignVault__addPoolTokens_tokensAlreadySet();
        poolTokens[_pool] = _tokens;
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!tokenExists[_tokens[i]]) {
                tokenList.push(_tokens[i]);
                tokenExists[_tokens[i]] = true;
            }
        }
    }

    function updateReserves(address _pool, address[] calldata _tokens, uint256[] calldata _amounts) external {
        if (_tokens.length != _amounts.length) revert SovereignVault__updateReserves_arrayLengthMismatch();
        for (uint256 i = 0; i < _tokens.length; i++) {
            poolReserves[_pool][_tokens[i]].amount += _amounts[i];
        }
    }

    function getTokensForPool(address _pool) public view override returns (address[] memory tokens) {
        return poolTokens[_pool];
    }

    function getReservesForPool(address _pool, address[] calldata _tokens) external view override returns (uint256[] memory) {
        if (poolTokens[_pool].length == 0) revert SovereignVault__getReservesForPool_invalidPool();

        uint256[] memory reserves = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            reserves[i] = poolReserves[_pool][_tokens[i]].amount;
        }

        return reserves;
    }

    function quoteToRecipient(bool _isZeroToOne, uint256 _amount, address) external {
        if (msg.sender != alm) revert SovereignVault__quoteToRecipient_onlyALM();

        if (_amount == 0) return;

        address token = _isZeroToOne ? poolTokens[alm][1] : poolTokens[alm][0];
        IERC20(token).safeApprove(alm, _amount);
    }

    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external override {
        if (poolTokens[msg.sender].length == 0) revert SovereignVault__claimPoolManagerFees_onlyPool();

        IERC20(poolTokens[msg.sender][0]).safeTransfer(msg.sender, _feePoolManager0);
        IERC20(poolTokens[msg.sender][1]).safeTransfer(msg.sender, _feePoolManager1);
    }

    function deposit(address _pool, address _token, uint256 _amount) external nonReentrant {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        poolReserves[_pool][_token].amount += _amount;
    }

    function withdraw(address _pool, address _token, uint256 _amount) external nonReentrant {
        if (poolReserves[_pool][_token].amount < _amount) revert SovereignVault__withdraw_insufficientReserves();
        poolReserves[_pool][_token].amount -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function verifyPath(address[] calldata path, uint256[] calldata amounts) public view returns (bool) {
        if (path.length != amounts.length) revert SovereignVault__verifyPath_arrayLengthMismatch();

        for (uint256 i = 0; i < path.length - 1; i++) {
            address[] memory tokens = poolTokens[path[i]];
            bool tokenSupported = false;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (tokens[j] == path[i + 1]) {
                    tokenSupported = true;
                    break;
                }
            }
            if (!tokenSupported) {
                return false;
            }
        }
        return true;
    }

    function executeMultiHopSwap(address[] calldata path, uint256[] calldata amounts, address recipient) external nonReentrant {
        if (!verifyPath(path, amounts)) revert SovereignVault__multiHopSwap_invalidPath();

        for (uint256 i = 0; i < path.length - 1; i++) {
            address pool = path[i];
            address tokenIn = path[i];
            address tokenOut = path[i + 1];
            uint256 amountIn = amounts[i];
            uint256 amountOut = amounts[i + 1];

            if (poolReserves[pool][tokenIn].amount < amountIn) revert SovereignVault__withdraw_insufficientReserves();
            if (poolReserves[pool][tokenOut].amount < amountOut) revert SovereignVault__withdraw_insufficientReserves();

            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
            IERC20(tokenOut).safeTransfer(recipient, amountOut);

            poolReserves[pool][tokenIn].amount -= amountIn;
            poolReserves[pool][tokenOut].amount += amountOut;
        }
    }
}
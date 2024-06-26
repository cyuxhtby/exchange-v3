// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISovereignVaultMinimal} from "@valantislabs/contracts/pools/interfaces/ISovereignVaultMinimal.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {ISovereignALM} from "@valantislabs/contracts/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantislabs/contracts/ALM/structs/SovereignALMStructs.sol";

contract Vault is ISovereignVaultMinimal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error SovereignVault__poolAlreadyAdded();
    error SovereignVault__invalidVaultForPool();
    error SovereignVault__invalidTokens();
    error SovereignVault__invalidPool();
    error SovereignVault__onlyPoolManager();
    error SovereignVault__onlyActivePool();
    error SovereignVault__insufficientReserves();
    error SovereignVault__invalidPath();
    error SovereignVault__swapExpired();
    error SovereignVault__slippageExceeded();

    struct PoolInfo {
        address[] tokens;
        address alm;
        address poolManager;
        bool isActive;
    }

    mapping(address pool => PoolInfo) public pools;
    mapping(address pool => mapping(address token => uint256 amount)) public poolReserves;
    mapping(address token0 => mapping(address token1 => address pool)) private tokenPairToPool;

    event PoolRegistered(address indexed pool, address[] tokens, address alm, address poolManager);
    event PoolDeactivated(address indexed pool);
    event ReservesUpdated(address indexed pool, address indexed token, uint256 amount);
    event PoolManagerFeesClaimed(address indexed pool, uint256 feePoolManager0, uint256 feePoolManager1);
    event MutliHopSwap(address indexed sender, address[] path, uint256 amountIn, uint256 amountOut);

    modifier onlyPoolManager(address _pool) {
        if (msg.sender != pools[_pool].poolManager) revert SovereignVault__onlyPoolManager();
        _;
    }

    modifier onlyActivePool() {
        if (!pools[msg.sender].isActive) revert SovereignVault__onlyActivePool();
        _;
    }

    function registerPool(address _pool, address[] memory _tokens, address _alm) external {
        if (pools[_pool].isActive) revert SovereignVault__poolAlreadyAdded();
        
        ISovereignPool pool = ISovereignPool(_pool);
        
        if (pool.sovereignVault() != address(this)) revert SovereignVault__invalidVaultForPool();
        
        if (_tokens.length != 2 || _tokens[0] != pool.token0() || _tokens[1] != pool.token1()) {
            revert SovereignVault__invalidTokens();
        }

        pools[_pool] = PoolInfo({
            tokens: _tokens,
            alm: _alm,
            poolManager: pool.poolManager(),
            isActive: true
        });

        tokenPairToPool[_tokens[0]][_tokens[1]] = _pool;
        tokenPairToPool[_tokens[1]][_tokens[0]] = _pool;
        emit PoolRegistered(_pool, _tokens, _alm, pool.poolManager());
    }

    function deactivatePool(address _pool) external onlyPoolManager(_pool) {
        if (!pools[_pool].isActive) revert SovereignVault__invalidPool();
        pools[_pool].isActive = false;
        emit PoolDeactivated(_pool);
    }

    function getTokensForPool(address _pool) public view override returns (address[] memory) {
        if (!pools[_pool].isActive) revert SovereignVault__invalidPool();
        return pools[_pool].tokens;
    }

    function getReservesForPool(address _pool, address[] calldata _tokens) external view override returns (uint256[] memory) {
        if (!pools[_pool].isActive) revert SovereignVault__invalidPool();
        uint256[] memory reserves = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            reserves[i] = poolReserves[_pool][_tokens[i]];
        }
        return reserves;
    }

    function updateReserves(address _token, uint256 _amount) external onlyActivePool {
        poolReserves[msg.sender][_token] = _amount;
        emit ReservesUpdated(msg.sender, _token, _amount);
    }

    function approveTokens(address _token, uint256 _amount) external onlyActivePool {
        IERC20(_token).safeApprove(msg.sender, _amount);
    }

    function deposit(address _token, uint256 _amount) external onlyActivePool {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        poolReserves[msg.sender][_token] += _amount;
        emit ReservesUpdated(msg.sender, _token, poolReserves[msg.sender][_token]);
    }

    function withdraw(address _token, uint256 _amount) external onlyActivePool {
        if (poolReserves[msg.sender][_token] < _amount) revert SovereignVault__insufficientReserves();
        poolReserves[msg.sender][_token] -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit ReservesUpdated(msg.sender, _token, poolReserves[msg.sender][_token]);
    }

    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external override onlyActivePool {
        address[] memory poolTokens = pools[msg.sender].tokens;
        if (poolTokens.length < 2) revert SovereignVault__invalidPool();
        
        IERC20(poolTokens[0]).safeTransfer(msg.sender, _feePoolManager0);
        IERC20(poolTokens[1]).safeTransfer(msg.sender, _feePoolManager1);
        emit PoolManagerFeesClaimed(msg.sender, _feePoolManager0, _feePoolManager1);
    }

    function executeMultiHopSwap(
        address[] calldata _path,
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint256 deadline
    ) external nonReentrant {
        if (block.timestamp > deadline) revert SovereignVault__swapExpired();
        if (_path.length < 2) revert SovereignVault__invalidPath();

        // Transfers from user to vault, user must have approved this contract first.
        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _amountIn);

        uint256 amountOut = _amountIn;
        for (uint256 i = 0; i < _path.length - 1; i++) {
            address pool = _getPoolForTokenPair(_path[i], _path[i + 1]);
            if (!pools[pool].isActive) revert SovereignVault__invalidPool();

            amountOut = _swapInPool(pool, _path[i], _path[i + 1], amountOut); 
        }

        if (amountOut < _minAmountOut) revert SovereignVault__slippageExceeded();

        IERC20(_path[_path.length - 1]).safeTransfer(msg.sender, amountOut);
        emit MutliHopSwap(msg.sender, _path, _amountIn, amountOut);
    }

    function _swapInPool(address _pool, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        ALMLiquidityQuoteInput memory quoteInput = ALMLiquidityQuoteInput({
            isZeroToOne: _tokenIn < _tokenOut,
            amountInMinusFee: _amountIn,
            feeInBips: 0, // Fees are handled in the ALM
            sender: address(this),
            recipient: address(this),
            tokenOutSwap: _tokenOut
        });

        ALMLiquidityQuote memory quote = ISovereignALM(pools[_pool].alm).getLiquidityQuote(quoteInput, "", "");

        poolReserves[_pool][_tokenIn] += quote.amountInFilled;
        poolReserves[_pool][_tokenOut] -= quote.amountOut;

        emit ReservesUpdated(_pool, _tokenIn, poolReserves[_pool][_tokenIn]);
        emit ReservesUpdated(_pool, _tokenOut, poolReserves[_pool][_tokenOut]);

        return quote.amountOut;
    }
    
    function _getPoolForTokenPair(address _token0, address _token1) internal view returns (address) {
        address pool = tokenPairToPool[_token0][_token1];
        if (pool == address(0)) revert SovereignVault__invalidPool();
        return pool;
    }
}

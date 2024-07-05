// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISovereignVaultMinimal} from "@valantislabs/contracts/pools/interfaces/ISovereignVaultMinimal.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {ISovereignALM} from "@valantislabs/contracts/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantislabs/contracts/ALM/structs/SovereignALMStructs.sol";
import {console} from "forge-std/Test.sol";


/// @notice Liquidity stored here is pool specific, this vault does not currently allow for liquidity to be shared between pools
contract Vault is ISovereignVaultMinimal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error SovereignVault__poolAlreadyAdded();
    error SovereignVault__invalidVaultForPool();
    error SovereignVault__invalidTokens();
    error SovereignVault__invalidPool();
    error SovereignVault__onlyPoolManager();
    error SovereignVault__onlyALM();    
    error SovereignVault__insufficientReserves();
    error SovereignVault__invalidPath();
    error SovereignVault__swapExpired();
    error SovereignVault__slippageExceeded();
    error SovereignVault__inputLengthsMismatch();

    struct PoolData {
        address[] tokens;
        address alm;
        address poolManager;
        bool isActive;
    }

    struct ALMData {
        address pool;
        address[] tokens;
        bool isActive;
    }

    mapping(address pool => PoolData) public pools;
    mapping(address alm => ALMData) public alms;
    mapping(address pool => mapping(address token => uint256 amount)) public poolReserves;
    mapping(address token0 => mapping(address token1 => address pool)) private tokenPairToPool;

    event PoolRegistered(address indexed pool, address[] tokens, address alm, address poolManager);
    event PoolDeactivated(address indexed pool);
    event ReservesUpdated(address indexed pool, address indexed token, uint256 amount);
    event PoolManagerFeesClaimed(address indexed pool, uint256 feePoolManager0, uint256 feePoolManager1);

    modifier onlyPoolManager(address _pool) {
        if (msg.sender != pools[_pool].poolManager) revert SovereignVault__onlyPoolManager();
        _;
    }

    // consider renaming this to onlyValidALM()
    modifier onlyALM() {
        if (!alms[msg.sender].isActive) revert SovereignVault__onlyALM();
        _;
    }


    function registerPool(address _pool, address[] memory _tokens, address _alm) external {
        if (pools[_pool].isActive) revert SovereignVault__poolAlreadyAdded();
        
        ISovereignPool pool = ISovereignPool(_pool);
        
        if (pool.sovereignVault() != address(this)) revert SovereignVault__invalidVaultForPool();
        
        if (_tokens.length != 2 || _tokens[0] != pool.token0() || _tokens[1] != pool.token1()) {
            revert SovereignVault__invalidTokens();
        }

        pools[_pool] = PoolData({
            tokens: _tokens,
            alm: _alm,
            poolManager: pool.poolManager(),
            isActive: true
        });

        alms[_alm] = ALMData({
            pool: _pool,
            tokens: _tokens,
            isActive: true
        });

        tokenPairToPool[_tokens[0]][_tokens[1]] = _pool;
        tokenPairToPool[_tokens[1]][_tokens[0]] = _pool;

        // Approve maximum allowance for both tokens
        /// @notice Not ideal !
        IERC20(_tokens[0]).approve(_pool, type(uint256).max);
        IERC20(_tokens[1]).approve(_pool, type(uint256).max);

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

    function updateReserves(address _pool, address[] calldata _tokens, uint256[] calldata _amounts) external onlyALM() {
        if (_tokens.length != _amounts.length) revert SovereignVault__inputLengthsMismatch();
        for (uint256 i = 0; i < _tokens.length; i++) {
            poolReserves[_pool][_tokens[i]] = _amounts[i];
            emit ReservesUpdated(_pool, _tokens[i], _amounts[i]);
        }
    }

    function deposit(address _pool, address _token, uint256 _amount) external onlyALM() nonReentrant() {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        poolReserves[_pool][_token] += _amount;
        emit ReservesUpdated(_pool, _token, poolReserves[_pool][_token]);
    }

    function withdraw(address _pool, address _token, uint256 _amount) external onlyALM() nonReentrant() {
        if (poolReserves[_pool][_token] < _amount) revert SovereignVault__insufficientReserves();
        poolReserves[_pool][_token] -= _amount;
        IERC20(_token).safeTransfer(msg.sender, _amount);
        emit ReservesUpdated(_pool, _token, poolReserves[_pool][_token]);
    }

    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external override onlyALM() nonReentrant {
        address[] memory poolTokens = pools[msg.sender].tokens;
        if (poolTokens.length < 2) revert SovereignVault__invalidPool();
        
        IERC20(poolTokens[0]).safeTransfer(msg.sender, _feePoolManager0);
        IERC20(poolTokens[1]).safeTransfer(msg.sender, _feePoolManager1);
        emit PoolManagerFeesClaimed(msg.sender, _feePoolManager0, _feePoolManager1);
    }
    
    function _getPoolForTokenPair(address _token0, address _token1) internal view returns (address) {
        address pool = tokenPairToPool[_token0][_token1];
        if (pool == address(0)) revert SovereignVault__invalidPool();
        return pool;
    }

    function approvePoolAllowance(address _tokenOut, uint256 _amount) external onlyALM {
        ALMData memory almData = alms[msg.sender];

        uint256 currentAllowance = IERC20(_tokenOut).allowance(address(this), almData.pool);
        if (currentAllowance > 0) {
            IERC20(_tokenOut).safeApprove(almData.pool, 0);
        }

        IERC20(_tokenOut).safeApprove(almData.pool, _amount);
    }

    function approvePool(address _pool, address _token, uint256 _amount) external {
        require(pools[_pool].isActive, "Pool not active");
        require(msg.sender == pools[_pool].alm, "Only ALM can approve");
        IERC20(_token).approve(_pool, type(uint256).max);
        IERC20(_token).approve(_pool, type(uint256).max); 
    }

    function approvePoolForSwap(address _token, uint256 _amount) external {
        require(pools[msg.sender].isActive || alms[msg.sender].isActive, "Only active pools or ALMs can call this function");
        address poolToApprove = pools[msg.sender].isActive ? msg.sender : alms[msg.sender].pool;
        IERC20(_token).approve(poolToApprove, type(uint256).max);
    }
}
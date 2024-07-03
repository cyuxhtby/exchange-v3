// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISovereignVault} from "./interfaces/ISovereignVault.sol";
import {ISovereignALM} from "@valantislabs/contracts/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantislabs/contracts/ALM/structs/SovereignALMStructs.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";
import {ISovereignPoolSwapCallback} from "@valantislabs/contracts/pools/interfaces/ISovereignPoolSwapCallback.sol";
import {ALMRegistry} from "./ALMRegistry.sol";

import {console} from "forge-std/Test.sol";

contract ALM is ISovereignALM, ISovereignPoolSwapCallback {
    using SafeERC20 for IERC20;

    error SovereignALM__onlyPool();
    error SovereignALM__depositLiquidity_zeroTotalDepositAmount();
    error SovereignALM__depositLiquidity_notPermissioned();
    error SovereignALM__depositLiquidity_vaultNotSet();
    error SovereignALM__withdrawLiquidity_vaultNotSet();
    error SovereignALM__withdrawLiquidity_invalidRecipient();
    error SovereignALM__withdrawLiquidity_insufficientReserves();
    error SovereignALM__findNextALM_noALMFound();
    error SovereignALM__depositLiquidity_invalidRatio();
    error SovereignALM__depositLiquidity_bothAmountsMustBeNonZero();
    error SovereignALM__withdrawLiquidity_invalidRatio();   

    event LiquidityDeposited(
        address indexed user, uint256 amount0, uint256 amount1
    );
    event LiquidityWithdrawn(
        address indexed user,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1
    );
    event SwapCallback(bool isZeroToOne, uint256 amountIn, uint256 amountOut);

    struct SwapPath {
        address[] path;
        uint256[] amounts;
    }

    mapping(address => SwapPath) private swapPaths;

    address public immutable pool;
    address public immutable vault;
    address public immutable registry;

    uint256 public fee0;
    uint256 public fee1;

    constructor(address _pool, address _vault, address _registry) {
        pool = _pool;
        vault = _vault;
        registry = _registry;
    }

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert SovereignALM__onlyPool();
        }
        _;
    }

    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory /*_verificationContext*/
    ) external returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        if (vault == address(0)) {
            revert SovereignALM__depositLiquidity_vaultNotSet();
        }
        if (_amount0 == 0 && _amount1 == 0) {
            revert SovereignALM__depositLiquidity_zeroTotalDepositAmount();
        }

        (address token0, address token1) = getPoolTokens();
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        uint256[] memory currentReserves = ISovereignVault(vault).getReservesForPool(pool, tokens);

        // Enforce deposit ratio for non zero reserves
        if (currentReserves[0] > 0 && currentReserves[1] > 0) {
            if (_amount0 * currentReserves[1] != _amount1 * currentReserves[0]) {
                revert SovereignALM__depositLiquidity_invalidRatio();
            }
        } else {
            if (_amount0 == 0 || _amount1 == 0) {
                revert SovereignALM__depositLiquidity_bothAmountsMustBeNonZero();
            }
        }

        if (_amount0 > 0) {
            IERC20(token0).safeTransferFrom(msg.sender, vault, _amount0);
        }
        if (_amount1 > 0) {
            IERC20(token1).safeTransferFrom(msg.sender, vault, _amount1);
        }

        uint256[] memory newReserves = ISovereignVault(vault).getReservesForPool(pool, tokens);
        newReserves[0] += _amount0;
        newReserves[1] += _amount1;
        ISovereignVault(vault).updateReserves(pool, tokens, newReserves);

        emit LiquidityDeposited(msg.sender, _amount0, _amount1);
        return (_amount0, _amount1);
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint256,
        uint256,
        address _recipient,
        bytes memory /*_verificationContext*/
    ) external {
        if (vault == address(0)) {
            revert SovereignALM__withdrawLiquidity_vaultNotSet();
        }
        if (_recipient == address(0)) {
            revert SovereignALM__withdrawLiquidity_invalidRecipient();
        }

        (address token0, address token1) = getPoolTokens();

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory currentReserves = ISovereignVault(vault).getReservesForPool(pool, tokens);

        if (currentReserves[0] < _amount0 || currentReserves[1] < _amount1) {
            revert SovereignALM__withdrawLiquidity_insufficientReserves();
        }

        if (_amount0 * currentReserves[1] != _amount1 * currentReserves[0]) {
            revert SovereignALM__withdrawLiquidity_invalidRatio();
        }

        uint256[] memory newReserves = new uint256[](2);
        newReserves[0] = currentReserves[0] - _amount0;
        newReserves[1] = currentReserves[1] - _amount1;
        ISovereignVault(vault).updateReserves(pool, tokens, newReserves);

        if (_amount0 > 0) {
            ISovereignVault(vault).withdraw(pool, token0, _amount0);
            IERC20(token0).safeTransfer(_recipient, _amount0);
        }
        if (_amount1 > 0) {
            ISovereignVault(vault).withdraw(pool, token1, _amount1);
            IERC20(token1).safeTransfer(_recipient, _amount1);
        }

        emit LiquidityWithdrawn(msg.sender, _recipient, _amount0, _amount1);
    }

    // Need to handle case of stack depth issues for very long swap paths
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes memory /*_externalContext*/,
        bytes memory /*_verifierData*/
    ) external override returns (ALMLiquidityQuote memory) {
        // Get the liquidity quote for the current pool
        ALMLiquidityQuote memory quote = _getLiquidityQuote(_almLiquidityQuoteInput);

        (address token0, address token1) = getPoolTokens();

        // Ensure allowance before any operations
        ensureAllowance(token0, quote.amountOut);
        ensureAllowance(token1, quote.amountOut);

        SwapPath storage swapPath = swapPaths[msg.sender];
        swapPath.path.push(_almLiquidityQuoteInput.isZeroToOne ? token0 : token1);
        swapPath.amounts.push(quote.amountInFilled);

        // If the tokenOutSwap is not part of the current pool's tokens, 
        // recursively get the liquidity quote of the next ALM.
        if (
            _almLiquidityQuoteInput.tokenOutSwap != address(token0)  &&
            _almLiquidityQuoteInput.tokenOutSwap != address(token1)
        ) {
            ISovereignALM nextALM = ISovereignALM(
                _findNextALM(_almLiquidityQuoteInput.tokenOutSwap)
            );

            bool isNextZeroToOne = (address(token1) == _almLiquidityQuoteInput.tokenOutSwap);

            ALMLiquidityQuoteInput memory nextLiquidityQuoteInput =
            ALMLiquidityQuoteInput({
                isZeroToOne: isNextZeroToOne,
                amountInMinusFee: quote.amountOut,
                feeInBips: _almLiquidityQuoteInput.feeInBips,
                sender: address(this),
                recipient: _almLiquidityQuoteInput.recipient,
                tokenOutSwap: _almLiquidityQuoteInput.tokenOutSwap
            });

            ALMLiquidityQuote memory nextQuote = nextALM.getLiquidityQuote(nextLiquidityQuoteInput, "", "");

            swapPath.path.push(_almLiquidityQuoteInput.tokenOutSwap);
            swapPath.amounts.push(nextQuote.amountOut);

            // Returns the final output amount and the initial input amount, 
            return ALMLiquidityQuote({
                isCallbackOnSwap: true,
                amountOut: nextQuote.amountOut,
                amountInFilled: quote.amountInFilled
            });
        } else {
            swapPath.path.push(_almLiquidityQuoteInput.tokenOutSwap);
            swapPath.amounts.push(quote.amountInFilled);
            return quote;
        }
    }

    function _getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput
    ) internal returns (ALMLiquidityQuote memory) {
        if (_almLiquidityQuoteInput.amountInMinusFee == 0) {
            return ALMLiquidityQuote(false, 0, 0);
        }

        (address token0, address token1) = getPoolTokens();
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory reserves = ISovereignVault(vault).getReservesForPool(pool, tokens);

        uint256 reserveIn = _almLiquidityQuoteInput.isZeroToOne ? reserves[0] : reserves[1];
        uint256 reserveOut = _almLiquidityQuoteInput.isZeroToOne ? reserves[1] : reserves[0];

        uint256 amountInWithFee = Math.mulDiv(
            _almLiquidityQuoteInput.amountInMinusFee,
            10000 + _almLiquidityQuoteInput.feeInBips,
            10000
        );
        uint256 amountOut = Math.mulDiv(
            reserveOut, amountInWithFee, reserveIn + amountInWithFee
        );

        uint256 fee = amountInWithFee - _almLiquidityQuoteInput.amountInMinusFee;
        if (_almLiquidityQuoteInput.isZeroToOne) {
            fee0 += fee;
        } else {
            fee1 += fee;
        }

        address tokenOut = _almLiquidityQuoteInput.isZeroToOne ? token1 : token0; 

        // YUH
        ISovereignVault(vault).approvePoolForSwap(tokenOut, amountOut);

        return ALMLiquidityQuote(
            true, amountOut, _almLiquidityQuoteInput.amountInMinusFee
        );
    }

    function _findNextALM(address _tokenOut) internal view returns (address) {
        (address token0, address token1) = getPoolTokens();
        address nextALM;

        // Check for direct connections first
        nextALM = ALMRegistry(registry).getALM(token1, _tokenOut);
        if (nextALM != address(0)) {
            console.log("Direct connection found from token1 to tokenOut");
            return nextALM;
        }

        nextALM = ALMRegistry(registry).getALM(token0, _tokenOut);
        if (nextALM != address(0)) {
            console.log("Direct connection found from token0 to tokenOut");
            return nextALM;
        }

        // If no direct connection, check connected tokens
        address[] memory connectedToToken1 = ALMRegistry(registry).getConnectedTokens(token1);
        for (uint i = 0; i < connectedToToken1.length; i++) {
            nextALM = ALMRegistry(registry).getALM(token1, connectedToToken1[i]);
            if (nextALM != address(0)) {
                console.log("Intermediate connection found from token1 to", connectedToToken1[i]);
                return nextALM;
            }
        }

        address[] memory connectedToToken0 = ALMRegistry(registry).getConnectedTokens(token0);
        for (uint i = 0; i < connectedToToken0.length; i++) {
            nextALM = ALMRegistry(registry).getALM(token0, connectedToToken0[i]);
            if (nextALM != address(0)) {
                console.log("Intermediate connection found from token0 to", connectedToToken0[i]);
                return nextALM;
            }
        }

        console.log("No connection found for tokens:", token0, token1, _tokenOut);
        revert SovereignALM__findNextALM_noALMFound();
    }

    function onSwapCallback(
        bool _isZeroToOne,
        uint256 _amountIn,
        uint256 _amountOut
    ) external override onlyPool {
        SwapPath storage swapPath = swapPaths[msg.sender];
        
        if (swapPath.path.length > 2) {
            _handleMultiHopSwap(swapPath, _amountOut);
        } else {
            _handleSingleHopSwap(_isZeroToOne, _amountIn, _amountOut);
        }

        delete swapPaths[msg.sender];
    }

function _handleMultiHopSwap(SwapPath storage pathInfo, uint256 finalAmountOut) internal {
    for (uint i = 0; i < pathInfo.path.length - 1; i++) {
        address poolAddress = ALMRegistry(registry).getPoolForTokenPair(pathInfo.path[i], pathInfo.path[i+1]);
        address[] memory tokens = new address[](2);
        tokens[0] = pathInfo.path[i];
        tokens[1] = pathInfo.path[i+1];
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = pathInfo.amounts[i];
        amounts[1] = pathInfo.amounts[i+1];
        ISovereignVault(vault).updateReserves(poolAddress, tokens, amounts);
    }

    // Final transfer from the vault to the user
    address finalTokenOut = pathInfo.path[pathInfo.path.length - 1];
    ISovereignVault(vault).withdraw(pool, finalTokenOut, finalAmountOut);
    IERC20(finalTokenOut).safeTransfer(msg.sender, finalAmountOut);
}

function _handleSingleHopSwap(bool _isZeroToOne, uint256 _amountIn, uint256 _amountOut) internal {
    (address token0, address token1) = getPoolTokens();
    address[] memory tokens = new address[](2);
    tokens[0] = token0;
    tokens[1] = token1;

    uint256[] memory newReserves = new uint256[](2);
    uint256[] memory oldReserves = ISovereignVault(vault).getReservesForPool(pool, tokens);

    if (_isZeroToOne) {
        newReserves[0] = oldReserves[0] + _amountIn;
        newReserves[1] = oldReserves[1] - _amountOut;
    } else {
        newReserves[0] = oldReserves[0] - _amountOut;
        newReserves[1] = oldReserves[1] + _amountIn;
    }

    ISovereignVault(vault).updateReserves(pool, tokens, newReserves);

    emit SwapCallback(_isZeroToOne, _amountIn, _amountOut);
}

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) external override onlyPool {}

    function sovereignPoolSwapCallback(
        address _tokenIn,
        uint256 _amountInUsed,
        bytes calldata _swapCallbackContext
    ) external override onlyPool {}

    function getPoolTokens()
        public
        view
        returns (address token0, address token1)
    {
        (token0, token1) = (ISovereignPool(pool).token0(), ISovereignPool(pool).token1());
    }
        
    function ensureAllowance(address _tokenOut, uint256 _amount) internal {
        uint256 currentAllowance = IERC20(_tokenOut).allowance(address(this), vault);
        if (currentAllowance < _amount) {
            ISovereignVault(vault).approvePoolAllowance(_tokenOut, _amount);
        }
    }


}

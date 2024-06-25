// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISovereignVault} from "./interfaces/ISovereignVault.sol";
import {ISovereignALM} from "@valantislabs/contracts/ALM/interfaces/ISovereignALM.sol";
import {ALMLiquidityQuoteInput, ALMLiquidityQuote} from "@valantislabs/contracts/ALM/structs/SovereignALMStructs.sol";
import {ISovereignPool} from "@valantislabs/contracts/pools/interfaces/ISovereignPool.sol";

contract ALM is ISovereignALM {
    using SafeERC20 for IERC20;

    error SovereignALM__onlyPool();
    error SovereignALM__depositLiquidity_zeroTotalDepositAmount();
    error SovereignALM__depositLiquidity_notPermissioned();

    event LogSwapCallback(bool isZeroToOne);

    address public immutable pool;
    address public immutable vault;

    uint256 public fee0;
    uint256 public fee1;

    constructor(address _pool, address _vault) {
        pool = _pool;
        vault = _vault;
    }

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert SovereignALM__onlyPool();
        }
        _;
    }

    function depositLiquidity(uint256 _amount0, uint256 _amount1, bytes memory _verificationContext)
        external
        returns (uint256 amount0Deposited, uint256 amount1Deposited)
    {
        (amount0Deposited, amount1Deposited) = ISovereignPool(pool).depositLiquidity(
            _amount0, _amount1, msg.sender, _verificationContext, abi.encode(msg.sender)
        );
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint256,
        uint256,
        address _recipient,
        bytes memory _verificationContext
    ) external {
        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, msg.sender, _recipient, _verificationContext);
    }

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuotePoolInput,
        bytes calldata,
        bytes calldata
    ) external override onlyPool returns (ALMLiquidityQuote memory) {
        if (_almLiquidityQuotePoolInput.amountInMinusFee == 0) {
            ALMLiquidityQuote memory emptyQuote;
            return emptyQuote;
        }

        uint256 reserveIn;
        uint256 reserveOut;

        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        reserveIn = _almLiquidityQuotePoolInput.isZeroToOne ? reserve0 : reserve1;
        reserveOut = _almLiquidityQuotePoolInput.isZeroToOne ? reserve1 : reserve0;

        uint256 amountOutExpected =
            reserveOut - Math.mulDiv(reserve0, reserve1, reserveIn + _almLiquidityQuotePoolInput.amountInMinusFee);

        ALMLiquidityQuote memory almLiquidityQuote =
            ALMLiquidityQuote(false, amountOutExpected, _almLiquidityQuotePoolInput.amountInMinusFee);

        uint256 feeMax = Math.mulDiv(
            _almLiquidityQuotePoolInput.amountInMinusFee,
            1e4 + _almLiquidityQuotePoolInput.feeInBips,
            1e4,
            Math.Rounding.Up
        ) - _almLiquidityQuotePoolInput.amountInMinusFee;
        uint256 feeAmount = feeMax - Math.mulDiv(feeMax, ISovereignPool(pool).poolManagerFeeBips(), 1e4);
        _almLiquidityQuotePoolInput.isZeroToOne ? (fee0 += feeAmount) : (fee1 += feeAmount);

        return almLiquidityQuote;
    }

    function onDepositLiquidityCallback(uint256 _amount0, uint256 _amount1, bytes memory _data)
        external
        override
        onlyPool
    {
        address user = abi.decode(_data, (address));

        (address token0, address token1) = (ISovereignPool(pool).token0(), ISovereignPool(pool).token1());

        // Transfer tokens to vault
        if (_amount0 > 0) {
            IERC20(token0).safeTransferFrom(user, vault, _amount0);
        }

        if (_amount1 > 0) {
            IERC20(token1).safeTransferFrom(user, vault, _amount1);
        }
        
        // Update vault reserves
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amount0;
        amounts[1] = _amount1;

        ISovereignVault(vault).updateReserves(pool, tokens, amounts);
    }

    function onSwapCallback(bool _isZeroToOne, uint256, uint256) external override onlyPool {
        emit LogSwapCallback(_isZeroToOne);
    }
}
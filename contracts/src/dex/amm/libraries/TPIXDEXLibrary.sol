// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../interfaces/ITPIXDEXPair.sol';
import '../interfaces/ITPIXDEXFactory.sol';

/**
 * @title TPIXDEXLibrary
 * @notice Helper functions สำหรับคำนวณ AMM (quote/getAmountOut/getAmountsOut ฯลฯ)
 *
 * @dev FIX สำคัญจาก skeleton เดิม (Thaiprompt-Affiliate):
 *      pairFor() เดิมเป็น CREATE2 prediction ที่ hardcode init-code-hash ของ
 *      Uniswap V2 คลาสสิก (96e8ac42...) ซึ่งไม่ตรงกับ creationCode ของ
 *      TPIXDEXPair (OZ ERC20 base) → router คำนวณ pair address ผิด → swap พังทุกครั้ง
 *      แก้เป็น internal view ที่อ่าน getPair() จาก factory ตรงๆ — ไม่มี hash ให้
 *      maintain, ถูกต้องเสมอไม่ว่า Pair bytecode จะเปลี่ยนยังไง
 *      (ทุกจุดที่ router เรียกเป็น state-changing/view อยู่แล้ว view จึงพอ)
 */
library TPIXDEXLibrary {
    /// @notice เรียงคู่ token ตาม address (token0 < token1) — ลำดับเดียวกับใน pair
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'TPIXDEXLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'TPIXDEXLibrary: ZERO_ADDRESS');
    }

    /// @notice หา pair address จาก factory registry (ไม่ใช้ CREATE2 prediction — ดู @dev ด้านบน)
    function pairFor(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = ITPIXDEXFactory(factory).getPair(token0, token1);
        require(pair != address(0), 'TPIXDEXLibrary: PAIR_NOT_FOUND');
    }

    /// @notice ดึง reserves ของคู่ token เรียงตามลำดับ (tokenA, tokenB) ที่ส่งเข้ามา
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ITPIXDEXPair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @notice แปลงจำนวน asset A → จำนวน asset B ที่มูลค่าเท่ากันตาม reserve ratio
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'TPIXDEXLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'TPIXDEXLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    /// @notice คำนวณ output สูงสุดจาก input (หัก fee 0.3%)
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'TPIXDEXLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'TPIXDEXLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice คำนวณ input ขั้นต่ำที่ต้องใช้เพื่อให้ได้ output ตามต้องการ (หัก fee 0.3%)
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'TPIXDEXLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'TPIXDEXLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @notice คำนวณ output ต่อเนื่องตลอด path (หลาย hop)
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, 'TPIXDEXLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @notice คำนวณ input ย้อนกลับตลอด path (หลาย hop)
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, 'TPIXDEXLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}

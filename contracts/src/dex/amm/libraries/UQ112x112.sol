// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title UQ112x112
 * @notice Fixed-point library สำหรับ price accumulator (TWAP oracle)
 * @dev Range: [0, 2^112 - 1], resolution 1/2^112
 */
library UQ112x112 {
    uint224 internal constant Q112 = 2 ** 112;

    /// @notice encode uint112 → UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // ไม่มีทาง overflow
    }

    /// @notice หาร UQ112x112 ด้วย uint112 → UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './TPIXDEXPair.sol';

/**
 * @title TPIXDEXFactory
 * @author Xman Studio
 * @notice Factory สร้าง/เก็บทะเบียน liquidity pair ทั้งหมดของ TPIX DEX
 * @dev Port จาก Uniswap V2 Factory
 *      FIX จาก skeleton เดิม: ตัด pairFor() (CREATE2 prediction) ทิ้ง —
 *      ทุกคนต้องอ่าน getPair() mapping แทน เพื่อไม่ให้มี init-code-hash ให้ maintain
 *
 *      Fee: setFeeTo(fee_collector) → protocol เก็บ 1/6 ของ fee growth ทุก pair
 */
contract TPIXDEXFactory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    constructor(address _feeToSetter) {
        require(_feeToSetter != address(0), 'TPIX: ZERO_ADDRESS');
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /**
     * @notice สร้าง liquidity pair ใหม่ (permissionless — ใครก็สร้างได้แบบ UniV2)
     * @return pair Address ของ pair ที่สร้าง (CREATE2 — deterministic ต่อคู่ token)
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'TPIX: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'TPIX: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'TPIX: PAIR_EXISTS');

        bytes memory bytecode = type(TPIXDEXPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        TPIXDEXPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // ลง mapping ทั้งสองทิศทาง
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /// @notice ตั้ง address รับ protocol fee (ตั้งเป็น address(0) = ปิด protocol fee)
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'TPIX: FORBIDDEN');
        feeTo = _feeTo;
    }

    /// @notice โอนสิทธิ์ตั้งค่า fee ให้ address ใหม่
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'TPIX: FORBIDDEN');
        require(_feeToSetter != address(0), 'TPIX: ZERO_ADDRESS');
        feeToSetter = _feeToSetter;
    }
}

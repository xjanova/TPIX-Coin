// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

/**
 * @title TPIXRouter
 * @author TPIX TRADE
 * @notice A DEX fee collection router that wraps any Uniswap V2-compatible router
 *         (Uniswap, PancakeSwap, SushiSwap, etc.) and collects a configurable
 *         platform fee on every swap before forwarding the trade to the underlying DEX.
 *
 * @dev This contract is designed to be chain-agnostic and can be deployed on any
 *      EVM-compatible network (Ethereum, BSC, Polygon, Arbitrum, Avalanche, etc.).
 *
 *      Fee Mechanics:
 *      - Fees are deducted from the INPUT token/native currency before the swap.
 *      - Fee rate is expressed in basis points (1 bp = 0.01%).
 *      - Maximum fee cap is 500 bp (5%) to protect users.
 *      - Collected fees are sent directly to the configured fee collector wallet.
 *
 *      Security:
 *      - Uses OpenZeppelin's ReentrancyGuard to prevent reentrancy attacks.
 *      - Uses OpenZeppelin's Pausable for emergency circuit-breaking.
 *      - Uses OpenZeppelin's SafeERC20 to handle non-standard ERC20 tokens.
 *      - Owner-only administrative functions with appropriate access control.
 *      - Emergency withdrawal functions for stuck tokens/native currency.
 *
 *      Supported Swap Types:
 *      - ERC20 -> ERC20 (swapExactTokensForTokens)
 *      - Native -> ERC20 (swapExactETHForTokens)
 *      - ERC20 -> Native (swapExactTokensForETH)
 */
contract TPIXRouter is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // =========================================================================
    //                              CONSTANTS
    // =========================================================================

    /// @notice The denominator used for basis-point fee calculations (10000 = 100%).
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

    /// @notice The maximum allowable fee rate in basis points (500 = 5%).
    uint256 public constant MAX_FEE_RATE = 500;

    // =========================================================================
    //                            STATE VARIABLES
    // =========================================================================

    /// @notice The underlying Uniswap V2-compatible DEX router.
    IUniswapV2Router02 public dexRouter;

    /// @notice The wallet address that receives all collected platform fees.
    address public feeCollector;

    /// @notice The current fee rate in basis points (e.g., 30 = 0.3%).
    uint256 public feeRate;

    // =========================================================================
    //                               EVENTS
    // =========================================================================

    /**
     * @notice Emitted when a swap is executed through the router.
     * @param user The address that initiated the swap.
     * @param tokenIn The input token address (address(0) for native currency).
     * @param tokenOut The output token address (address(0) for native currency).
     * @param amountIn The gross input amount before fee deduction.
     * @param amountOut The output amount received from the DEX.
     * @param feeAmount The platform fee collected from this swap.
     */
    event SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 feeAmount
    );

    /**
     * @notice Emitted when a platform fee is collected and sent to the fee collector.
     * @param token The token address in which the fee was collected (address(0) for native).
     * @param amount The amount of fee collected.
     * @param collector The fee collector wallet that received the fee.
     */
    event FeeCollected(
        address indexed token,
        uint256 amount,
        address indexed collector
    );

    /**
     * @notice Emitted when the fee rate is updated by the owner.
     * @param oldRate The previous fee rate in basis points.
     * @param newRate The new fee rate in basis points.
     */
    event FeeRateUpdated(uint256 oldRate, uint256 newRate);

    /**
     * @notice Emitted when the fee collector wallet is updated by the owner.
     * @param oldCollector The previous fee collector address.
     * @param newCollector The new fee collector address.
     */
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    /**
     * @notice Emitted when the underlying DEX router is updated by the owner.
     * @param oldRouter The previous router address.
     * @param newRouter The new router address.
     */
    event RouterUpdated(address indexed oldRouter, address indexed newRouter);

    /**
     * @notice Emitted when tokens are withdrawn via the emergency withdrawal function.
     * @param token The token address withdrawn (address(0) for native currency).
     * @param to The recipient of the withdrawn tokens.
     * @param amount The amount withdrawn.
     */
    event EmergencyWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    // =========================================================================
    //                               ERRORS
    // =========================================================================

    /// @notice Thrown when the zero address is provided where a valid address is required.
    error ZeroAddress();

    /// @notice Thrown when the fee rate exceeds the maximum allowed cap.
    /// @param requested The fee rate that was requested.
    /// @param maximum The maximum allowable fee rate.
    error FeeRateTooHigh(uint256 requested, uint256 maximum);

    /// @notice Thrown when a swap amount is zero.
    error ZeroAmount();

    /// @notice Thrown when the swap path has fewer than 2 tokens.
    error InvalidPath();

    /// @notice Thrown when the swap deadline has already passed.
    error DeadlineExpired();

    /// @notice Thrown when a native currency transfer fails.
    error NativeTransferFailed();

    /// @notice Thrown when there is nothing to withdraw in an emergency withdrawal.
    error NothingToWithdraw();

    // =========================================================================
    //                             CONSTRUCTOR
    // =========================================================================

    /**
     * @notice Deploys the TPIXRouter contract.
     * @param _dexRouter The address of the underlying Uniswap V2-compatible DEX router.
     * @param _feeCollector The wallet address that will receive collected platform fees.
     * @param _feeRate The initial fee rate in basis points (e.g., 30 = 0.3%).
     * @param _owner The address that will own this contract and have administrative privileges.
     *
     * @dev Reverts with `ZeroAddress` if any address parameter is the zero address.
     *      Reverts with `FeeRateTooHigh` if `_feeRate` exceeds `MAX_FEE_RATE`.
     */
    constructor(
        address _dexRouter,
        address _feeCollector,
        uint256 _feeRate,
        address _owner
    ) Ownable(_owner) {
        if (_dexRouter == address(0)) revert ZeroAddress();
        if (_feeCollector == address(0)) revert ZeroAddress();
        if (_feeRate > MAX_FEE_RATE) revert FeeRateTooHigh(_feeRate, MAX_FEE_RATE);

        dexRouter = IUniswapV2Router02(_dexRouter);
        feeCollector = _feeCollector;
        feeRate = _feeRate;
    }

    /**
     * @notice Allows the contract to receive native currency (ETH/BNB/MATIC/etc.).
     * @dev Required to receive native currency refunds from the DEX router.
     */
    receive() external payable {}

    // =========================================================================
    //                           SWAP FUNCTIONS
    // =========================================================================

    /**
     * @notice Swaps an exact amount of ERC20 tokens for as many output tokens as possible,
     *         collecting a platform fee from the input amount before forwarding to the DEX.
     *
     * @param amountIn The gross amount of input tokens (fee will be deducted from this).
     * @param amountOutMin The minimum amount of output tokens to receive from the DEX
     *                     (applied to the post-fee amount). Use appropriate slippage tolerance.
     * @param path An array of token addresses representing the swap route.
     *             path[0] is the input token; path[path.length - 1] is the output token.
     * @param to The recipient address for the output tokens.
     * @param deadline The Unix timestamp after which the swap will revert.
     *
     * @return amounts An array of amounts for each step in the swap path, as returned
     *                 by the underlying DEX router.
     *
     * @dev The caller must have approved this contract to spend at least `amountIn`
     *      of the input token before calling this function.
     *
     *      Flow:
     *      1. Transfer `amountIn` of input token from caller to this contract.
     *      2. Calculate and deduct the platform fee.
     *      3. Send the fee to the fee collector.
     *      4. Approve the DEX router to spend the remaining amount.
     *      5. Execute the swap on the DEX router.
     *      6. Emit SwapExecuted and FeeCollected events.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256[] memory amounts) {
        _validateSwapParams(amountIn, path, deadline);

        address inputToken = path[0];
        address outputToken = path[path.length - 1];

        // Transfer input tokens from user to this contract
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate and collect fee
        uint256 feeAmount = _calculateFee(amountIn);
        uint256 amountAfterFee = amountIn - feeAmount;

        if (feeAmount > 0) {
            IERC20(inputToken).safeTransfer(feeCollector, feeAmount);
            emit FeeCollected(inputToken, feeAmount, feeCollector);
        }

        // Approve the DEX router to spend the post-fee amount
        IERC20(inputToken).forceApprove(address(dexRouter), amountAfterFee);

        // Execute swap on the underlying DEX
        amounts = dexRouter.swapExactTokensForTokens(
            amountAfterFee,
            amountOutMin,
            path,
            to,
            deadline
        );

        emit SwapExecuted(
            msg.sender,
            inputToken,
            outputToken,
            amountIn,
            amounts[amounts.length - 1],
            feeAmount
        );

        return amounts;
    }

    /**
     * @notice Swaps exact native currency (ETH/BNB/MATIC) for as many output tokens
     *         as possible, collecting a platform fee from the native amount before
     *         forwarding to the DEX.
     *
     * @param amountOutMin The minimum amount of output tokens to receive from the DEX
     *                     (applied to the post-fee amount). Use appropriate slippage tolerance.
     * @param path An array of token addresses representing the swap route.
     *             path[0] MUST be the WETH/WBNB/WMATIC address of the underlying router.
     *             path[path.length - 1] is the output token.
     * @param to The recipient address for the output tokens.
     * @param deadline The Unix timestamp after which the swap will revert.
     *
     * @return amounts An array of amounts for each step in the swap path, as returned
     *                 by the underlying DEX router.
     *
     * @dev The caller must send the exact native currency amount via `msg.value`.
     *
     *      Flow:
     *      1. Calculate and deduct the platform fee from msg.value.
     *      2. Send the fee (in native currency) to the fee collector.
     *      3. Forward the remaining native currency to the DEX router for swapping.
     *      4. Emit SwapExecuted and FeeCollected events.
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant whenNotPaused returns (uint256[] memory amounts) {
        _validateSwapParams(msg.value, path, deadline);

        address outputToken = path[path.length - 1];

        // Calculate and collect fee from native currency
        uint256 feeAmount = _calculateFee(msg.value);
        uint256 amountAfterFee = msg.value - feeAmount;

        if (feeAmount > 0) {
            _transferNative(feeCollector, feeAmount);
            emit FeeCollected(address(0), feeAmount, feeCollector);
        }

        // Execute swap on the underlying DEX with remaining native currency
        amounts = dexRouter.swapExactETHForTokens{value: amountAfterFee}(
            amountOutMin,
            path,
            to,
            deadline
        );

        emit SwapExecuted(
            msg.sender,
            address(0),
            outputToken,
            msg.value,
            amounts[amounts.length - 1],
            feeAmount
        );

        return amounts;
    }

    /**
     * @notice Swaps an exact amount of ERC20 tokens for as much native currency
     *         (ETH/BNB/MATIC) as possible, collecting a platform fee from the input
     *         token amount before forwarding to the DEX.
     *
     * @param amountIn The gross amount of input tokens (fee will be deducted from this).
     * @param amountOutMin The minimum amount of native currency to receive from the DEX
     *                     (applied to the post-fee amount). Use appropriate slippage tolerance.
     * @param path An array of token addresses representing the swap route.
     *             path[0] is the input token.
     *             path[path.length - 1] MUST be the WETH/WBNB/WMATIC address.
     * @param to The recipient address for the native currency output.
     * @param deadline The Unix timestamp after which the swap will revert.
     *
     * @return amounts An array of amounts for each step in the swap path, as returned
     *                 by the underlying DEX router.
     *
     * @dev The caller must have approved this contract to spend at least `amountIn`
     *      of the input token before calling this function.
     *
     *      Flow:
     *      1. Transfer `amountIn` of input token from caller to this contract.
     *      2. Calculate and deduct the platform fee.
     *      3. Send the fee to the fee collector.
     *      4. Approve the DEX router to spend the remaining amount.
     *      5. Execute the swap on the DEX router, receiving native currency to `to`.
     *      6. Emit SwapExecuted and FeeCollected events.
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256[] memory amounts) {
        _validateSwapParams(amountIn, path, deadline);

        address inputToken = path[0];

        // Transfer input tokens from user to this contract
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amountIn);

        // Calculate and collect fee
        uint256 feeAmount = _calculateFee(amountIn);
        uint256 amountAfterFee = amountIn - feeAmount;

        if (feeAmount > 0) {
            IERC20(inputToken).safeTransfer(feeCollector, feeAmount);
            emit FeeCollected(inputToken, feeAmount, feeCollector);
        }

        // Approve the DEX router to spend the post-fee amount
        IERC20(inputToken).forceApprove(address(dexRouter), amountAfterFee);

        // Execute swap on the underlying DEX
        amounts = dexRouter.swapExactTokensForETH(
            amountAfterFee,
            amountOutMin,
            path,
            to,
            deadline
        );

        emit SwapExecuted(
            msg.sender,
            inputToken,
            address(0),
            amountIn,
            amounts[amounts.length - 1],
            feeAmount
        );

        return amounts;
    }

    // =========================================================================
    //                        ADMIN FUNCTIONS
    // =========================================================================

    /**
     * @notice Updates the platform fee rate.
     * @param _newFeeRate The new fee rate in basis points (e.g., 30 = 0.3%).
     *
     * @dev Only callable by the contract owner.
     *      Reverts with `FeeRateTooHigh` if `_newFeeRate` exceeds `MAX_FEE_RATE` (500 bp).
     *      Emits a {FeeRateUpdated} event.
     */
    function setFeeRate(uint256 _newFeeRate) external onlyOwner {
        if (_newFeeRate > MAX_FEE_RATE) revert FeeRateTooHigh(_newFeeRate, MAX_FEE_RATE);

        uint256 oldRate = feeRate;
        feeRate = _newFeeRate;

        emit FeeRateUpdated(oldRate, _newFeeRate);
    }

    /**
     * @notice Updates the fee collector wallet address.
     * @param _newFeeCollector The new wallet address to receive platform fees.
     *
     * @dev Only callable by the contract owner.
     *      Reverts with `ZeroAddress` if `_newFeeCollector` is the zero address.
     *      Emits a {FeeCollectorUpdated} event.
     */
    function setFeeCollector(address _newFeeCollector) external onlyOwner {
        if (_newFeeCollector == address(0)) revert ZeroAddress();

        address oldCollector = feeCollector;
        feeCollector = _newFeeCollector;

        emit FeeCollectorUpdated(oldCollector, _newFeeCollector);
    }

    /**
     * @notice Updates the underlying DEX router address.
     * @param _newRouter The address of the new Uniswap V2-compatible DEX router.
     *
     * @dev Only callable by the contract owner.
     *      Reverts with `ZeroAddress` if `_newRouter` is the zero address.
     *      Emits a {RouterUpdated} event.
     *
     *      WARNING: Changing the router may affect existing token approvals.
     *      Ensure the new router is a trusted, audited contract.
     */
    function setRouter(address _newRouter) external onlyOwner {
        if (_newRouter == address(0)) revert ZeroAddress();

        address oldRouter = address(dexRouter);
        dexRouter = IUniswapV2Router02(_newRouter);

        emit RouterUpdated(oldRouter, _newRouter);
    }

    // =========================================================================
    //                       EMERGENCY FUNCTIONS
    // =========================================================================

    /**
     * @notice Pauses all swap operations. Can only be called by the owner.
     * @dev When paused, all swap functions will revert. Administrative functions
     *      remain accessible. Use this in case of detected vulnerabilities or
     *      during maintenance periods.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses swap operations. Can only be called by the owner.
     * @dev Restores normal swap functionality after a pause.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Withdraws ERC20 tokens accidentally sent to this contract.
     * @param token The address of the ERC20 token to withdraw.
     * @param to The recipient address for the withdrawn tokens.
     *
     * @dev Only callable by the contract owner.
     *      Reverts with `ZeroAddress` if `to` is the zero address.
     *      Reverts with `NothingToWithdraw` if the contract has no balance of the token.
     *      Emits an {EmergencyWithdrawal} event.
     *
     *      This function exists to recover tokens that are accidentally sent to the
     *      contract or that remain due to unexpected swap failures.
     */
    function emergencyWithdrawToken(address token, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NothingToWithdraw();

        IERC20(token).safeTransfer(to, balance);

        emit EmergencyWithdrawal(token, to, balance);
    }

    /**
     * @notice Withdraws native currency (ETH/BNB/MATIC) accidentally sent to this contract.
     * @param to The recipient address for the withdrawn native currency.
     *
     * @dev Only callable by the contract owner.
     *      Reverts with `ZeroAddress` if `to` is the zero address.
     *      Reverts with `NothingToWithdraw` if the contract has no native currency balance.
     *      Reverts with `NativeTransferFailed` if the transfer fails.
     *      Emits an {EmergencyWithdrawal} event.
     */
    function emergencyWithdrawNative(address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = address(this).balance;
        if (balance == 0) revert NothingToWithdraw();

        _transferNative(to, balance);

        emit EmergencyWithdrawal(address(0), to, balance);
    }

    // =========================================================================
    //                          VIEW FUNCTIONS
    // =========================================================================

    /**
     * @notice Calculates the platform fee for a given input amount.
     * @param amountIn The input amount to calculate the fee for.
     * @return feeAmount The fee amount that would be deducted.
     * @return amountAfterFee The remaining amount after fee deduction.
     */
    function calculateFeeBreakdown(
        uint256 amountIn
    ) external view returns (uint256 feeAmount, uint256 amountAfterFee) {
        feeAmount = _calculateFee(amountIn);
        amountAfterFee = amountIn - feeAmount;
    }

    /**
     * @notice Returns the expected output amounts for a given swap, accounting for
     *         the platform fee deduction on the input.
     * @param amountIn The gross input amount (before fee deduction).
     * @param path The token swap path.
     * @return amounts The expected output amounts at each step, based on the post-fee input.
     *
     * @dev This is a convenience function that queries the underlying DEX router's
     *      `getAmountsOut` with the fee-adjusted input amount.
     */
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts) {
        uint256 feeAmount = _calculateFee(amountIn);
        uint256 amountAfterFee = amountIn - feeAmount;
        return dexRouter.getAmountsOut(amountAfterFee, path);
    }

    /**
     * @notice Returns the WETH (or WBNB/WMATIC) address from the underlying DEX router.
     * @return The wrapped native currency token address.
     */
    function WETH() external view returns (address) {
        return dexRouter.WETH();
    }

    // =========================================================================
    //                       INTERNAL FUNCTIONS
    // =========================================================================

    /**
     * @notice Calculates the platform fee for a given amount.
     * @param amount The amount to calculate the fee on.
     * @return The calculated fee amount.
     * @dev Fee = amount * feeRate / BASIS_POINTS_DENOMINATOR.
     *      Returns 0 if feeRate is 0.
     */
    function _calculateFee(uint256 amount) internal view returns (uint256) {
        if (feeRate == 0) return 0;
        return (amount * feeRate) / BASIS_POINTS_DENOMINATOR;
    }

    /**
     * @notice Validates common swap parameters.
     * @param amountIn The input amount to validate.
     * @param path The swap path to validate.
     * @param deadline The deadline to validate.
     *
     * @dev Reverts with:
     *      - `ZeroAmount` if `amountIn` is 0.
     *      - `InvalidPath` if `path` has fewer than 2 elements.
     *      - `DeadlineExpired` if `deadline` is in the past.
     */
    function _validateSwapParams(
        uint256 amountIn,
        address[] calldata path,
        uint256 deadline
    ) internal view {
        if (amountIn == 0) revert ZeroAmount();
        if (path.length < 2) revert InvalidPath();
        if (deadline < block.timestamp) revert DeadlineExpired();
    }

    /**
     * @notice Safely transfers native currency to a recipient.
     * @param to The recipient address.
     * @param amount The amount of native currency to transfer.
     * @dev Reverts with `NativeTransferFailed` if the transfer fails.
     */
    function _transferNative(address to, uint256 amount) internal {
        (bool success, ) = payable(to).call{value: amount}("");
        if (!success) revert NativeTransferFailed();
    }
}

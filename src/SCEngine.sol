// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title SCEngine
 * @author Michael ECo
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * The stable coin has the properties:
 * - Exogenous Collateral
 * - Dollar pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI have no governance, no fees, and was only backed by WETH and WBTC.
 * Our SC system should be always be "overcollateralized". At no point, should the value of the all collateral <= the $ backed by value of all the SC
 *
 * @notice This contract is the core of the SC system. It handles all the logic for mining and redeeming SC, as well as the depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract SCEngine {
    function depositCollateralAndMinSC() external {}

    function depositCollateral() external {}

    function redeemCollateralForSC() external {}

    function redeemCollateral() external {}

    function burnSC() external {}

    function mintSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}

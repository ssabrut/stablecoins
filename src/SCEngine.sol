// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {StableCoin} from "src/StableCoin.sol";

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
    error SCEngine__NeedsMoreThanZero();
    error SCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();

    mapping(address token => address priceFeed) private s_priceFeeds;

    StableCoin private immutable i_sc;

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert SCEngine__NeedsMoreThanZero();
        }
        _;
    }

    // modifier isAllowedToken(address _token) {

    // }

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address _scAddress
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert SCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
        }

        i_sc = StableCoin(_scAddress);
    }

    function depositCollateralAndMinSC() external {}

    /**
     *
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount fo the collateral to deposit
     */
    function depositCollateral(
        address _tokenCollateralAddress,
        uint256 _amountCollateral
    ) external moreThanZero(_amountCollateral) {}

    function redeemCollateralForSC() external {}

    function redeemCollateral() external {}

    function burnSC() external {}

    function mintSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}

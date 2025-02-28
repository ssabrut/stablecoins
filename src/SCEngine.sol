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
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
contract SCEngine is ReentrancyGuard {
    error SCEngine__NeedsMoreThanZero();
    error SCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error SCEngine__NotAllowedToken();
    error SCEngine__TransferFailed();
    error SCEngine__MintFailed();
    error SCEngine__BreaksHealthFactor(uint256 _healthFactor);

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountSCMinted) private s_SCMinted;
    address[] private s_collateralTokens;
    StableCoin private immutable i_sc;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert SCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert SCEngine__NotAllowedToken();
        }

        _;
    }

    constructor(address[] memory _tokenAddresses, address[] memory _priceFeedAddresses, address _scAddress) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert SCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }

        i_sc = StableCoin(_scAddress);
    }

    /**
     *
     * @param _tokenAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount of collateral to deposit
     * @param _amountToMint The amount of stable coin to mint
     * @notice This function will deposit your collateral and mint SC in one transaction
     */
    function depositCollateralAndMintSC(address _tokenAddress, uint256 _amountCollateral, uint256 _amountToMint)
        external
    {
        depositCollateral(_tokenAddress, _amountCollateral);
        mintSC(_amountToMint);
    }

    /**
     * @notice Redeems collateral by burning StableCoin tokens
     * @dev This function combines burning StableCoin tokens and redeeming collateral in a single transaction
     * @param _tokenAddress The address of the collateral token to redeem
     * @param _amountCollateral The amount of collateral to redeem
     * @param _amountToBurn The amount of StableCoin tokens to burn
     * @custom:requirements User must have sufficient StableCoin balance and the contract must have sufficient collateral
     */
    function redeemCollateralForSC(address _tokenAddress, uint256 _amountCollateral, uint256 _amountToBurn) external {
        burnSC(_amountToBurn);
        redeemCollateral(_tokenAddress, _amountCollateral);
    }

    /**
     * @notice Allows a user to redeem collateral that has been deposited
     * @dev This function will revert if the transfer fails or if redeeming the collateral would break the user's health factor
     * @param _tokenAddress The address of the collateral token to redeem
     * @param _amountCollateral The amount of collateral to redeem
     * @custom:modifier moreThanZero Ensures the collateral amount is greater than zero
     * @custom:modifier nonReentrant Prevents reentrancy attacks
     * @custom:emits CollateralRedeemed when collateral is successfully redeemed
     * @custom:error SCEngine__TransferFailed If the token transfer fails
     */
    function redeemCollateral(address _tokenAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenAddress] -= _amountCollateral;
        emit CollateralRedeemed(msg.sender, _tokenAddress, _amountCollateral);

        bool success = IERC20(_tokenAddress).transfer(msg.sender, _amountCollateral);
        if (!success) {
            revert SCEngine__TransferFailed();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Burns a specified amount of stable coins from the sender's balance.
     * @dev This function decreases the sender's minted SC balance, transfers the tokens to this contract,
     *      and then burns them. It also checks that the sender's health factor remains valid after the operation.
     * @param _amount The amount of stable coins to burn
     * @custom:modifier moreThanZero Ensures the amount is greater than zero
     * @custom:throws SCEngine__TransferFailed if the token transfer fails
     */
    function burnSC(uint256 _amount) public moreThanZero(_amount) {
        s_SCMinted[msg.sender] -= _amount;
        bool success = i_sc.transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert SCEngine__TransferFailed();
        }

        i_sc.burn(_amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    /**
     * @notice follows CEI
     * @param _tokenCollateralAddress The address of the token to deposit as collateral
     * @param _amountCollateral The amount fo the collateral to deposit
     */
    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert SCEngine__TransferFailed();
        }
    }

    /**
     *
     * @notice follows CEI
     * @param _amountSCToMint The amount of stable coin to mint
     * @notice They must have more collateral value more than the minimum threshold
     */
    function mintSC(uint256 _amountSCToMint) public moreThanZero(_amountSCToMint) nonReentrant {
        s_SCMinted[msg.sender] += _amountSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_sc.mint(msg.sender, _amountSCToMint);
        if (!minted) {
            revert SCEngine__MintFailed();
        }
    }

    function getUsdValue(address _token, uint256 _amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * _amount) / PRECISION;
    }

    function getAccountCollateralValue(address _user) public view returns (uint256 totalCollateralInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[_user][token];
            totalCollateralInUsd += getUsdValue(token, amount);
        }

        return totalCollateralInUsd;
    }

    function _getAccountInformation(address _user)
        internal
        view
        returns (uint256 totalSCMinted, uint256 collateralValueInUsd)
    {
        totalSCMinted = s_SCMinted[_user];
        collateralValueInUsd = getAccountCollateralValue(_user);
    }

    /**
     * Returns how close to liquidation a user is
     * if a user goes below 1, they get liquidated
     * @param _user The user that want to be checked
     */
    function _healthFactor(address _user) internal view returns (uint256) {
        (uint256 totalSCMinted, uint256 collateralValueInUsd) = _getAccountInformation(_user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalSCMinted;
    }

    function _revertIfHealthFactorIsBroken(address _user) internal view {
        uint256 healthFactor = _healthFactor(_user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert SCEngine__BreaksHealthFactor(healthFactor);
        }
    }
}

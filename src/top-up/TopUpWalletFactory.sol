// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CREATE3} from "solady/utils/CREATE3.sol";
import {UUPSUpgradeable, Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {TopUpWallet} from "./TopUpWallet.sol";
import { IStargate, Ticket } from "../interfaces/IStargate.sol";
import { MessagingFee, OFTReceipt, SendParam } from "../interfaces/IOFT.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TopUpWalletFactory
 * @author ether.fi [shivam@ether.fi]
 * @notice Factory to deploy the topup wallet contracts for a user
 */
contract TopUpWalletFactory is Initializable, UUPSUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint32 public immutable scrollDestEid;
    address public beacon;
    address public scrollSafe;
    mapping(address asset => address stargatePool) public stargatePool; 

    event WalletDeployed(address indexed wallet);
    event BatchWalletDeployed(address[] indexed wallets);
    event BeaconSet(address oldBeacon, address newBeacon);
    event ScrollSafeSet(address oldSafe, address newSafe);
    event StargatePoolSet(address[] asset, address[] stargatePool);
    event FundsBridgedWithStargate(address indexed token, uint256 amount, Ticket ticket);

    error InvalidValue();
    error ArrayLengthMismatch();
    error ScrollSafeNotSet();
    error StargatePoolNotSet();
    error InsufficientFeeToCoverCost();

    constructor(uint32 _scrollDestEid) {
        scrollDestEid = _scrollDestEid;
        _disableInitializers();
    }

    function initialize(
        uint48 _accessControlDelay,
        address _owner,
        address _implementation,
        address _scrollSafe
    ) external initializer {
        __AccessControlDefaultAdminRules_init(_accessControlDelay, _owner);
        _grantRole(ADMIN_ROLE, _owner);
        beacon = address(new UpgradeableBeacon(_implementation, address(this)));
        scrollSafe = _scrollSafe;
    }

    function setBeacon(address _beacon) external onlyRole(ADMIN_ROLE) {
        if (_beacon == address(0)) revert InvalidValue();
        emit BeaconSet(beacon, _beacon);
        beacon = _beacon;
    }

    function setScrollSafe(address _scrollSafe) external onlyRole(ADMIN_ROLE) {
        if (_scrollSafe == address(0)) revert InvalidValue();
        emit ScrollSafeSet(scrollSafe, _scrollSafe);
        scrollSafe = _scrollSafe;   
    }

    function setStargatePool(address[] memory assets, address[] memory pools) external onlyRole(ADMIN_ROLE) {
        uint256 len = assets.length;
        if (len != pools.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < len; ) {
            if (assets[i] == address(0) || pools[i] == address(0)) revert InvalidValue();
            stargatePool[assets[i]] = pools[i];
            unchecked {
                ++i;
            }
        }

        emit StargatePoolSet(assets, pools);
    }

    function getWalletAddress(bytes32 salt) external view returns (address) {
        return CREATE3.predictDeterministicAddress(salt);
    }

    function deployWallet(bytes32 salt) public onlyRole(ADMIN_ROLE) {
        address wallet = _deployWallet(salt);
        emit WalletDeployed(wallet);
    }

    function batchDeployWallet(bytes32[] memory salts) external onlyRole(ADMIN_ROLE) {
        uint256 len = salts.length;
        address[] memory wallets = new address[](len);

        for (uint256 i = 0; i < len; ) {
            wallets[i] = _deployWallet(salts[i]);
            unchecked {
                ++i;
            }
        }

        emit BatchWalletDeployed(wallets);
    }

    function flush(address[] memory wallets, address[] memory tokens) external {
        uint256 len = wallets.length;
        for(uint256 i = 0; i < len; ) {
            TopUpWallet(payable(wallets[i])).flushTokens(tokens);
            unchecked {
                ++i;
            }
        }
    }

    function bridge(address[] memory tokens) external onlyRole(ADMIN_ROLE) {
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ) {
            _bridge(tokens[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _bridge(address token) internal {
        uint256 amount = IERC20(token).balanceOf(address(this));
        (address stargate, uint256 valueToSend, SendParam memory sendParam, MessagingFee memory messagingFee) = 
            prepareRideBus(token, amount);
        
        if (address(this).balance < valueToSend) revert InsufficientFeeToCoverCost();
        IERC20(token).forceApprove(stargate, amount);
        (, , Ticket memory ticket) = IStargate(stargate).sendToken{ value: valueToSend }(sendParam, messagingFee, payable(address(this)));
        emit FundsBridgedWithStargate(token, amount, ticket);
    }

    // from https://stargateprotocol.gitbook.io/stargate/v/v2-developer-docs/integrate-with-stargate/how-to-swap#ride-the-bus
    function prepareRideBus(
        address token, 
        uint256 amount
    ) public view returns (address stargate,  uint256 valueToSend,  SendParam memory sendParam,  MessagingFee memory messagingFee) {
        if (token == address(0) || amount == 0) revert InvalidValue();
        if (scrollSafe == address(0)) revert ScrollSafeNotSet();
        if (stargatePool[token] == address(0)) revert StargatePoolNotSet();

        stargate = stargatePool[token];
        sendParam = SendParam({
            dstEid: scrollDestEid,
            to: bytes32(uint256(uint160(scrollSafe))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: new bytes(0),
            composeMsg: new bytes(0),
            oftCmd: new bytes(1)
        });

        (, , OFTReceipt memory receipt) = IStargate(stargate).quoteOFT(sendParam);
        sendParam.minAmountLD = receipt.amountReceivedLD;

        messagingFee = IStargate(stargate).quoteSend(sendParam, false);
        valueToSend = messagingFee.nativeFee;

        if (IStargate(stargate).token() == address(0x0)) {
            valueToSend += sendParam.amountLD;
        }
    }

    function upgradeWalletImpl(address newImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UpgradeableBeacon(beacon).upgradeTo(newImplementation);
    }

    function _deployWallet(bytes32 salt) internal returns (address) {
        return address(
            CREATE3.deployDeterministic(
                abi.encodePacked(
                    type(BeaconProxy).creationCode, 
                    abi.encode(beacon, abi.encodeWithSelector(TopUpWallet.initialize.selector, address(this)))
                ), 
                salt
            )
        );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE)  {}
}
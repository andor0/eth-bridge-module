pragma solidity ^0.5.12;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";

//Beneficieries (validators) template
import "../helpers/ValidatorsOperations.sol";
import "../third-party/BokkyPooBahsDateTimeLibrary.sol";
import "../bridge/Status.sol";
import "../bridge/Transfers.sol";
import "../bridge/Dao.sol";

contract Bridge is Initializable, ValidatorsOperations, Transfers, Dao, Status {

    using BokkyPooBahsDateTimeLibrary for uint;


    /* volume transactions */

    mapping(bytes32 => uint) currentVolumeByDate;

    /* pending volume */
    mapping(bytes32 => uint) currentVPendingVolumeByDate;

    mapping(bytes32 => mapping (address => uint)) currentDayVolumeForAddress;
    
    /**
    * @notice Constructor.
    * @param _token  Address of DAI token
    */
    function initialize(IERC20 _token) public 
    initializer {
        ValidatorsOperations.initialize();
        token = _token;
        init();
    } 

    // MODIFIERS
    /**
     * @dev Allows to perform method by existing Validator
    */
    modifier onlyExistingValidator(address _Validator) {
        require(isExistValidator(_Validator), "address is not in Validator array");
         _;
    }
    
    modifier checkMinMaxTransactionValue(uint value) {
        require(value < limits.maxHostTransactionValue && value < limits.minHostTransactionValue, "Transaction value is too  small or large");
        _;
    }

    modifier checkDayVolumeTransaction() {
        if (currentVolumeByDate[keccak256(abi.encodePacked(now.getYear(), now.getMonth(), now.getDay()))] > limits.dayHostMaxLimit) {
            _;
            _pauseBridgeByVolume();
        } else {
            if (pauseBridgeByVolume) {
                _resumeBridgeByVolume();
            }
            _;
        }
    }

    modifier checkPendingDayVolumeTransaction() {
        if (currentVPendingVolumeByDate[keccak256(abi.encodePacked(now.getYear(), now.getMonth(), now.getDay()))] > limits.maxGuestPendingTransactionLimit) {
            _;
            _pauseBridgeByVolume();
        } else {
            if (pauseBridgeByVolume) {
                _resumeBridgeByVolume();
            }
            _;
        }
    }

    modifier checkDayVolumeTransactionForAddress() {
        if (currentDayVolumeForAddress[keccak256(abi.encodePacked(now.getYear(), now.getMonth(), now.getDay()))][msg.sender] > limits.dayHostMaxLimitForOneAddress) {
             _;
             _pausedByBridgeVolumeForAddress(msg.sender);
        } else {
            if (pauseAccountByVolume[msg.sender]) {
                _resumedByBridgeVolumeForAddress(msg.sender);
            }
            _;
        }
    }

    /*
        public functions
    */
    function setTransfer(uint amount, bytes32 guestAddress) public 
    activeBridgeStatus
    checkMinMaxTransactionValue(amount)
    checkPendingDayVolumeTransaction()
    checkDayVolumeTransaction()
    checkDayVolumeTransactionForAddress() {
       _addPendingVolumeByDate(amount);
       _setTransfer(amount, guestAddress);
    }

    /*
        revert function
    */
    function revertTransfer(bytes32 messageID) public 
    activeBridgeStatus
    pendingMessage(messageID)  
    onlyManyValidators {
        _revertTransfer(messageID);
    }

    /*
    * Approve finance by message ID when transfer pending
    */
    function approveTransfer(bytes32 messageID, address spender, bytes32 guestAddress, uint availableAmount) public 
    activeBridgeStatus 
    validMessage(messageID, spender, guestAddress, availableAmount) 
    pendingMessage(messageID) 
    onlyManyValidators {
       _approveTransfer(messageID, spender, guestAddress, availableAmount);
    }

    /*
    * Confirm tranfer by message ID when transfer pending
    */
    function confirmTransfer(bytes32 messageID) public 
    activeBridgeStatus
    approvedMessage(messageID)  
    checkDayVolumeTransaction()
    checkDayVolumeTransactionForAddress()
    onlyManyValidators {
        _confirmTransfer(messageID);
        _addVolumeByMessageID(messageID);
    }

    /*
    * Withdraw tranfer by message ID after approve from guest
    */
    function withdrawTransfer(bytes32 messageID, bytes32  sender, address recipient, uint availableAmount)  public 
    activeBridgeStatus
    checkBalance(availableAmount)
    onlyManyValidators {
        _withdrawTransfer(messageID, sender, recipient, availableAmount);
    }

    /*
    * Confirm Withdraw tranfer by message ID after approve from guest
    */
    function confirmWithdrawTransfer(bytes32 messageID)  public withdrawMessage(messageID) 
    activeBridgeStatus 
    checkDayVolumeTransaction()
    checkDayVolumeTransactionForAddress()
    onlyManyValidators {
        _confirmWithdrawTransfer(messageID);
    }

    /*
    * Confirm Withdraw cancel by message ID after approve from guest
    */
    function confirmCancelTransfer(bytes32 messageID)  public 
    activeBridgeStatus 
    cancelMessage(messageID)  
    onlyManyValidators {
       _confirmWithdrawTransfer(messageID);
    }

    /* Bridge Status Function */
    function startBridge() public 
    stoppedOrPausedBridgeStatus 
    onlyManyValidators {
        _startBridge();
    }

    function resumeBridge() public 
    stoppedOrPausedBridgeStatus 
    onlyManyValidators {
        _resumeBridge();
    }

    function stopBridge() public 
    onlyManyValidators {
        _stopBridge();
    }

    function pauseBridge() public 
    onlyManyValidators {
        _pauseBridge();
    }

    function setPausedStatusForGuestAddress(bytes32 sender) 
    onlyManyValidators
    public {
       _setPausedStatusForGuestAddress(sender);
    }

    function setResumedStatusForGuestAddress(bytes32 sender) 
    onlyManyValidators
    public {
       _setResumedStatusForGuestAddress(sender);
    }

    /*
     DAO Parameters
    */
    function createProposal(uint[10] memory parameters) 
    onlyExistingValidator(msg.sender)
    public  {
        _createProposal(parameters);    
    }

    function _approvedNewProposal(bytes32 proposalID)
    onlyManyValidators
    public
    {
        _approvedNewProposal(limits, proposalID);
    }

    /*
     * Internal functions
    */
    function _addVolumeByMessageID(bytes32 messageID) internal {
        Message storage message = messages[messageID];
        bytes32 dateID = keccak256(abi.encodePacked(now.getYear(), now.getMonth(), now.getDay()));
        currentVolumeByDate[dateID] = currentVolumeByDate[dateID].add(message.availableAmount);
        currentDayVolumeForAddress[dateID][message.spender] = currentDayVolumeForAddress[dateID][message.spender].add(message.availableAmount);
    }  

    function _addPendingVolumeByDate(uint256 availableAmount) internal {
        bytes32 dateID = keccak256(abi.encodePacked(now.getYear(), now.getMonth(), now.getDay()));
        currentVolumeByDate[dateID] = currentVolumeByDate[dateID].add(availableAmount);
    }

}
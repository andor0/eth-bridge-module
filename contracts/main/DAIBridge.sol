pragma solidity ^0.5.12;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

//Beneficieries (validators) template
import "../helpers/ValidatorsOperations.sol";

contract DAIBridge is ValidatorsOperations {

    IERC20 private token;

    enum TransferStatus {PENDING, WITHDRAW, APPROVED, CANCELED, CONFIRMED, CONFIRMED_WITHDRAW, CANCELED_CONFIRMATION}

    enum BridgeStatus {ON, OFF, PAUSE}

    struct Message {
        bytes32 messageID;
        address spender;
        bytes32 substrateAddress;
        uint availableAmount;
        bool isExists; //check message is exists
        TransferStatus status;
    }

    event RelayMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);
    event ConfirmMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);
    event RevertMessage(bytes32 messageID, address sender, uint amount);
    event WithdrawMessage(bytes32 MessageID, address recepient, bytes32 sender, uint amount);
    event ApprovedRelayMessage(bytes32 messageID, address  sender, bytes32 recipient, uint amount);
    event ConfirmWithdrawMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);
    event ConfirmCancelMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);


    mapping(bytes32 => Message) messages;
    mapping(address => Message) messagesBySender;

    /**
    * @notice Constructor.
    * @param _token  Address of DAI token
    */
    constructor (IERC20 _token) public
        ValidatorsOperations() {
        token = _token;
    }  

    // MODIFIERS
    /**
     * @dev Allows to perform method by existing Validator
    */
    modifier onlyExistingValidator(address _Validator) {
        require(isExistValidator(_Validator), "address is not in Validator array");
         _;
    }

    /*
        check available amount
    */
    modifier messageHasAmount(bytes32 messageID) {
         require((messages[messageID].isExists && messages[messageID].availableAmount > 0), "Amount withdraw");
        _;
    }

    /*
        check that message is valid
    */
    modifier validMessage(bytes32 messageID, address spender, bytes32 substrateAddress, uint availableAmount) {
         require((messages[messageID].isExists && messages[messageID].spender == spender)
                && (messages[messageID].substrateAddress == substrateAddress)
                && (messages[messageID].availableAmount == availableAmount), "Data is not valid");
         _;
    }

    modifier pendingMessage(bytes32 messageID) {
        require(messages[messageID].isExists && messages[messageID].status == TransferStatus.PENDING, "Message is not pending");
        _;
    }

    modifier approvedMessage(bytes32 messageID) {
        require(messages[messageID].isExists && messages[messageID].status == TransferStatus.APPROVED, "Message is not approved");
         _;
    }

    modifier withdrawMessage(bytes32 messageID) {
        require(messages[messageID].isExists && messages[messageID].status == TransferStatus.WITHDRAW, "Message is not approved");
         _;
    }

    modifier cancelMessage(bytes32 messageID) {
         require(messages[messageID].isExists && messages[messageID].status == TransferStatus.CANCELED, "Message is not canceled");
        _;
    }

    function setTransfer(uint amount, bytes32 substrateAddress) public {
        require(token.allowance(msg.sender, address(this)) >= amount, "contract is not allowed to this amount");
        token.transferFrom(msg.sender, address(this), amount);

        bytes32 messageID = keccak256(abi.encodePacked(now));

        Message  memory message = Message(messageID, msg.sender, substrateAddress, amount, true, TransferStatus.PENDING);
        messages[messageID] = message;

         emit RelayMessage(messageID, msg.sender, substrateAddress, amount);
    }

    function revertTransfer(bytes32 messageID) public pendingMessage(messageID) onlyManyValidators {
        Message storage message = messages[messageID];

        message.status = TransferStatus.CANCELED;

        token.transfer(msg.sender, message.availableAmount);

            emit RevertMessage(messageID, msg.sender, message.availableAmount);
    }

    /*
    * Approve finance by message ID when transfer pending
    */
    function approveTransfer(bytes32 messageID, address spender, bytes32 substrateAddress, uint availableAmount)
        public validMessage(messageID, spender, substrateAddress, availableAmount) pendingMessage(messageID) onlyManyValidators {
        Message storage message = messages[messageID];
        message.status = TransferStatus.APPROVED;

        emit ApprovedRelayMessage(messageID, spender, substrateAddress, availableAmount);
    }

    /*
    * Confirm tranfer by message ID when transfer pending
    */
    function confirmTransfer(bytes32 messageID) public approvedMessage(messageID) onlyManyValidators {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CONFIRMED;
        emit ConfirmMessage(messageID, message.spender, message.substrateAddress, message.availableAmount);
    }

    /*
    * Withdraw tranfer by message ID after approve from Substrate
    */
    function withdrawTransfer(bytes32 messageID, bytes32  sender, address recipient, uint availableAmount)  public onlyManyValidators {
        require(token.balanceOf(address(this)) >= availableAmount, "Balance is not enough");
        token.transfer(recipient, availableAmount);
        Message  memory message = Message(messageID, msg.sender, sender, availableAmount, true, TransferStatus.WITHDRAW);
        messages[messageID] = message;
        emit WithdrawMessage(messageID, recipient, sender, availableAmount);
    }

    /*
    * Confirm Withdraw tranfer by message ID after approve from Substrate
    */
    function confirmWithdrawTransfer(bytes32 messageID)  public withdrawMessage(messageID) onlyManyValidators {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CONFIRMED_WITHDRAW;
        emit ConfirmWithdrawMessage(messageID, message.spender, message.substrateAddress, message.availableAmount);
    }

    /*
    * Confirm Withdraw cancel by message ID after approve from Substrate
    */
    function confirmCancelTransfer(bytes32 messageID)  public cancelMessage(messageID) onlyManyValidators {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CONFIRMED_WITHDRAW;
        emit ConfirmCancelMessage(messageID, message.spender, message.substrateAddress, message.availableAmount);
    }
}
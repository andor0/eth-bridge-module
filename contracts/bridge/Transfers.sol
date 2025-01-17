pragma solidity ^0.5.12;

import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";
import "../third-party/BokkyPooBahsDateTimeLibrary.sol";


contract Transfers {
    enum TransferStatus {PENDING, WITHDRAW, APPROVED, CANCELED, CONFIRMED, CONFIRMED_WITHDRAW, CANCELED_CONFIRMED}
    
    IERC20 internal token;

    /*
        Struct
    */
    struct Message {
        bytes32 messageID;
        address spender;
        bytes32 guestAddress;
        uint availableAmount;
        bool isExists; //check message is exists
        TransferStatus status;
    }

    /*
    *    Events
    */
    event RelayMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);
    event ConfirmMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);
    event RevertMessage(bytes32 messageID, address sender, uint amount);
    event WithdrawMessage(bytes32 MessageID, address recepient, bytes32 sender, uint amount);
    event ApprovedRelayMessage(bytes32 messageID, address  sender, bytes32 recipient, uint amount);
    event ConfirmWithdrawMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);
    event ConfirmCancelMessage(bytes32 messageID, address sender, bytes32 recipient, uint amount);

    /*
       * Messages
    */
    mapping(bytes32 => Message) messages;
    mapping(address => Message) messagesBySender;

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
    modifier validMessage(bytes32 messageID, address spender, bytes32 guestAddress, uint availableAmount) {
         require((messages[messageID].isExists && messages[messageID].spender == spender)
                && (messages[messageID].guestAddress == guestAddress)
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

    modifier allowTransfer(uint256 amount) {
        require(token.allowance(msg.sender, address(this)) >= amount, "contract is not allowed to this amount");
        _;
    }

    modifier checkBalance(uint256 availableAmount) {
        require(token.balanceOf(address(this)) >= availableAmount, "Balance is not enough");
        _;
    }

    function _setTransfer(uint amount, bytes32 guestAddress) internal 
    allowTransfer(amount) {
         /** to modifier **/
        
        token.transferFrom(msg.sender, address(this), amount);
        Message  memory message = Message(keccak256(abi.encodePacked(now)), msg.sender, guestAddress, amount, true, TransferStatus.PENDING);
        messages[keccak256(abi.encodePacked(now))] = message;

        emit RelayMessage(keccak256(abi.encodePacked(now)), msg.sender, guestAddress, amount);
    }

    function _revertTransfer(bytes32 messageID) internal {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CANCELED;
        token.transfer(msg.sender, message.availableAmount);
        emit RevertMessage(messageID, msg.sender, message.availableAmount);
    }

    function _approveTransfer(bytes32 messageID, address spender, bytes32 guestAddress, uint availableAmount) internal {
        Message storage message = messages[messageID];
        message.status = TransferStatus.APPROVED;

        emit ApprovedRelayMessage(messageID, spender, guestAddress, availableAmount);
    }

    function _confirmTransfer(bytes32 messageID) internal {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CONFIRMED;
        emit ConfirmMessage(messageID, message.spender, message.guestAddress, message.availableAmount);
    }

    function _withdrawTransfer(bytes32 messageID, bytes32  sender, address recipient, uint availableAmount) internal {
        token.transfer(recipient, availableAmount);
        Message  memory message = Message(messageID, msg.sender, sender, availableAmount, true, TransferStatus.WITHDRAW);
        messages[messageID] = message;
        emit WithdrawMessage(messageID, recipient, sender, availableAmount);
    }

    function _confirmWithdrawTransfer(bytes32 messageID) internal {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CONFIRMED_WITHDRAW;
        emit ConfirmWithdrawMessage(messageID, message.spender, message.guestAddress, message.availableAmount);
    }

    function  _confirmCancelTransfer(bytes32 messageID) internal {
        Message storage message = messages[messageID];
        message.status = TransferStatus.CANCELED_CONFIRMED;

        emit ConfirmCancelMessage(messageID, message.spender, message.guestAddress, message.availableAmount);
    }
}
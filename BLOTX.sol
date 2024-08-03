// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "./ERC20Upgradeable.sol";
import "./ERC20PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ERC20PermitUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

/**
 * @title BLOTXToken
 * @dev ERC20 token contract with pausable, upgradeable, and lockable features.
 * Inherits functionality from OpenZeppelin's upgradeable token contracts.
 */
contract BLOTXToken is Initializable, ERC20Upgradeable, ERC20PausableUpgradeable, OwnableUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {

    /// @notice Event emitted when the global lock state is changed
    event GlobalLockChanged(bool isLocked, uint256 unlockTime);

    /// @notice Event emitted when an account is added to the exception list
    event ExceptionAdded(address indexed account);

    /// @notice Event emitted when an account is removed from the exception list
    event ExceptionRemoved(address indexed account);


    /// @dev Mapping to store exception list accounts
    mapping(address => bool) private _exceptionList;

    /// @dev Global lock state
    bool private _globalLock;

    /// @dev Global unlock timestamps
    uint256 private _firstUnlockTime;
    uint256 private _secondUnlockTime;

    /// @dev Initial balances at the first unlock time
    mapping(address => uint256) private _initialBalances;

     /// @dev Mapping to store used quotas for each account
    mapping(address => uint256) private _usedQuota;

    /**
     * @dev Initializer function to replace constructor for upgradeable contracts.
     * @param initialOwner Address of the initial owner of the contract.
     */
    function initialize(address initialOwner) initializer public {
        __ERC20_init("BLOTX Token", "BLOTX");
        __ERC20Pausable_init();
        __Ownable_init(initialOwner);
        __ERC20Permit_init("BLOTX Token");
        __UUPSUpgradeable_init();

        _mint(msg.sender, 280000000 * 10 ** decimals());

        transferOwnership(initialOwner);
    }

    /**
     * @notice Pauses all token transfers.
     * @dev Can only be called by the contract owner.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers.
     * @dev Can only be called by the contract owner.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the global lock state and unlock times for the contract.
     * @param lock Boolean value indicating the new lock state.
     * @param firstUnlockTime Timestamp when the first unlock will occur.
     * @param secondUnlockTime Timestamp when the second unlock will occur.
     * @dev Can only be called by the contract owner.
     */
    function setGlobalLock(bool lock, uint256 firstUnlockTime, uint256 secondUnlockTime) public onlyOwner {
        _globalLock = lock;
        _firstUnlockTime = firstUnlockTime;
        _secondUnlockTime = secondUnlockTime;

        emit GlobalLockChanged(lock, firstUnlockTime);
    }

    /**
     * @notice Adds an account to the exception list.
     * @param account Address of the account to add.
     * @dev Can only be called by the contract owner.
     */
    function addException(address account) public onlyOwner {
        _exceptionList[account] = true;
        emit ExceptionAdded(account);
    }

    /**
     * @notice Removes an account from the exception list.
     * @param account Address of the account to remove.
     * @dev Can only be called by the contract owner.
     */
    function removeException(address account) public onlyOwner {
        _exceptionList[account] = false;
        emit ExceptionRemoved(account);
    }

    /**
     * @notice Checks if an account is locked.
     * @param account Address of the account to check.
     * @return True if the account is locked, false otherwise.
     */
    function isLocked(address account) public view returns (bool) {
        return (_globalLock && block.timestamp < _firstUnlockTime && !_exceptionList[account]);
    }

    /**
     * @dev Authorizes upgrades to the contract.
     * @param newImplementation Address of the new implementation contract.
     * @dev Can only be called by the contract owner.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /**
     * @dev Internal function to handle updates on token transfers.
     * @param from Address of the sender.
     * @param to Address of the receiver.
     * @param value Amount of tokens transferred.
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        super._update(from, to, value);

        _logInitialBalance(to);
        _logInitialBalance(from);
    }

    function _logInitialBalance(address account) internal {
        if (_initialBalances[account] == 0) {
            _initialBalances[account] = balanceOf(account);
        }
    }

    function getInitialBalanceOf(address account) public view returns (uint256){
        return _initialBalances[account];
    }
  

    /**
     * @dev Overrides the ERC20 transfer function to include custom logic.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return True if the transfer is successful.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!isLocked(_msgSender()), "Sender account is locked");
        _validateTransfer(_msgSender(), amount);
        return super.transfer(to, amount);
    }

    /**
     * @dev Overrides the ERC20 transferFrom function to include custom logic.
     * @param from The sender address.
     * @param to The recipient address.
     * @param amount The amount of tokens to transfer.
     * @return True if the transfer is successful.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!isLocked(from), "Sender account is locked");
        _validateTransfer(from, amount);
        return super.transferFrom(from, to, amount);
    }

    /**
     * @dev Validates a transfer based on the lock rules.
     * @param account The account initiating the transfer.
     * @param amount The amount of tokens to transfer.
     */
    function _validateTransfer(address account, uint256 amount) internal {
         if (_globalLock && block.timestamp >= _firstUnlockTime && block.timestamp < _secondUnlockTime) {
            uint256 initialBalance = _initialBalances[account];
            require(initialBalance > 0, "Initial balance not set");

            uint256 monthsSinceFirstUnlock = (block.timestamp - _firstUnlockTime) / 30 days;
            uint256 monthlyQuota = (initialBalance * 425) / 10000;
            uint256 totalQuota = (initialBalance * 49) / 100 + monthsSinceFirstUnlock * monthlyQuota;

            uint256 maxTransferable = totalQuota;

            // Calculate how much has actually been transferred from the initial quota
            uint256 alreadyTransferred = _usedQuota[account];

            uint256 availableToTransfer = maxTransferable > alreadyTransferred ? maxTransferable - alreadyTransferred : 0;

            require(amount <= availableToTransfer, "Transfer exceeds allowed quota");

            _usedQuota[account] += amount;
        }
    }

}

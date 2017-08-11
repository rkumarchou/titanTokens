//sol Wallet
// Multi-sig, daily-limited account proxy/wallet.
// @authors:
// Gav Wood <g@ethdev.com>
// inheritable "property" contract that enables methods to be protected by requiring the acquiescence of either a
// single, or, crucially, each of a number of, designated owners.
// usage:
// use modifiers onlyowner (just own owned) or onlymanyowners(hash), whereby the same hash must be provided by
// some number (specified in constructor) of the set of owners (specified in the constructor, modifiable) before the
// interior is executed.


import "./Token.sol";
import "./SecureMath.sol";
import "./SimpleWallet.sol";
import "./TACvoting.sol";

pragma solidity ^0.4.11;

/*
The standard Wallet contract, retrievable at
https://github.com/ethereum/dapp-bin/blob/master/wallet/wallet.sol has been
modified to include additional functionality, in particular:
*/



contract tokenControl is secureMath, multisig, multiowned {


    bool public tokenSaleStatus;
    uint public amountRaised;
    uint public constant SWAP_LENGTH =  6 weeks + 6 days + 3 hours;
    uint public constant MAX_ETH = 75000 ether; // Hard cap, capped otherwise by total tokens sold (max 7.5M FYN)
    Token public token;


    modifier isOverZeroValue {
        require (msg.value != 0);
        _;
    }

    modifier etherLimitNotReached {
    	require (amountRaised + msg.value <= MAX_ETH);
        _;
    }

    modifier tokenLimitNotReached {
        require (safeToMultiply(token.swapValue(), msg.value));
        uint tokensAmount = token.swapValue() * msg.value;
        require (safeToAdd(token.totalSupply(),tokensAmount));
        require (token.totalSupply() + tokensAmount <= token.tokenCap());
        _;
    }

    modifier isSaleStopped {
        require (tokenSaleStatus);
        _;
    }

    // Modifier to check if the token Increments have started
    modifier hasIncrementStarted {
      require (token.tokenIncrementInitiated());
      _;
    }

    modifier areConditionsSatisfied {
        _;
        // End token swap if sale period ended
        // We can't throw to reverse the amount sent in or we will lose state
        // , so we will accept it even though if it is after crowdsale
        if (token.creationTime() + SWAP_LENGTH < now) {
            token.enableTokenKill();
            tokenSaleStatus = false;
        }
        // Check if cap has been reached in this tx
        if (amountRaised == MAX_ETH) {
            token.enableTokenKill();
            tokenSaleStatus = false;
        }

        // Check if token cap has been reach in this tx
        if (token.totalSupply() == token.tokenCap()) {
            token.enableTokenKill();
            tokenSaleStatus = false;
        }
    }

    function startTokenSale() onlyowner {
        tokenSaleStatus = true;
    }

    function stopTokenSale() onlyowner {
        tokenSaleStatus = false;
    }

    function setTokenContract(address newTokenContractAddr) onlyowner {
        require (newTokenContractAddr != address(0x0));
        // Allow setting only once
        require (token == address(0x0));
        token = Token(newTokenContractAddr);
    }


    function buyTokens(address _beneficiary)
    payable
    isOverZeroValue
    etherLimitNotReached
    tokenLimitNotReached
    isSaleStopped
    areConditionsSatisfied {

        Deposit(msg.sender, msg.value);
        token.mint(_beneficiary, msg.value);
        require (safeToAdd(amountRaised, msg.value));
        amountRaised += msg.value;
    }

    // A simple function that calls the mintTokenIncrement function from the
    // token contract and increments the balance of the beneficiary. Modifier
    // checks if the increment process has started before running the function.
    function claimTokenIncrement(address _beneficiary) hasIncrementStarted {
      token.mintTokenIncrement(_beneficiary);
    }


    function withdrawReserve(address _beneficiary) onlyowner {
	    if (token.creationTime() + SWAP_LENGTH < now) {
            token.mintRemainingTokens(_beneficiary);
        }
    }
}


// usage:
// bytes32 h = Wallet(w).from(oneOwner).transact(to, value, data);
// Wallet(w).from(anotherOwner).confirm(h);
contract Wallet is secureMath, multisig, multiowned, daylimit, tokenControl {

	// METHODS

    struct Transaction {
        address to;
        uint value;
        bytes data;
    }

    // constructor - just pass on the owner array to the multiowned and
    // the limit to daylimit

    function Wallet(address[] _owners,  uint _required, uint _daylimit)
            multiowned(_owners, _required) daylimit(_daylimit)
            {

    }


    // Activates Emergency Stop for Token
    function stopToken() onlymanyowners(sha3(msg.data)) external {
       token.stopToken();
    }

    // gets called when no other function matches
    function()
    payable {
        buyTokens(msg.sender);
    }

    // Outside-visible transact entry point. Executes transaction immediately if below daily spend limit.
    // If not, goes into multisig process. We provide a hash on return to allow the sender to provide
    // shortcuts for the other confirmations (allowing them to avoid replicating the _to, _value
    // and _data arguments). They still get the option of using them if they want, anyways.


    function execute(address _to, uint _value, bytes _data) internal
    returns (bytes32 _r) {
        // Disallow the wallet contract from calling token contract once it's set
        // so tokens can't be minted arbitrarily once the sale starts.
        // Tokens can be minted for premine before the sale opens and token is set.
        require (_to != address(token));

        // first, take the opportunity to check that we're under the daily limit.

        SingleTransact(msg.sender, _value, _to, _data);
        // yes - just execute the call.
        if(!_to.call.value(_value)(_data))
        return 0;


        // determine our operation hash.
        _r = sha3(msg.data, block.number);
        if (!confirm(_r) && m_txs[_r].to == 0) {
            m_txs[_r].to = _to;
            m_txs[_r].value = _value;
            m_txs[_r].data = _data;
            ConfirmationNeeded(_r, msg.sender, _value, _to, _data);
        }
    }

    // confirm a transaction through just the hash. we use the previous transactions map, m_txs, in order
    // to determine the body of the transaction from the hash provided.
    function confirm(bytes32 _h) onlymanyowners(_h) returns (bool) {
        if (m_txs[_h].to != 0) {
            if (!m_txs[_h].to.call.value(m_txs[_h].value)(m_txs[_h].data))   // Bugfix: If successful, MultiTransact event should fire; if unsuccessful, we should throw
                throw;
            MultiTransact(msg.sender, _h, m_txs[_h].value, m_txs[_h].to, m_txs[_h].data);
            delete m_txs[_h];
            return true;
        }
    }

    // kills the contract sending everything to `_to`.
    function kill(address _to) onlymanyowners(sha3(msg.data)) external {
        // ensure owners can't prematurely stop token sale
        require (!tokenSaleStatus);
        // ensure owners can't kill wallet without stopping token
        //  otherwise token can never be stopped
        require (token.transferStop() == true);
        suicide(_to);
    }

    // INTERNAL METHODS

    function clearPending() internal {
        uint length = m_pendingIndex.length;
        for (uint i = 0; i < length; ++i)
            delete m_txs[m_pendingIndex[i]];
        super.clearPending();
    }



	// FIELDS

    // pending transactions we have at present.
    mapping (bytes32 => Transaction) m_txs;
}

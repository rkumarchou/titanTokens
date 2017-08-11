pragma solidity ^0.4.6;

import "./SecureMath.sol";

  // ERC20 Token Standard Interface
  // https://github.com/ethereum/EIPs/issues/20
  contract ERC20 {
    function totalSupply() constant returns (uint);
    function balanceOf(address who) constant returns (uint);
    function allowance(address owner, address spender) constant returns (uint);

    function transfer(address to, uint value) returns (bool ok);
    function transferFrom(address from, address to, uint value) returns (bool ok);
    function approve(address spender, uint value) returns (bool ok);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
  }


contract Token is  secureMath, ERC20 {

    string public name = "Titan tokens";
    string public symbol = "Titan";
    uint8  public decimals = 18;
    uint256 public tokenCap =  6900000e18;
    uint public swapValue = 20;

    address public walletAddress;

    // Event fired whenever tokens are minted.
    event Mint(address newTokenHolder, uint amountOfTokens);

    // Evenet fired when token sale finishes
    event TokenSaleOver();

    // Modifier to make sure that a function is called only
    // from the wallet.
    modifier onlyFromWallet {
      require (msg.sender == walletAddress);
      _;
    }

    // Modifier to make sure that a function is only called from
    // the TACvoting contract.
    modifier onlyFromTAC {
      require (msg.sender == TACAddress);
      _;
    }

    // Modifier to check if an address already is a tokenHolder
    modifier isTokenHolder (address _addr) {
      require (existingTokenHolder[uint(_addr)]);
      _;
    }

    // Modifier to check if an address is eligible for token increment
    // by checking the tokenHolders increment index.
    modifier eligibleForTokenIncrement (address _addr) {
      require (tokenHolderIncrementIndex[uint(_addr)] < (nextIncrementIndexNumber-1));
      _;
    }

    // Check if transfer should stop
    modifier checkTransferStop {
      require (transferStop != true);
      _;
    }

    function totalSupply() constant returns (uint supply) {
      return tokensSupplied;
    }

    // Constructor to make the Token contract. The owner's initial balance must be entered in the 1st argument
    function Token(uint initial_balance, address _walletAddress, address _TACAddress, uint256 saleTime) {
      balances[uint(msg.sender)] = initial_balance;
      tokensSupplied = initial_balance;
      walletAddress = _walletAddress;
      TACAddress = _TACAddress;
      creationTime = saleTime;
      transferStop = true;
    }

    // Function to check the balance of any token holder.
    function balanceOf( address who ) constant returns (uint value) {
      return balances[uint(who)];
    }

    // Function to check the allowable withdrawal approved by any token holders
    // for a particular address
    function allowance(address owner, address spender) constant returns (uint _allowance) {
      return allowed[owner][spender];
    }

    // Function to transfer tokens to a certain address
    function transfer( address to, uint value)
      checkTransferStop
      returns (bool ok) {

        require (to != walletAddress);
        require ( balances[uint(msg.sender)] >= value );
        require ( safeToAdd(balances[uint(to)], value) );

        balances[uint(msg.sender)] -= value;
        balances[uint(to)] += value;
        Transfer( msg.sender, to, value );
        return true;
    }


    // Function to transfer from an address to a different address.
    // The function checks if the from token holder has already approved
    // the transaction.
    function transferFrom( address from, address to, uint value)
      checkTransferStop
      returns (bool ok) {

        require (to != walletAddress) ;

        require ( balances[uint(from)] >= value );

        require ( allowed[from][msg.sender] < value );

        require ( !safeToAdd(balances[uint(to)], value) );

        allowed[from][msg.sender] -= value;
        balances[uint(from)] -= value;
        balances[uint(to)] += value;
        Transfer( from, to, value );
        return true;
    }

    // Function to approve a certain amount of tokens to certain address
    function approve(address spender, uint value)
      checkTransferStop
      returns (bool ok) {

      // To change the approve amount you first have to reduce the addresses`
      //  allowance to zero by calling `approve(_spender,0)` if it is not
      //  already 0 to mitigate the race condition described here:
      //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
      //
      //  Note that this doesn't prevent attacks; the user will have to personally
      //  check to ensure that the token count has not changed, before issuing
      //  a new approval. Increment/decrement is not commonly spec-ed, and
      //  changing to a check-my-approvals-before-changing would require user
      //  to find out his current approval for spender and change expected
      //  behaviour for ERC20.


      require ((value==0) && (allowed[msg.sender][spender] ==0));

      allowed[msg.sender][spender] = value;
      Approval( msg.sender, spender, value );
      return true;
    }

    // Function to record the token holders.
    function recordTokenMint (address _addr) internal {
      if (!existingTokenHolder[uint(_addr)]){
        tokenHolders.push(uint(_addr));
        existingTokenHolder[uint(_addr)] = true;
      }
    }


    function mint(address newTokenHolder, uint etherAmount)
      external
      onlyFromWallet {
          require (safeToMultiply(swapValue,etherAmount));
          uint tokensAmount = swapValue * etherAmount;

          require (safeToAdd(balances[uint(newTokenHolder)],tokensAmount ));
          require (safeToAdd(tokensSupplied,tokensAmount));

          require ((tokensSupplied + tokensAmount) <= tokenCap);

          balances[uint(newTokenHolder)] += tokensAmount;
          tokensSupplied += tokensAmount;

          recordTokenMint(newTokenHolder);

          Mint(newTokenHolder, tokensAmount);
    }

    function mintRemainingTokens(address beneficiary)
      external
      onlyFromWallet {
          require (tokenCap > tokensSupplied);
          require (safeToSub(tokenCap,tokensSupplied));
          uint tokensAmount = tokenCap - tokensSupplied;

          require (safeToAdd(balances[uint(beneficiary)], tokensAmount ));
          require (safeToAdd(tokensSupplied,tokensAmount));

          balances[uint(beneficiary)] += tokensAmount;
          tokensSupplied += tokensAmount;

          Mint(beneficiary, tokensAmount);
    }

    // Once activated, a new token contract will need to be created, mirroring the current token holdings.
    function stopToken() onlyFromWallet {
      transferStop = true;
    }


    function enableTokenKill()
      external
      onlyFromWallet {
          transferStop = false;
          TokenSaleOver();
    }
  }

pragma solidity ^0.4.11;

import "./Token.sol";

// This is the voting contract that will be used for calling the Proposals.
contract TACvoting {

  uint[128] public owners;

  uint public numOwners;

  mapping(uint => uint) ownerIndex;

  // The minimum debate period that a generic Proposal can have
  uint constant minProposalVoteDuration = 2 weeks;

  // Period after which a Proposal is closed
  // (used in the case `executeProposal` fails because it throws)
  uint constant maxProposalExecuteDuration = 10 days;

  uint minQuorumRequired;

  uint minQuorumDivisor;

  //token contract
  Token token;

  // Proposals to discuss TAC decisions
  Proposal[] public proposals;

  // The unix time of the last time quorum was reached on a Proposal
  uint public lastTimeMinQuorumMet;



  struct Proposal {
      // A plain text description of the Proposal
      string description;
      // A unix timestamp, denoting the end of the voting period
      uint votingDeadline;
      // True if the Proposal's votes have yet to be counted, otherwise False
      bool open;
      // True if quorum has been reached, the votes have been counted, and
      // the majority said yes
      bool proposalPassed;
      // A hash to check validity of a Proposal
      bytes32 proposalHash;
      // Deposit in wei the creator added when submitting their Proposal. It
      // is taken from the msg.value of a newProposal call.
      uint yea;
      // Number of Tokens opposed to the Proposal
      uint nay;
      // Simple mapping to check if a shareholder has voted for it
      mapping (address => bool) votedYes;
      // Simple mapping to check if a shareholder has voted against it
      mapping (address => bool) votedNo;
      // true if the Proposal is to change the token increment percentage
      // or dividend percentagey
      // true if the proposal is to change the token increment percentage
      // or dividend percentage
      bool specialProposal;
      //
      uint incrementPercentage;

  }

  // Map of addresses blocked during a vote (not allowed to transfer Titans
  // The address points to the Proposal ID.
  /*mapping (address => uint) public blocked;*/

  // Map of addresses and Proposal voted on by this address
  mapping (address => uint[]) public votingRegister;


  // avoids a Proposal with ID 0 because it is used
  event ProposalAdded(
      uint ProposalID,
      string description
  );

  // avoids a Proposal with ID 0 because it is used
  event SpecialProposalAdded(
      uint ProposalID,
      uint _incrementPercentage,
      string description
  );

  event Voted(uint ProposalID, bool position, address  voter);
  event ProposalTallied(uint ProposalID, bool result, uint quorum, string ProposalType);


  modifier onlyowner {
    require (ownerIndex[uint(msg.sender)] > 0);
    _;
  }

  function TACvoting (address[] _owners) {
      numOwners = _owners.length + 1;
      owners[1] = uint(msg.sender);
      ownerIndex[uint(msg.sender)] = 1;
      for (uint i = 0; i < _owners.length; ++i)
      {
          owners[2 + i] = uint(_owners[i]);
          ownerIndex[uint(_owners[i])] = 2 + i;
      }

      lastTimeMinQuorumMet = now;
      minQuorumDivisor = 2;
      proposals.length = 1; // avoids a Proposal with ID 0 because it is used
  }


  function newProposal (
        string _description,
        bytes _transactionData,
        uint64 _debatingPeriod
    ) onlyowner returns (uint _ProposalID) {

        require (_debatingPeriod >= minProposalVoteDuration
            && _debatingPeriod >= 8 weeks
           );


        _ProposalID = proposals.length++;
        Proposal p = proposals[_ProposalID];
        p.description = _description;
        p.proposalHash = sha3(_transactionData);
        p.votingDeadline = now + _debatingPeriod;
        p.open = true;

        //p.ProposalPassed = False; // that's default

        ProposalAdded(
            _ProposalID,
            _description
        );
    }

  function specialProposal (
        string _description,
        bytes _transactionData,
        uint64 _debatingPeriod,
        uint8 _incrementPercentage
    ) onlyowner returns (uint _proposalID) {

        require (_debatingPeriod >= minProposalVoteDuration
            && _debatingPeriod >= 8 weeks);

        require (_incrementPercentage < 100
        && _incrementPercentage >= 0);


        _proposalID = proposals.length++;
        Proposal p = proposals[_proposalID];
        p.description = _description;
        p.proposalHash = sha3(_transactionData);
        p.votingDeadline = now + _debatingPeriod;
        p.open = true;
        p.specialProposal = true;
        p.incrementPercentage = _incrementPercentage;
        //p.proposalPassed = False; // that's default

        SpecialProposalAdded(
            _proposalID,
            _incrementPercentage,
            _description
        );
    }



    function setTokenContract (address newTokenContractAddr) onlyowner {
        require (newTokenContractAddr != address(0x0));
        // Allow setting only once
        require (token == address(0x0));
        token = Token(newTokenContractAddr);
        minQuorumRequired = token.totalSupply() / minQuorumDivisor;
    }


    function vote (uint _ProposalID, bool _supportsProposal) {

        Proposal p = proposals[_ProposalID];

        unVote(_ProposalID);

        if (_supportsProposal) {
            p.yea += token.balanceOf(msg.sender);
            p.votedYes[msg.sender] = true;
        } else {
            p.nay += token.balanceOf(msg.sender);
            p.votedNo[msg.sender] = true;
        }


        votingRegister[msg.sender].push(_ProposalID);
        Voted(_ProposalID, _supportsProposal, msg.sender);
    }



    function unVote(uint _ProposalID){
          Proposal p = proposals[_ProposalID];

          if (now >= p.votingDeadline) {
              throw;
          }

          if (p.votedYes[msg.sender]) {
              p.yea -= token.balanceOf(msg.sender);
              p.votedYes[msg.sender] = false;
          }

          if (p.votedNo[msg.sender]) {
              p.nay -= token.balanceOf(msg.sender);
              p.votedNo[msg.sender] = false;
          }
      }


    function minQuorum() internal constant returns (uint _minQuorum) {
        // minimum of 14.3% and maximum of 47.6%
        return token.totalSupply() / minQuorumDivisor;
    }


    function executeProposal (
        uint _ProposalID,
        bytes _transactionData
    ) onlyowner returns (bool _success) {

        Proposal p = proposals[_ProposalID];

        // If we are over deadline and waiting period, assert Proposal is closed
        if (p.open && now > p.votingDeadline + maxProposalExecuteDuration) {
            closeProposal(_ProposalID);
            return;
        }

        // Check if the Proposal can be executed
        if (now < p.votingDeadline  // has the voting deadline arrived?
            // Have the votes been counted?
            || !p.open
            || p.proposalPassed // anyone trying to call us recursively?
            // Does the transaction code match the Proposal?
            || p.proposalHash != sha3(_transactionData)
            )
                throw;


                uint quorum = p.yea + p.nay;

               // require max quorum
               if (quorum >= minQuorum()) {
                   lastTimeMinQuorumMet = now;
               }

               // Execute result
               if (quorum >= minQuorum() && p.yea > p.nay) {

                   p.proposalPassed = true;


                   _success = true;
                   if (p.specialProposal) {

                   token.addIncrement(p.incrementPercentage);
                  }



               }

               closeProposal(_ProposalID);

               // Initiate event
               if (p.specialProposal) {
               ProposalTallied(_ProposalID, _success, quorum, "Special Proposal");
               }
               else {
               ProposalTallied(_ProposalID, _success, quorum, "General Proposal");
               }
           }


    function diluteWaitPeriod (uint _proposalID, string _transactionData) {

        Proposal p = proposals[_proposalID];

        require (p.proposalHash == sha3(_transactionData));
        p.votingDeadline = now;
    }
    // closes the proposal once the proposal has been executed
    function closeProposal(uint _ProposalID) internal {
        Proposal p = proposals[_ProposalID];
        if (p.open)
        p.open = false;
    }
}

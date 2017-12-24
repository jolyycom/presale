pragma solidity ^0.4.13;

/* Math operations with safety checks that throw on error */
library SafeMath {
    function mul(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal constant returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

/* The owned contract has an owner address, and provides 
basic authorization control functions, this simplifies 
the implementation of "user permissions" */
contract owned {
	address public owner;

	/* The owned constructor sets the original `owner` of the contract to the sender account */
	function owned() public {
		owner = msg.sender;
	}

	/* Throws if called by any account other than the owner */
	modifier onlyOwner() {
		require(msg.sender == owner);
		_;
	}
	
	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
	/** Allows the current owner to transfer control of the contract to a newOwner */
	function transferOwnership(address newOwner) public onlyOwner {
	    address prevOwn = owner;
		owner = newOwner;
		OwnershipTransferred(prevOwn, newOwner);
	}
}

/* ERC20 interface */
contract token {
    function balanceOf(address _owner) public constant returns (uint256 _balance);
    function transfer(address _to, uint256 _value) public returns (bool _success);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool _success);
    function approve(address _spender, uint256 _value) public returns (bool _success);
    function allowance(address _owner, address _spender) public constant returns (uint256 _remaining);
	/* This generates a public event on the blockchain that will notify clients */
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract tokenRecipient {
	function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; 
}

contract JolyyToken is owned, token {
	using SafeMath for uint256;
	/* Public variables of the token */
	string public name;
	string public symbol;
	uint8 public decimals;
	uint256 public totalSupply;
	
	bool public canTransfer;

	modifier onlyPayloadSize(uint numwords) {
        assert(msg.data.length == numwords * 32 + 4);
		_;
	}
	
	/* This creates an array with all balances */
	mapping (address => uint256) public balances;
	mapping (address => mapping (address => uint256)) public allowed;
	
	event Burn(address indexed from, uint256 value);

	/* Initializes contract with initial supply tokens to the creator of the contract */
	function JolyyToken() public {
		name = "Jolyy";                                   	// Set the name for display purposes
		symbol = "JOY";                               		// Set the symbol for display purposes
		decimals = 18;                            			// Amount of decimals for display purposes
		totalSupply = SafeMath.mul(30000000, 1 ether);      // Update total supply
		balances[msg.sender] = totalSupply;              	// Give the creator all initial tokens
		canTransfer = false;
	}
	
	function approveTransfers() public onlyOwner {
		canTransfer = true;
	}
	
	/* Internal transfer, only can be called by this contract */
	function _transfer(address _from, address _to, uint _value) internal {
		require (_to != address(0));                               				// Prevent transfer to 0x0 address. Use burn() instead
		require(canTransfer || msg.sender == owner);
		require (balances[_from] >= _value);                					// Check if the sender has enough
		require (SafeMath.add(balances[_to], _value) >= balances[_to]); 					// Check for overflows
		balances[_from] = SafeMath.sub(balances[_from], _value);        				   	// Subtract from the sender
		balances[_to] = SafeMath.add(balances[_to], _value);                            	// Add the same to the recipient
		Transfer(_from, _to, _value);
	}

	function transfer(address _to, uint256 _value) onlyPayloadSize(2) public returns (bool _success) {
		_transfer(msg.sender, _to, _value);
		return true;
	}

	function transferFrom(address _from, address _to, uint256 _value) public onlyPayloadSize(3) returns (bool success) {
		require (_value <= allowed[_from][msg.sender]);     					// Check allowance
		allowed[_from][msg.sender] = SafeMath.sub(allowed[_from][msg.sender], _value);
		_transfer(_from, _to, _value);
		return true;
	}
	
    /* Approve the passed address to spend the specified amount of tokens on behalf of msg.sender */
	function approve(address _spender, uint256 _value) public returns (bool success) {
		allowed[msg.sender][_spender] = _value;
		Approval(msg.sender, _spender, _value);
		return true;
	}

	function approveAndCall(address _spender, uint256 _value, bytes _extraData) public returns (bool success) {
		tokenRecipient spender = tokenRecipient(_spender);
		if (approve(_spender, _value)) {
		  spender.receiveApproval(msg.sender, _value, this, _extraData);
		  return true;
		}
	}
	
	/* Burns a specific amount of tokens. */
    function burn(uint256 _value) public onlyOwner returns (bool success) {
        require (balances[msg.sender] >= _value);            				// Check if the sender has enough
		transfer(0x0, _value);
        balances[msg.sender] = SafeMath.sub(balances[msg.sender], _value);  // Subtract from the sender
        totalSupply = SafeMath.sub(totalSupply, _value);                    // Updates totalSupply
        Burn(msg.sender, _value);
        return true;
    }

	/*  Function to check the amount of tokens that an owner allowed to a spender */
	function allowance(address _owner, address _spender) onlyPayloadSize(2) public constant returns (uint256) {
		return allowed[_owner][_spender];
	}

	function balanceOf(address _owner) public constant returns (uint256 _balance) {
		return balances[_owner];
	}
}        

contract JolyyPreSale is owned {
	using SafeMath for uint256;
	
    uint256 public fundingGoal;
    uint256 public amountRaised;

	uint256 public preSaleStart;
	uint256 public preSaleEnds;
	uint256 public SoldTokens;
	uint256 public price;
	uint256 public Cap;
	
	JolyyToken public tokenReward;
	
	address public team;
	address public company;
	address	public bounty;
	
    mapping(address => uint256) public balanceOf;
	
	bool public isActive;
    bool public fundingGoalReached;
    bool public crowdsaleClosed;

    modifier afterDeadline() { 
		require(block.timestamp >= preSaleEnds);
		_; 
	}
	
    event GoalReached(address indexed _recipient, uint256 _totalAmountRaised);

    function JolyyPreSale(address _JollyAddress) public {
        fundingGoal = SafeMath.mul(500, 1 ether);
        amountRaised = 0;
        tokenReward = JolyyToken(_JollyAddress);
		Cap = SafeMath.mul(12500000, 1 ether);
		isActive = false;
		fundingGoalReached = false;
		crowdsaleClosed = false;
		team = 0x591f7bBAc47d693cb1e39177608F43e2fBb12619;
		company = 0x3ADC439df5d035663089e588975857ECBc27e750;
		bounty = 0xf7Bc105cCAdC3C9032a2eD60339F8F490Dc16B44;
    }
	
	function preSaleActivete(uint256 _price) public onlyOwner {
		require(!isActive && !crowdsaleClosed);
		price = _price;
		preSaleStart = block.timestamp;
		uint256 durationInDays = SafeMath.mul(15, 1 days);
		preSaleEnds = SafeMath.add(preSaleStart, durationInDays);
		isActive = true;
	}
	
    event FundTransfer(address indexed _backer, uint256 amount, bool _isContribution);
    function() payable {
		require(!crowdsaleClosed);
		uint256 amount = msg.value;
		if(isActive) {
			require(fundingGoal >= amountRaised.add(amount));
			require(msg.value >= 2 ether && msg.value <= 25 ether);
			uint256 tokens = SafeMath.div(amount, price);
			tokens = tokens.mul(1 ether);
			require(Cap >= (SafeMath.add(SoldTokens, tokens)));
			balanceOf[msg.sender] = SafeMath.add(balanceOf[msg.sender], amount);
			
			SoldTokens = SafeMath.add(SoldTokens, tokens);
			token(tokenReward).transfer(msg.sender, tokens);
			amountRaised = SafeMath.add(amountRaised, amount);
			FundTransfer(msg.sender, amount, true);
		} else {
			revert();
		}
		
		if(this.balance >= fundingGoal && !fundingGoalReached) {
			fundingGoalReached = true;
			GoalReached(owner, amountRaised);
		}	
    }
    
    
	function transferEth(uint256 _amount) internal {
		require(amountRaised >= uint256(495).mul( 1 ether));
		owner.transfer(_amount);
		EthTransfered(owner, _amount);
	}
	
	function transferTeamTokens() internal {
		token(tokenReward).transfer(team, SafeMath.mul(3000000, 1 ether));
		token(tokenReward).transfer(company, SafeMath.mul(6000000, 1 ether));
		token(tokenReward).transfer(bounty, SafeMath.mul(3000000, 1 ether));
	}
	
    event EthTransfered(address _owner, uint256 _value);
    function ClosePresale() public onlyOwner afterDeadline {
        crowdsaleClosed = true;
        isActive = false;
        transferEth(this.balance);
        transferTeamTokens();
		uint256 remaining = token(tokenReward).balanceOf(this);
		token(tokenReward).transfer(owner,remaining);
		JolyyToken(tokenReward).transferOwnership(owner);
    }
}

# @version 0.3.10
from vyper.interfaces import ERC20

event UpdatedMinimumPaymentAmount:
    tokenFrom: indexed(address)
    oldMinimumPaymentAmount: indexed(uint256)
    newMinimumPaymentAmount: indexed(uint256)


struct GPv2Order_Data:
    sellToken: ERC20  # token to sell
    buyToken: ERC20  # token to buy
    receiver: address  # receiver of the token to buy
    sellAmount: uint256
    buyAmount: uint256
    validTo: uint32  # timestamp until order is valid
    appData: bytes32  # extra info about the order
    feeAmount: uint256  # amount of fees in sellToken
    kind: bytes32  # buy or sell
    partiallyFillable: bool  # partially fillable (True) or fill-or-kill (False)
    sellTokenBalance: bytes32  # From where the sellToken balance is withdrawn
    buyTokenBalance: bytes32  # Where the buyToken is deposited

struct AuctionInfo:
    epochId: uint256
    startTime: uint256
    startPrice: uint256
    minimumPaymentAmount: uint256

WAD: constant(uint256) = 10 ** 18
MAX_COINS_LEN: constant(uint256) = 64
ERC1271_MAGIC_VALUE: constant(bytes4) = 0x1626ba7e
ETH_ADDRESS: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE

governance: public(immutable(address))

vaultRelayer: public(immutable(address))

cowSettlement: public(immutable(address))

paymentToken: public(immutable(address))

auctionLength: public(immutable(uint256))

paymentReceiver: public(immutable(address))

priceMultiplier: public(uint256)

auctions: public(HashMap[address, AuctionInfo])

@external
def __init__(
    _governance: address, 
    _vault_relayer: address, 
    _cow_settlement: address,
    _target_threshold: uint256,
    _payment_token: address,
    _auction_length: uint256,
    _payment_receiver: address,
    _price_multiplier: uint256,
):
    """
    @notice Contract constructor
    @param _vault_relayer CowSwap's VaultRelayer contract address, all approves go there
    @param _target_threshold Minimum amount of target to buy per order
    """
    governance = _governance
    vaultRelayer = _vault_relayer
    cowSettlement = _cow_settlement
    paymentToken = _payment_token
    auctionLength = _auction_length
    paymentReceiver = _payment_receiver
    self.priceMultiplier = _price_multiplier

@view
@external
def price(token_from: address, timestamp: uint256 = block.timestamp) -> uint256:
    return self._price(token_from, timestamp)
    

@view
@internal
def _price(token_from: address, timestamp: uint256) -> uint256:
    auction_info: AuctionInfo = self.auctions[token_from]
    assert auction_info.startTime != 0, "!valid from"

    time_elapsed: uint256 = timestamp - auction_info.startTime
    to_add: uint256 = 0
    
    if time_elapsed < auctionLength:
        difference: uint256 = auction_info.startPrice - auction_info.minimumPaymentAmount
        if difference != 0:
            to_add = difference - (difference * time_elapsed / auctionLength)

    return auction_info.minimumPaymentAmount + to_add

@external
def preTake(token_from: address):
    assert msg.sender == cowSettlement, "!settlement"
    auction_info: AuctionInfo = self.auctions[token_from]
    assert auction_info.startTime != 0, "!valid from"

    balance: uint256 = ERC20(token_from).balanceOf(self) # Todo custom amounts to take
    assert balance > 0
    assert ERC20(token_from).approve(vaultRelayer, balance, default_return_value=True)

    self._roll_epoch(auction_info)

@view
@external
def isValidSignature(_hash: bytes32, signature: Bytes[1792]) -> bytes4:
    """
    @notice ERC1271 signature verifier method
    @param _hash Hash of signed object. Ignored here
    @param signature Signature for the object. (GPv2Order.Data) here
    @return `ERC1271_MAGIC_VALUE` if signature is OK
    """
    order: GPv2Order_Data =  _abi_decode(signature, (GPv2Order_Data))
    # Verify's the auction is valid
    price: uint256 = self._price(order.sellToken.address, block.timestamp)

    # Verify order details
    assert order.buyAmount >= price, "bad price"
    assert order.buyToken.address == paymentToken, "bad token"
    assert order.receiver == paymentReceiver, "bad receiver"
    assert order.sellAmount <= order.sellToken.balanceOf(self)

    # Should be a pre-hook
    assert order.appData != empty(bytes32)

    return ERC1271_MAGIC_VALUE

@internal
def _roll_epoch(auction_info: AuctionInfo):
    auction_info.epochId = unsafe_add(auction_info.epochId, 1) # Okay to overflow
    auction_info.startTime = block.timestamp
    auction_info.startPrice = max(auction_info.startPrice * self.priceMultiplier / WAD, auction_info.minimumPaymentAmount)


@external
def setMinimumPaymentAmount(token_from: address, minimum_payment_amount: uint256):
    assert msg.sender == governance, "!gov"

    auction_info: AuctionInfo = self.auctions[token_from]
    assert self.auctions[token_from].startTime != 0, "!valid from"
    
    old_amount: uint256 = auction_info.minimumPaymentAmount

    price: uint256 = self._price(token_from, block.timestamp)

    # If the price is under the new minimum
    if price < minimum_payment_amount:
        # Change the version in memory
        auction_info.minimumPaymentAmount = minimum_payment_amount
        # Reset Values
        self._roll_epoch(auction_info)

    # Set storage.
    self.auctions[token_from].minimumPaymentAmount = minimum_payment_amount

    log UpdatedMinimumPaymentAmount(token_from, old_amount, minimum_payment_amount)



@external
def recover(_coins: DynArray[ERC20, MAX_COINS_LEN]):
    """
    @notice Recover ERC20 tokens or Ether from this contract
    @dev Callable only by owner and emergency owner
    @param _coins Token addresses
    """
    assert msg.sender == governance, "!governance"

    for coin in _coins:
        if coin.address == ETH_ADDRESS:
            raw_call(governance, b"", value=self.balance)
        else:
            coin.transfer(governance, coin.balanceOf(self), default_return_value=True)  # do not need safe transfer
# @version 0.3.10
from vyper.interfaces import ERC20
from vyper.interfaces import ERC20Detailed

event UpdatedPaymentAmount:
    tokenFrom: indexed(address)
    oldPaymentAmount: indexed(uint256)
    newPaymentAmount: indexed(uint256)


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

WAD: constant(uint256) = 10 ** 18
MAX_COINS_LEN: constant(uint256) = 20
ERC1271_MAGIC_VALUE: constant(bytes4) = 0x1626ba7e
ETH_ADDRESS: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE

governance: public(immutable(address))

cowSettlement: public(immutable(address))

paymentToken: public(immutable(address))

paymentScaler: immutable(uint256)

paymentReceiver: public(immutable(address))

paymentAmount: public(HashMap[address, uint256])

@external
def __init__(
    _governance: address, 
    _cow_settlement: address,
    _payment_token: address,
    _payment_receiver: address,
):
    """
    @notice Contract constructor
    """
    governance = _governance
    cowSettlement = _cow_settlement
    paymentToken = _payment_token
    paymentScaler = WAD / pow_mod256(10, convert(ERC20Detailed(_payment_token).decimals(), uint256))
    paymentReceiver = _payment_receiver

@view
@external
def price(token_from: address) -> uint256:
    return self._price(token_from)
    

@view
@internal
def _price(token_from: address) -> uint256:
    payment_amount: uint256 = self.paymentAmount[token_from]
    balance: uint256 = ERC20(token_from).balanceOf(self)

    if payment_amount == 0 or balance == 0:
        return 0

    scaler: uint256 = WAD / pow_mod256(10, convert(ERC20Detailed(token_from).decimals(), uint256))

    return payment_amount * paymentScaler * WAD / (balance * scaler) / paymentScaler


@external
def take(token_from: address) -> uint256:
    payment_amount: uint256 = self.paymentAmount[token_from]
    assert payment_amount != 0, "zero amount"

    balance: uint256 = ERC20(token_from).balanceOf(self)

    assert ERC20(token_from).transfer(msg.sender, balance, default_return_value=True)

    ERC20(paymentToken).transferFrom(msg.sender, paymentReceiver, payment_amount, default_return_value=True)

    return balance
    

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
    payment_amount: uint256 = self.paymentAmount[order.sellToken.address]

    # Verify order details
    assert payment_amount > 0, "zero amount"
    assert order.buyAmount >= payment_amount, "bad price"
    assert order.buyToken.address == paymentToken, "bad token"
    assert order.receiver == paymentReceiver, "bad receiver"
    assert order.sellAmount <= order.sellToken.balanceOf(self)

    return ERC1271_MAGIC_VALUE

@external
def setPaymentAmount(token_from: address, payment_amount: uint256):
    """
    @notice This is how governance will enable and disable tokens as well as 
        change the amount for each token that needs to be used to buy
    """
    assert msg.sender == governance, "!gov"

    old_amount: uint256 = self.paymentAmount[token_from]
    
    # If enabling the token.
    if old_amount == 0:
        # Max approve the settlement contract
        assert ERC20(token_from).approve(cowSettlement, max_value(uint256), default_return_value=True)
    
    # If disabling the token.
    if payment_amount == 0:
        # Remove the approval from the settlement contract
        assert ERC20(token_from).approve(cowSettlement, 0, default_return_value=True)
    
    # Set storage.
    self.paymentAmount[token_from] = payment_amount

    log UpdatedPaymentAmount(token_from, old_amount, payment_amount)


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
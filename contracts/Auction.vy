# @version 0.3.10
from vyper.interfaces import ERC20

event UpdatedMinimumPaymentAmount:
    oldMinimumPaymentAmount: indexed(uint256)
    newMinimumPaymentAmount: indexed(uint256)

event UpdatedPriceMultiplier:
    oldPriceMultiplier: indexed(uint256)
    newPriceMultiplier: indexed(uint256)

event Buy:
    buyer: indexed(address)
    assets_receiver: indexed(address)
    payment_amount: uint256

WAD: constant(uint256) = 10 ** 18

governance: public(immutable(address))

paymentToken: public(immutable(address))

auctionLength: public(immutable(uint256))

paymentReceiver: public(immutable(address))

epochId: public(uint256)

startTime: public(uint256)

startPrice: public(uint256)

priceMultiplier: public(uint256)

minimumPaymentAmount: public(uint256)

#### TODO:

# 1. Call back hook during buy?
# 2. Init with a 0 min that works
# 3. $0 payment fills rek forever
# 4. Pack storage

@external
def __init__(
    gov: address,
    payment_token: address,
    auction_length: uint256,
    payment_receiver: address,
    price_multiplier: uint256,
    minimum_payment_amount: uint256,
):
    governance = gov
    paymentToken = payment_token
    auctionLength = auction_length
    paymentReceiver = payment_receiver
    self.priceMultiplier = price_multiplier
    self.minimumPaymentAmount = minimum_payment_amount
    self.startTime = block.timestamp
    self.startPrice = max(minimum_payment_amount * price_multiplier / WAD, minimum_payment_amount)


@external
def buy(
    assets: DynArray[address, 20],
    assets_receiver: address,
    epochId: uint256,
) -> uint256:

    _epochId: uint256 = self.epochId
    assert epochId == _epochId

    payment: uint256 = self._price(block.timestamp)

    assert ERC20(paymentToken).transferFrom(msg.sender, paymentReceiver, payment, default_return_value=True)

    for asset in assets:
        assert ERC20(asset).transfer(assets_receiver, ERC20(asset).balanceOf(self), default_return_value=True)

    log Buy(msg.sender, assets_receiver, payment)

    self.epochId = unsafe_add(_epochId, 1)
    self.startTime = block.timestamp
    self.startPrice = max(payment * self.priceMultiplier / WAD, self.minimumPaymentAmount)

    return payment


@view
@external
def price(timestamp: uint256 = block.timestamp) -> uint256:
    return self._price(timestamp)
    

@view
@internal
def _price(timestamp: uint256) -> uint256:
    min_payment: uint256 = self.minimumPaymentAmount
    time_elapsed: uint256 = timestamp - self.startTime
    to_add: uint256 = 0
    
    if time_elapsed < auctionLength:
        difference: uint256 = self.startPrice - min_payment
        if difference != 0:
            to_add = difference - (difference * time_elapsed / auctionLength)

    return min_payment + to_add


@external
def setMinimumPaymentAmount(minimum_payment_amount: uint256):
    assert msg.sender == governance, "!gov"
    old_amount: uint256 = self.minimumPaymentAmount

    price: uint256 = self._price(block.timestamp)

    # If the price is under the current minimum
    if price < minimum_payment_amount:
        # Reset Values
        self.epochId = unsafe_add(self.epochId, 1)
        self.startTime = block.timestamp
        self.startPrice = max(self.startPrice * self.priceMultiplier / WAD, minimum_payment_amount)

    self.minimumPaymentAmount = minimum_payment_amount

    log UpdatedMinimumPaymentAmount(old_amount, minimum_payment_amount)


@external
def setPriceMultiplier(price_multiplier: uint256):
    assert msg.sender == governance, "!gov"
    old_multiplier: uint256 = self.priceMultiplier
    self.priceMultiplier = price_multiplier

    log UpdatedPriceMultiplier(old_multiplier, price_multiplier)
import ape
from ape import chain, reverts
from utils.constants import MAX_INT, WEEK, ZERO_ADDRESS


def test_auction_setup(auction, daddy, fee_recipient, want):
    assert auction.governance() == daddy
    assert auction.paymentToken() == want
    assert auction.auctionLength() == WEEK
    assert auction.paymentReceiver() == fee_recipient
    assert auction.epochId() == 0
    assert auction.startTime() != 0
    assert auction.startTime() < chain.pending_timestamp
    assert auction.startPrice() == int(20_000e18)
    assert auction.priceMultiplier() == 2e18
    assert auction.minimumPaymentAmount() == 10_000e18


def test_price(auction, daddy, user):
    old = int(2e18)
    new = int(0)

    assert auction.priceMultiplier() == old
    price = auction.price()
    assert price > old

    with ape.reverts("revert: !gov"):
        auction.setPriceMultiplier(new, sender=user)

    tx = auction.setPriceMultiplier(new, sender=daddy)

    assert auction.priceMultiplier() == new
    assert auction.price() <= price

    logs = list(tx.decode_logs(auction.UpdatedPriceMultiplier))

    assert len(logs) == 1
    assert logs[0].oldPriceMultiplier == old
    assert logs[0].newPriceMultiplier == new


def test_set_minimum_amount(auction, daddy, user):
    old_min = int(10_000e18)
    new_min = int(0)

    assert auction.minimumPaymentAmount() == old_min
    price = auction.price()
    assert price > old_min

    with ape.reverts("revert: !gov"):
        auction.setMinimumPaymentAmount(new_min, sender=user)

    tx = auction.setMinimumPaymentAmount(new_min, sender=daddy)

    assert auction.minimumPaymentAmount() == new_min
    assert auction.price() <= price

    logs = list(tx.decode_logs(auction.UpdatedMinimumPaymentAmount))

    assert len(logs) == 1
    assert logs[0].oldMinimumPaymentAmount == old_min
    assert logs[0].newMinimumPaymentAmount == new_min

    # Set it higher
    old_min = new_min
    new_min = int(100_000e18)

    tx = auction.setMinimumPaymentAmount(new_min, sender=daddy)

    assert auction.minimumPaymentAmount() == new_min
    assert auction.price() > price
    assert auction.price() == new_min
    assert auction.startTime() == chain.pending_timestamp - 1
    assert auction.startPrice() == new_min

    logs = list(tx.decode_logs(auction.UpdatedMinimumPaymentAmount))

    assert len(logs) == 1
    assert logs[0].oldMinimumPaymentAmount == old_min
    assert logs[0].newMinimumPaymentAmount == new_min


def test_set_price_multiplier(auction, daddy, user):
    pass


def test_buy(auction, fee_recipient, want, create_token, fee_buyer, asset_receiver):
    pass

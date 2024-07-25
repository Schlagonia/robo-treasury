import pytest
from ape import accounts, project, networks
from utils.constants import MAX_INT, WEEK, ZERO_ADDRESS


@pytest.fixture(scope="session")
def daddy(accounts):
    yield accounts[0]


@pytest.fixture(scope="session")
def user(accounts):
    yield accounts[1]


@pytest.fixture(scope="session")
def fee_recipient(accounts):
    yield accounts[2]


@pytest.fixture(scope="session")
def asset_receiver(accounts):
    yield accounts[3]


@pytest.fixture(scope="session")
def fee_buyer(accounts):
    yield accounts[4]


@pytest.fixture(scope="session")
def create_token(project, daddy, user, amount):
    def create_token(initialUser=user, initialAmount=amount):
        token = daddy.deploy(project.MockERC20)

        token.mint(initialUser, initialAmount, sender=daddy)

        return token

    yield create_token


@pytest.fixture(scope="session")
def want(create_token):
    yield create_token()


@pytest.fixture(scope="session")
def amount():
    return int(1_000 * 1e18)


@pytest.fixture(scope="session")
def deploy_auction(project, daddy, fee_recipient, want):
    def deploy_auction(
        gov=daddy,
        payment_token=want,
        payment_receiver=fee_recipient,
        auction_length=WEEK,
        price_multiplier=int(2e18),
        min_payment_amount=int(10_000e18),
    ):
        auction = gov.deploy(
            project.Auction,
            gov,
            payment_token,
            auction_length,
            payment_receiver,
            price_multiplier,
            min_payment_amount,
        )

        return auction

    yield deploy_auction


@pytest.fixture(scope="session")
def auction(deploy_auction):
    yield deploy_auction()

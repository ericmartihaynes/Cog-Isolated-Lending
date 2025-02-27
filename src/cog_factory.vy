# @version 0.3.9

"""
@title Cog Factory

@license GNU Affero General Public License v3.0
@author Cog Finance
@notice A priviledged factory for creating Cog Pairs and managing their protocol-owned liquidity
"""

# ///////////////////////////////////////////////////// #
#                  2Step Ownership                      #
# ///////////////////////////////////////////////////// #

# @dev Returns the address of the current owner.
owner: public(address)


# @dev Returns the address of the pending owner.
pending_owner: public(address)


# @dev Emitted when the ownership transfer from
# `previous_owner` to `new_owner` is initiated.
event OwnershipTransferStarted:
    previous_owner: indexed(address)
    new_owner: indexed(address)


# @dev Emitted when the ownership is transferred
# from `previous_owner` to `new_owner`.
event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)


@external
def transfer_ownership(new_owner: address):
    """
    @dev Starts the ownership transfer of the contract
         to a new account `new_owner`.
    @notice Note that this function can only be
            called by the current `owner`. Also, there is
            no security risk in setting `new_owner` to the
            zero address as the default value of `pending_owner`
            is in fact already the zero address and the zero
            address cannot call `accept_ownership`. Eventually,
            the function replaces the pending transfer if
            there is one.
    @param new_owner The 20-byte address of the new owner.
    """
    self._check_owner()
    self.pending_owner = new_owner
    log OwnershipTransferStarted(self.owner, new_owner)


@external
def accept_ownership():
    """
    @dev The new owner accepts the ownership transfer.
    @notice Note that this function can only be
            called by the current `pending_owner`.
    """
    assert (
        self.pending_owner == msg.sender
    ), "Ownable2Step: caller is not the new owner"
    self._transfer_ownership(msg.sender)


@external
def renounce_ownership():
    """
    @dev Sourced from {Ownable-renounce_ownership}.
    @notice See {Ownable-renounce_ownership} for
            the function docstring.
    """
    self._check_owner()
    self._transfer_ownership(empty(address))


@internal
def _check_owner():
    """
    @dev Throws if the sender is not the owner.
    """
    assert msg.sender == self.owner, "Ownable2Step: caller is not the owner"


@internal
def _transfer_ownership(new_owner: address):
    """
    @dev Transfers the ownership of the contract
         to a new account `new_owner` and deletes
         any pending owner.
    @notice This is an `internal` function without
            access restriction.
    @param new_owner The 20-byte address of the new owner.
    """
    self.pending_owner = empty(address)
    old_owner: address = self.owner
    self.owner = new_owner
    log OwnershipTransferred(old_owner, new_owner)


interface ICogPair:
    def update_borrow_fee(newFee: uint256): nonpayable
    def update_default_protocol_fee(newFee: uint256): nonpayable
    def pause(): nonpayable
    def unpause(): nonpayable


# ///////////////////////////////////////////////////// #
#                       Events                          #
# ///////////////////////////////////////////////////// #

event StablePairCreated:
    asset: indexed(address)
    collateral: indexed(address)
    pair: indexed(address)


event LowPairCreated:
    asset: indexed(address)
    collateral: indexed(address)
    pair: indexed(address)


event MediumPairCreated:
    asset: indexed(address)
    collateral: indexed(address)
    pair: indexed(address)


event HighPairCreated:
    asset: indexed(address)
    collateral: indexed(address)
    pair: indexed(address)


event CustomPairCreated:
    blueprint: indexed(address)
    pair: indexed(address)
    asset: address
    collateral: address


blueprint: immutable(address)

priv_users: public(HashMap[address, bool])

fee_to: public(address)


# ///////////////////////////////////////////////////// #
#                     Ownership Functions               #
# ///////////////////////////////////////////////////// #

@external
def set_priv_user_status(user: address, status: bool):
    """
    @dev Sets the status of a priviledged user

    @param user The address of the user
    @param status The status to set the user to
    """
    self._check_owner()
    self.priv_users[user] = status


@external
def update_borrow_fee(pair: address, newFee: uint256):
    """
    @param pair The address of the pair to change the fee of
    @param newFee The fee to change the borrow fee to
    """
    self._check_owner()
    ICogPair(pair).update_borrow_fee(newFee)


@external
def update_default_protocol_fee(pair: address, newFee: uint256):
    """
    @dev Sets the default protocol fee on a given pair

    @param pair The address of the pair to change the fee of
    @param newFee The fee to change the default protocol fee to for the given pair
    """
    self._check_owner()
    ICogPair(pair).update_default_protocol_fee(newFee)


@external
def change_fee_to(new_recipient: address):
    """
    @param new_recipient The address to which protocol fees are sent
    """
    self._check_owner()
    self.fee_to = new_recipient


@external
def pause(pair: address):
    """
    @dev Pauses a given pair

    @param pair The address of the pair to pause
    """
    assert (self.priv_users[msg.sender] == True)
    ICogPair(pair).pause()


@external
def unpause(pair: address):
    """
    @dev Unpauses a given pair

    @param pair The address of the pair to unpause
    """
    assert (self.priv_users[msg.sender] == True)
    ICogPair(pair).unpause()


@external
def __init__(_blueprint: address, _fee_to: address):
    """
    @dev Initializes the factory

    @param _blueprint The address of the blueprint to use for pair deployment
    @param _fee_to The address to which protocol fees are sent
    """
    blueprint = _blueprint
    self.fee_to = _fee_to
    self._transfer_ownership(msg.sender)


# ///////////////////////////////////////////////////// #
#               Pair Deployment Functions               #
# ///////////////////////////////////////////////////// #

# Approx. 1% APR for interest_per_second
ONE_PERCENT: constant(uint64) = 317097920

@external
def deploy_stable_risk_pair(
    asset: address, collateral: address, oracle: address
) -> address:
    """
    @dev Deploy a stable risk pair

    @param asset The address of the asset token
    @param collateral The address of the collateral token
    @param oracle The address of the oracle to use for the pair

    @return pair The address of the deployed pair
    """

    # 15% minimum utilization, 35% maximum utilization
    MINIMUM_TARGET_UTILIZATION: uint256 = 150000000000000000
    MAXIMUM_TARGET_UTILIZATION: uint256 = 350000000000000000

    # 2% minimum APR, 5% starting APR, 25% maximum APR
    STARTING_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 5)
    MINIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 2)
    MAXIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 25)

    INTEREST_ELASTICITY: uint256 = 28800000000000000000000000000000000000000

    pair: address = create_from_blueprint(
        blueprint,
        asset,
        collateral,
        oracle,
        MINIMUM_TARGET_UTILIZATION,
        MAXIMUM_TARGET_UTILIZATION,
        STARTING_INTEREST_PER_SECOND,
        MINIMUM_INTEREST_PER_SECOND,
        MAXIMUM_INTEREST_PER_SECOND,
        INTEREST_ELASTICITY,
        code_offset=3,
    )
    log StablePairCreated(asset, collateral, pair)
    return pair


@external
def deploy_low_risk_pair(
    asset: address, collateral: address, oracle: address
) -> address:
    """
    @dev Deploy a low risk pair

    @param asset The address of the asset token
    @param collateral The address of the collateral token
    @param oracle The address of the oracle to use for the pair

    @return pair The address of the deployed pair
    """

    # 20% minimum utilization, 40% maximum utilization
    MINIMUM_TARGET_UTILIZATION: uint256 = 200000000000000000
    MAXIMUM_TARGET_UTILIZATION: uint256 = 400000000000000000

    # 2% minimum interest per second, 5% starting interest per second, 35% maximum interest per second
    STARTING_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 5)
    MINIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 2)
    MAXIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 35)

    INTEREST_ELASTICITY: uint256 = 28800000000000000000000000000000000000000

    pair: address = create_from_blueprint(
        blueprint,
        asset,
        collateral,
        oracle,
        MINIMUM_TARGET_UTILIZATION,
        MAXIMUM_TARGET_UTILIZATION,
        STARTING_INTEREST_PER_SECOND,
        MINIMUM_INTEREST_PER_SECOND,
        MAXIMUM_INTEREST_PER_SECOND,
        INTEREST_ELASTICITY,
        code_offset=3,
    )

    log LowPairCreated(asset, collateral, pair)
    return pair


@external
def deploy_medium_risk_pair(
    asset: address, collateral: address, oracle: address
) -> address:
    """
    @dev Deploy a medium risk pair

    @param asset The address of the asset token
    @param collateral The address of the collateral token
    @param oracle The address of the oracle to use for the pair

    @return pair The address of the deployed pair
    """

    # 60% minimum utilization, 60% maximum utilization
    MINIMUM_TARGET_UTILIZATION: uint256 = 500000000000000000
    MAXIMUM_TARGET_UTILIZATION: uint256 = 600000000000000000

    # 4% minimum APR, 1% starting APR, 150% maximum APR
    STARTING_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 7)
    MINIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 4)
    MAXIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 150)

    INTEREST_ELASTICITY: uint256 = 28800000000000000000000000000000000000000

    pair: address = create_from_blueprint(
        blueprint,
        asset,
        collateral,
        oracle,
        MINIMUM_TARGET_UTILIZATION,
        MAXIMUM_TARGET_UTILIZATION,
        STARTING_INTEREST_PER_SECOND,
        MINIMUM_INTEREST_PER_SECOND,
        MAXIMUM_INTEREST_PER_SECOND,
        INTEREST_ELASTICITY,
        code_offset=3,
    )
    log MediumPairCreated(asset, collateral, pair)
    return pair


@external
def deploy_high_risk_pair(
    asset: address, collateral: address, oracle: address
) -> address:
    """
    @dev Deploy a high risk pair

    @param asset The address of the asset token
    @param collateral The address of the collateral token
    @param oracle The address of the oracle to use for the pair

    @return pair The address of the deployed pair
    """

    # 30% minimum utilization, 50% maximum utilization
    MINIMUM_TARGET_UTILIZATION: uint256 = 300000000000000000
    MAXIMUM_TARGET_UTILIZATION: uint256 = 500000000000000000

    # 5% minimum interest per second, 12% starting interest per second, 1000% maximum interest per second
    STARTING_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 12) 
    MINIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 5)
    MAXIMUM_INTEREST_PER_SECOND: uint64 = (ONE_PERCENT * 1000)

    INTEREST_ELASTICITY: uint256 = 20000000000000000000000000000000000000000

    pair: address = create_from_blueprint(
        blueprint,
        asset,
        collateral,
        oracle,
        MINIMUM_TARGET_UTILIZATION,
        MAXIMUM_TARGET_UTILIZATION,
        STARTING_INTEREST_PER_SECOND,
        MINIMUM_INTEREST_PER_SECOND,
        MAXIMUM_INTEREST_PER_SECOND,
        INTEREST_ELASTICITY,
        code_offset=3,
    )
    log HighPairCreated(asset, collateral, pair)
    return pair


@external
def deploy_custom_risk_pair(
    asset: address,
    collateral: address,
    oracle: address,
    _blueprint: address,
    code_offset: uint256,
    minimum_target_utilization: uint256,
    maximum_target_utilization: uint256,
    starting_interest_per_second: uint64,
    minimum_interest_per_second: uint64,
    maximum_interest_per_second: uint64,
    elasticity: uint256,
) -> address:
    """
    @dev Deploy a custom pair with a different set of parameters

    @param asset The address of the asset token
    @param collateral The address of the collateral token
    @param oracle The address of the oracle to use for the pair
    @param _blueprint The address of the blueprint to use for the pair
    @param code_offset The offset of the code to use for the given blueprint
    @param minimum_target_utilization The minimum target utilization for the pair
    @param maximum_target_utilization The maximum target utilization for the pair
    @param starting_interest_per_second The starting interest per second for the pair
    @param minimum_interest_per_second The minimum interest per second for the pair
    @param maximum_interest_per_second The maximum interest per second for the pair
    @param elasticity The interest rate elasticity factor

    @return pair The address of the deployed pair
    """
    pair: address = create_from_blueprint(
        _blueprint,
        asset,
        collateral,
        oracle,
        minimum_target_utilization,
        maximum_target_utilization,
        starting_interest_per_second,
        minimum_interest_per_second,
        maximum_interest_per_second,
        elasticity,
        code_offset=code_offset,
    )
    log CustomPairCreated(_blueprint, pair, asset, collateral)
    return pair

import {
  OwnershipTransferred as OwnershipTransferredEvent,
  TokenBought as TokenBoughtEvent,
  TokenCreated as TokenCreatedEvent,
  TokenSold as TokenSoldEvent,
  poolcreated as poolcreatedEvent,
  tokenDeployed as tokenDeployedEvent,
  tokenGraduated as tokenGraduatedEvent
} from "../generated/SlugDex/SlugDex"
import {
  OwnershipTransferred,
  TokenBought,
  TokenCreated,
  TokenSold,
  poolcreated,
  tokenDeployed,
  tokenGraduated
} from "../generated/schema"

export function handleOwnershipTransferred(
  event: OwnershipTransferredEvent
): void {
  let entity = new OwnershipTransferred(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.previousOwner = event.params.previousOwner
  entity.newOwner = event.params.newOwner

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTokenBought(event: TokenBoughtEvent): void {
  let entity = new TokenBought(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.token = event.params.token
  entity.VETH = event.params.VETH
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTokenCreated(event: TokenCreatedEvent): void {
  let entity = new TokenCreated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.token = event.params.token
  entity.internal_id = event.params.id

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTokenSold(event: TokenSoldEvent): void {
  let entity = new TokenSold(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.token = event.params.token
  entity.VETH = event.params.VETH
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handlepoolcreated(event: poolcreatedEvent): void {
  let entity = new poolcreated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.tokenA = event.params.tokenA

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handletokenDeployed(event: tokenDeployedEvent): void {
  let entity = new tokenDeployed(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.token = event.params.token

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handletokenGraduated(event: tokenGraduatedEvent): void {
  let entity = new tokenGraduated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.token = event.params.token

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

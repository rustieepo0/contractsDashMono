local bint = require('.bint')(256)
local ao = require('ao')
local utils = require(".utils")
local json = require("json")

--@type {[string]: string}
Balances = Balances or { [ao.id] = tostring(bint(1e18)) }

--@type string
Name = Name or "Bundler"

--@type string
Ticker = Ticker or "BUN"

--@type integer
Denomination = Denomination or 18

--@type string
Logo = 'SBCCXwwecBlDqRLUjb8dYABExTJXLieawf7m2aBJ-KY'

--@type {[string]:{checksum:string, status: integer, quantity: string, index: integer, block: integer}}
Uploads = Uploads or {}

--@type {id: string, url: string, reputation: integer, balance: string, staked: string}[]
Stakers = Stakers or {}

--@type string[]
Slashed = Slashed or {}

---@param sender string
---@param recipient string
---@param quantity Bint
---@param cast unknown
function Transfer(sender, recipient, quantity, cast)
  Balances[sender] = Balances[sender] or tostring(0)
  Balances[recipient] = Balances[recipient] or tostring(0)

  local balance = bint(Balances[sender])
  if bint.__le(quantity, balance) then
    Balances[sender] = tostring(bint.__sub(balance, quantity))
    Balances[recipient] = tostring(bint.__add(Balances[recipient], quantity))

    if not cast then
      -- Send debit notice to sender
      ao.send({
        Target = sender,
        Action = 'Debit-Notice',
        Recipient = recipient,
        Quantity = tostring(quantity),
        Data = Colors.gray ..
            "You transferred " ..
            Colors.blue .. tostring(quantity) .. Colors.gray .. " to " .. Colors.green .. recipient .. Colors.reset
      })
      -- Send credit notice to recipient
      ao.send({
        Target = recipient,
        Action = 'Credit-Notice',
        Sender = sender,
        Quantity = tostring(quantity),
        Data = Colors.gray ..
            "You received " ..
            Colors.blue .. tostring(quantity) .. Colors.gray .. " from " .. Colors.green .. sender .. Colors.reset
      })
    end
  else
    -- Send error message for insufficient balance
    ao.send({
      Target = sender,
      Action = 'Transfer-Error',
      Error = 'Insufficient Balance!'
    })
  end
end

---Verify an upload
---@param id string
function Verify(id)
  assert(id and #id > 0, "Invalid data item id")
  assert(Uploads[id].status == 3, "Upload incomplete")
  -- TODO: Actually check Arweave upload
  return true
end

---Update Reputation of Staker
---@param index integer
---@param amount integer
function UpdateReputation(index, amount)
  Stakers[index].reputation = Stakers[index].reputation + amount
end

--- Slash function: penalizes a staker by slashing their balance
---@param stakerIndex number: The index of the staker in the Stakers table
function Slash(stakerIndex)
  -- Retrieve the staker from the Stakers table
  local staker = Stakers[stakerIndex]

  -- Check if the staker exists
  assert(staker, "Staker does not exist")

  -- Slashing logic here
  -- Example: Deduct a percentage of the staker's balance
  local slashAmount = bint.divide(Stakers[stakerIndex].balance, 10)  -- Slash 10% of the balance
  Balances[staker.id] = tostring(bint.__sub(Stakers[stakerIndex].balance, slashAmount))

  -- Add the staker to the slashed list
  table.insert(Slashed, staker.id)
end

-- Handlers for network interactions

Handlers.add(
  'initiate', Handlers.utils.hasMatchingTag('Action', 'Initiate'),
   function(message, _)
    ---@type string
   local id = message.Transaction
   assert(id and #id > 0, "Invalid data item id")

   ---@type string
   local checksum = message.Checksum
   assert(checksum and #checksum > 0, "Invalid checksum")

   ---@type Bint
   local quantity = bint(message.Quantity)
   assert(quantity and quantity > 0, "Invalid quantity")

   Transfer(message.From, ao.id, quantity, false)

   Uploads[id] = {
     checksum = checksum,
     status = 0,
     quantity = tostring(quantity),
     bundler = math.random(#Stakers),
     block = message['Block-Height']
   }
 end)

--- Vault

Handlers.add(
  'stake',
   Handlers.utils.hasMatchingTag('Action', 'Stake'),
   function(message, _)
    local exist = utils.includes(message.From, Stakers)
    assert(not exist, "Already staked")
    
    assert(bint(Balances[message.From]) >= bint("1000"), "Insufficient Balance")
    
    local url = message.URL;
    assert(url and #url > 0, "Invalid URL")
    
    -- Update staked amount in Stakers table
    Stakers[#Stakers + 1] = { 
      id = message.From, 
      url = url, 
      reputation = 1000, 
      balance = bint(Balances[message.From]), 
      staked = bint("1000") 
    }
  end
)

-- Staking Reward Logic
function CalculateStakingRewards(staker)
  -- Replace with your reward calculation logic based on staking duration, etc.
  -- This is a placeholder example
  local reward = staker.staked * 0.01  -- 1% reward per unit of staked tokens
  return reward
end

Handlers.add(
  'unstake',
   Handlers.utils.hasMatchingTag('Action', 'Unstake'),
   function(message, _)
   local pos = -1
   for i = 1, #Stakers do
    if Stakers[i].id == message.From then
      pos = i
    end
  end
  assert(pos ~= -1, "Not Staked")
  
  -- Return the original staked amount
  Transfer(ao.id, message.From, Stakers[pos].staked, false)
  table.remove(Stakers, pos)
end
)

Handlers.add(
  'transfer', 
  Handlers.utils.hasMatchingTag('Action', 'Transfer'), 
  function(message, _)
  assert(type(message.Recipient) == 'string', 'Recipient is required!')
  
  assert(type(message.Quantity) == 'string', 'Quantity is required!')
  
  local quantity = bint(message.Quantity)
  
  assert(quantity > bint(0), 'Quantity is required!')
  Transfer(message.From, message.Recipient, quantity, message.Cast)
end
)

Handlers.add('balances', 
Handlers.utils.hasMatchingTag('Action', 'Balances'), 
function(message, _)
  ao.send({ Target = message.From, Data = json.encode(Balances) })
end
)

Handlers.add('stakers', 
Handlers.utils.hasMatchingTag('Action', 'Stakers'), 
function(message, _)
  ao.send({ Target = message.From, Data = json.encode(Stakers) })
end
)

Handlers.add(
  'notify', 
  Handlers.utils.hasMatchingTag('Action', 'Notify'), 
  function(message, _)
  assert(type(message.Transaction) == 'string', "DataItem id is required!")
  
  assert(type(message.Status) == 'string', "Status is required!")
  
  local id = message.Transaction
  local bundler = Stakers[Uploads[id].index]
  
  assert(bundler == message.From, "Not owner")
  assert(Uploads[id].status ~= 3, "Upload already complete")
  
  local status = tonumber(message.Status)
  assert(utils.includes(status, { -1, 2, 3 }), "Invalid status")
  
  Uploads[id].status = status
end
)

Handlers.add(
  'release', Handlers.utils.hasMatchingTag('Action', 'Release'), 
  function(message, _)
  local id = message.Transaction
  assert(id and #id > 0, "Invalid data item id")
  
  local bundler = Stakers[Uploads[id].index]
  
  assert(bundler == message.From, "Not owner")
  assert(Uploads[id].status == 3, "Upload incomplete")
  
  Verify(id)
  
  UpdateReputation(Uploads[id].index, 100)
  local quantity = bint(Uploads[id].quantity)
  
  Transfer(ao.id, message.From, quantity, nil)
end
)

Handlers.add(
  'slash', Handlers.utils.hasMatchingTag('Action', 'Slash'), 
  function(message, _)
  assert(type(message.StakerIndex) == 'number', 'Staker index is required!')
  Slash(message.StakerIndex)
end
)

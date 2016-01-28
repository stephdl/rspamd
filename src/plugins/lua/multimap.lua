--[[
Copyright (c) 2011-2015, Vsevolod Stakhov <vsevolod@highsecure.ru>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]--

-- Multimap is rspamd module designed to define and operate with different maps

local rules = {}
local rspamd_logger = require "rspamd_logger"
local cdb = require "rspamd_cdb"
local util = require "rspamd_util"
local regexp = require "rspamd_regexp"
local _ = require "fun"
--local dumper = require 'pl.pretty'.dump

local function ip_to_rbl(ip, rbl)
  return table.concat(ip:inversed_str_octets(), ".") .. '.' .. rbl
end

local function check_multimap(task)
  -- Applies specific filter for input
  local function apply_filter(filter, input, rule)
    if filter == 'email:addr' or filter == 'email' then
      local addr = util.parse_mail_address(input)
      if addr and addr[1] then
        return addr[1]['addr']
      end
    elseif filter == 'email:user' then
      local addr = util.parse_mail_address(input)
      if addr and addr[1] then
        return addr[1]['user']
      end
    elseif filter == 'email:domain' then
      local addr = util.parse_mail_address(input)
      if addr and addr[1] then
        return addr[1]['domain']
      end
    elseif filter == 'email:name' then
      local addr = util.parse_mail_address(input)
      if addr and addr[1] then
        return addr[1]['name']
      end
    else
      -- regexp case
      if not rule['regexp'] then
        local type,pat = string.match(filter, '(regexp:)(.+)')
        if type and pat then
          rule['regexp'] = regexp.create(pat)
        end
      end

      if not rule['regexp'] then
        rspamd_logger.errx(task, 'bad search filter: %s', filter)
      else
        local results = rule['regexp']:search(input)
        if results then
          return results[1]
        end
      end
    end

    return input
  end


  -- Match a single value for against a single rule
  local function match_rule(r, value)
    local ret = false

    if r['filter'] then
      value = apply_filter(r['filter'], value, r)
    end

    if not value then
      return false
    end

    if r['cdb'] then
      local srch = value
      if r['type'] == 'ip' then
        srch = value:to_string()
      end

      ret = r['cdb']:lookup(srch)
    elseif r['radix'] then
      ret = r['radix']:get_key(value)
    elseif r['hash'] then
      ret = r['hash']:get_key(value)
    end

    if ret then
      task:insert_result(r['symbol'], 1)
    end

    return ret
  end

  -- Match list of values according to the field
  local function match_list(r, ls, fields)
    local ret = false
    if ls then
      if fields then
        _.each(function(e)
          local match = e[fields[1]]
          if match then
            if fields[2] then
              match = fields[2](match)
            end
            ret = match_rule(r, match)
          end
        end, ls)
      else
        _.each(function(e) ret = match_rule(r, e) end, ls)
      end
    end

    return ret
  end

  local function match_addr(r, addr)
    local ret = match_list(r, addr, {'addr'})

    if not ret then
      -- Try domain
      ret = match_list(r, addr, {'domain', function(d) return '@' .. d end})
    end
    if not ret then
      -- Try user
      ret =  match_list(r, addr, {'user', function(d) return d .. '@' end})
    end

    return ret
  end

  -- IP rules
  local ip = task:get_from_ip()
  if ip:is_valid() then
    _.each(function(r) match_rule(r, ip) end,
      _.filter(function(r) return r['type'] == 'ip' end, rules))
  end

  -- Header rules
  _.each(function(r)
    local hv = task:get_header_full(r['header'])
    match_list(r, hv, {'decoded'})
  end,
  _.filter(function(r) return r['type'] == 'header' end, rules))

  -- Rcpt rules
  if task:has_recipients() then
    local rcpts = task:get_recipients()
    _.each(function(r)
      match_addr(r, rcpts)
    end,
    _.filter(function(r) return r['type'] == 'rcpt' end, rules))
  end

  -- From rules
  if task:has_from() then
    local from = task:get_from()
    if from then
      _.each(function(r)
        match_addr(r, from)
      end,
      _.filter(function(r) return r['type'] == 'from' end, rules))
    end
  end

  -- RBL rules
  if ip:is_valid() then
    _.each(function(r)
        local cb = function (resolver, to_resolve, results, err, rbl)
          if results then
            task:insert_result(r['symbol'], 1, r['map'])
          end
        end

        task:get_resolver():resolve_a({task = task,
          name = ip_to_rbl(ip, r['map']),
          callback = cb,
          })
      end,
    _.filter(function(r) return r['type'] == 'dnsbl' end, rules))
  end
end

local function add_multimap_rule(key, newrule)
  if not newrule['map'] then
    rspamd_logger.errx(rspamd_config, 'incomplete rule, missing map')
    return nil
  end
  if not newrule['symbol'] and key then
    newrule['symbol'] = key
  elseif not newrule['symbol'] then
    rspamd_logger.errx(rspamd_config, 'incomplete rule, missing symbol')
    return nil
  end
  -- Check cdb flag
  if string.find(newrule['map'], '^cdb://.*$') then
    local test = cdb.create(newrule['map'])
    newrule['cdb'] = cdb.create(newrule['map'])
    if newrule['cdb'] then
      return newrule
    else
      rspamd_logger.warnx(rspamd_config, 'Cannot add rule: map doesn\'t exists: %1',
          newrule['map'])
    end
  else
    if newrule['type'] == 'ip' then
      newrule['radix'] = rspamd_config:add_radix_map (newrule['map'],
        newrule['description'])
      if newrule['radix'] then
        return newrule
      else
        rspamd_logger.warnx(rspamd_config, 'Cannot add rule: map doesn\'t exists: %1',
            newrule['map'])
      end
    elseif newrule['type'] == 'header' or newrule['type'] == 'rcpt' or newrule['type'] == 'from' then
      newrule['hash'] = rspamd_config:add_hash_map (newrule['map'], newrule['description'])
      if newrule['hash'] then
        return newrule
      else
        rspamd_logger.warnx(rspamd_config, 'Cannot add rule: map doesn\'t exists: %1',
          newrule['map'])
      end
    elseif newrule['type'] == 'dnsbl' then
      return newrule
    end
  end
  return nil
end

-- Registration
local opts =  rspamd_config:get_all_opt('multimap')
if opts and type(opts) == 'table' then
  for k,m in pairs(opts) do
    if type(m) == 'table' then
      local rule = add_multimap_rule(k, m)
      if not rule then
        rspamd_logger.errx(rspamd_config, 'cannot add rule: "'..k..'"')
      else
        table.insert(rules, rule)
      end
    else
      rspamd_logger.errx(rspamd_config, 'parameter ' .. k .. ' is invalid, must be an object')
    end
  end
  -- add fake symbol to check all maps inside a single callback
  if type(rspamd_config.get_api_version) ~= 'nil' then
    local id = rspamd_config:register_callback_symbol_priority(1.0, -1,
      check_multimap)
    for i,rule in ipairs(rules) do
      rspamd_config:register_virtual_symbol(rule['symbol'], 1.0, id)
    end
  end
end

local redis = require "resty.redis"
local red = redis:new()
red:set_timeout(1000)

local redis_host = ngx.var.redis_host
if not redis_host then
    redis_host = "redis"
end

local redis_port = ngx.var.redis_port
if not redis_port then
    redis_port = 6379
end

-- Make sure we can connect to Redis
local ok, err = red:connect(redis_host, redis_port)
if not ok then
    ngx.log(ngx.STDERR, "Failed to connect to Redis: " .. err)
    return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

-- Extract only the hostname without the port
local frontend = ngx.re.match(ngx.var.http_host, "^([^:]*)")[1]
local pool, err = red:get('frontend:' .. frontend)

if not pool then
    ngx.log(ngx.STDERR, "Failed to lookup pool: " .. err)
end

if pool == ngx.null then
    -- Extract the domain name without the subdomain
    -- special nginx lua escaping https://github.com/openresty/lua-nginx-module#special-escaping-sequences
    local pattern = [=[(\\.[^.]+\\.[^.]+)$]=]
    local m, err = ngx.re.match(frontend, pattern)

    if m then
        pool, err = red:get('frontend:*' .. m[1])
        if not pool then
            ngx.log(ngx.STDERR, "Failed to lookup pool: " .. err)
            return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
        end

        if pool == ngx.null then
            ngx.log(ngx.STDERR, "No pools for frontend: " .. frontend)
            return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
        end
    else
        ngx.log(ngx.STDERR, "No pools for frontend: " .. frontend)
        return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
    end
end

-- Lookup backends
red:multi()
red:lrange("backend:" .. pool, 0, -1)
red:smembers("dead:" .. frontend)
local ans, err = red:exec()
if not ans then
    ngx.log(ngx.STDERR, "Backend lookup failed: " .. err)
    return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end

local backends = ans[1]
if #backends == 0 then
    ngx.log(ngx.STDERR, "Backend not found for pool: " .. pool)
    return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
end
local deads = ans[2]

-- Select a random backend (after removing the dead ones)
local indexes = {}
for i, v in ipairs(deads) do
   deads[v] = true
end
for i, v in ipairs(backends) do
    if deads[tostring(i)] == nil then
        table.insert(indexes, i)
    end
end
local index = indexes[math.random(1, #indexes)]
local backend = backends[index]

-- Announce dead backends if there is any
local deads = ngx.shared.deads
for i, v in ipairs(deads:get_keys()) do
    red:publish("dead", deads:get(v))
    deads:delete(v)
end

-- Set the connection pool (to avoid connect/close everytime)
red:set_keepalive(0, 100)

-- Export variables
ngx.var.backend = backend
ngx.var.backends_len = #backends
ngx.var.backend_id = index - 1
ngx.var.frontend = frontend
ngx.var.pool = pool

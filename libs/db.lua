local sgsub = string.gsub
local tinsert = table.insert
local type = type
local ipairs = ipairs
local pairs = pairs
local mysql = require("resty.mysql")
local cjson = require("cjson")
local DB = {}
local mysql_config = {
    timeout = 5000,
    connect_config = {
        host = "127.0.0.1",
        port = 3306,
        database = "demo",
        user = "root",
        password = "",
        max_packet_size = 1024 * 1024
    },
    pool_config = {
        max_idle_timeout = 20000, -- 20s
        pool_size = 50 -- connection pool size
    }
}

function DB:new(conf)
    conf = conf or mysql_config
    local instance = {}
    instance.conf = conf
    setmetatable(instance, { __index = self})
    return instance
end

function DB:exec(sql)
    if not sql then
        ngx.log(ngx.ERR, "sql parse error! please check")
        return nil, "sql parse error! please check"
    end

    local conf = self.conf
    local db, err = mysql:new()
    if not db then
        ngx.status = 500
        ngx.say("failed to instantiate mysql: ", err)
        ngx.exit(500)
    end
    db:set_timeout(conf.timeout) -- 1 sec

    local ok, err, errno, sqlstate = db:connect(conf.connect_config)
    if not ok then
        ngx.status = 500
        ngx.say("failed to connect: ", err, ": ", errno, " ", sqlstate)
        ngx.exit(500)
    end

    ngx.log(ngx.ERR, "connected to mysql, reused_times:", db:get_reused_times(), " sql:", sql)

    db:query("SET NAMES utf8")
    local res, err, errno, sqlstate = db:query(sql)
    if not res then
        ngx.log(ngx.ERR, "bad result: ", err, ": ", errno, ": ", sqlstate, ".")
    end

    local ok, err = db:set_keepalive(conf.pool_config.max_idle_timeout, conf.pool_config.pool_size)
    if not ok then
        ngx.say("failed to set keepalive: ", err)
    end

    return res, err, errno, sqlstate
end



function DB:query(sql, params)
    sql = self:parse_sql(sql, params)
    return self:exec(sql)
end

function DB:select(sql, params)
    return self:query(sql, params)
end

function DB:insert(sql, params)
    local res, err, errno, sqlstate = self:query(sql, params)
    if res and not err then
        return  res.insert_id, err
    else
        return res, err
    end
end

function DB:update(sql, params)
    return self:query(sql, params)
end

function DB:delete(sql, params)
    local res, err, errno, sqlstate = self:query(sql, params)
    if res and not err then
        return res.affected_rows, err
    else
        return res, err
    end
end

local function split(str, delimiter)
    if str==nil or str=='' or delimiter==nil then
        return nil
    end
    
    local result = {}
    for match in (str..delimiter):gmatch("(.-)"..delimiter) do
        tinsert(result, match)
    end
    return result
end


local function compose(t, params)
    if t==nil or params==nil or type(t)~="table" or type(params)~="table" or #t~=#params+1 or #t==0 then
        return nil
    else
        local result = t[1]
        for i=1, #params do
            result = result  .. params[i].. t[i+1]
        end
        return result
    end
end
    
local function table_is_array(t)
    if type(t) ~= "table" then return false end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end


function DB:parse_sql(sql, params)
    if not params or not table_is_array(params) or #params == 0 then
        return sql
    end

    local new_params = {}
    for i, v in ipairs(params) do
        if v and type(v) == "string" then
            v = ngx.quote_sql_str(v)
        end
        
        tinsert(new_params, v)
    end

    local t = split(sql,"?")
    local sql = compose(t, new_params)

    return sql
end 

return DB
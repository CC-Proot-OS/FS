local FileSystem = fs:exec("/lib/toastfs.lua",0)()
local DFS = {}
function DFS:new()
    -- Create a special DevFileSystem that inherits from FileSystem
    DevFileSystem = FileSystem:new()
    DevFileSystem._list = DevFileSystem.list
    DevFileSystem.root = {
        isDir = true,
    }
    -- Function to add a device node to /dev
    function DevFileSystem:addDevice(name, handler,perms)
        self.root[name] = {
            name = name,
            isDir = false,
            isDevice = true,
            handler = handler,
            perms = perms or 0
        }
    end
    function DevFileSystem:_isDir(path,uid)
        if path == "/" or path == "" then
            return true
        end
        return false
    end

    -- Override open to handle device nodes
    function DevFileSystem:open(path, mode, userId)
        local targetItem = self:navigate(path)

        if targetItem and targetItem.isDevice then
            return {
                read = function() return targetItem.handler("read") end,
                readAll = function() return targetItem.handler("read") end,
                readLine = function() return targetItem.handler("read") end,
                seek = function() return targetItem.handler("seek") end,
                write = function(data) targetItem.handler("write", data) end,
                close = function() end  -- No-op for devices
            }
        else
            return FileSystem.open(self, path, mode, userId)  -- Call the base class method
        end
    end
    DevFileSystem._open = DevFileSystem.open
    -- Function to check permissions
    function DevFileSystem:checkPermissions(item, userId, accessType)
        --local userPerms = item.permissions[userId] or 0  -- Default to 0 if no permissions assigned
        local requiredPerms = 0
        if userId == 0 then
            return true
        end
        
        if accessType == "r" then
            requiredPerms = 4  -- Read permission
        elseif accessType == "w" then
            requiredPerms = 2  -- Write permission
        elseif accessType == "x" then
            requiredPerms = 1  -- Execute permission
        end

        return bit.band(item.perms, requiredPerms) > 0
    end
    function DevFileSystem:Permissions(path, userId)
        local item = self:navigate(path)
        if userId == 0 then
            return 7
        end

        
        return item.perms
    end
    DevFileSystem._getPermissions = DevFileSystem.Permissions
    return DevFileSystem
end
return DFS
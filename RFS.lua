local ofs = fs
RealFS = {}
RealFS.__index = RealFS

-- Constructor
function RealFS:new(storePath)
    storePath = storePath or "/proot/fs"
    if storePath:sub(-1) == "/" then
        storePath = storePath:sub(1, -2)
    end

    local metaFilePath = storePath .. "/etc/fsmeta.lstn"  -- Store metadata in <storePath>/etc/fsmeta.lstn

    local fs = {
        storePath = storePath,    -- Root of the filesystem
        metaFilePath = metaFilePath, -- Metadata file
        permissions = {},  -- Cache for permissions
        root = { isDir = true, contents = {} }, -- Root directory
        mounts = {}  -- Table to store mounted filesystems
    }
    fs.combine = ofs.combine
    fs.getName = ofs.getName
    setmetatable(fs, self)

    fs:loadPermissions()
    fs.permissions["/"] = {
        perms = 7,  -- Full permissions (rwx) for root
        ownerId = 0,  -- Root is the owner
        groupId = 0,
        groupPerms =0,
        allPerms = 4,
        created = os.time(),
        modified = os.time(),
        isDir = true
    }

    return fs
end

-- Mount another filesystem to a path
function RealFS:mount(path, fs,user)
    if not self.permissions[path] then
        error "Mount point does not exist or is not a directory"
    end
    self.mounts[path] = fs
    return true
end

-- Find the filesystem for a given path, and return the relative path for that filesystem
function RealFS:findFS(path)
    for mountPath, fs in pairs(self.mounts) do
        if path:sub(1, #mountPath) == mountPath then
            
            local relativePath = path:sub(#mountPath + 1)
            if relativePath == "" then relativePath = "/" end
            return fs, relativePath
        end
    end
    return self, path
end
local function mysplit(inputstr, sep)
    if sep == nil then
      sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
      table.insert(t, str)
    end
    return t
  end
-- Load permissions from the metadata file
function RealFS:loadPermissions()
    local file = ofs.open(self.metaFilePath, "r")

    if file then
        local lines = mysplit(file.readAll(),"\n")
        for _,line in ipairs(lines) do
            local path, ownr_perms, ownerId, group, groupId,all, created, modified = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
            self.permissions[path] = {
                perms = tonumber(ownr_perms),
                groupPerms = tonumber(group),
                allPerms = tonumber(all),
                ownerId = tonumber(ownerId),
                groupId = tonumber(groupId),
                created = tonumber(created),
                modified = tonumber(modified)
            }
        end
        file:close()
    else
        print("Metadata file not found at " .. self.metaFilePath .. ", starting fresh.")
    end
end


-- Save permissions to the metadata file
function RealFS:savePermissions()
    local file,e = ofs.open(self.metaFilePath, "w")
    for path, meta in pairs(self.permissions) do
        file.write(string.format("%s|%d|%d|%d|%d|%d|%d|%d\n", path, meta.perms, meta.ownerId, meta.groupPerms,meta.groupId,meta.allPerms, meta.created, meta.modified))
    end
    file.close()
end

function RealFS:loadFromDisk(p)
    self:loadPermissions()
end
function RealFS:saveToDisk(p)
    self:savePermissions()
end

-- Open a file and return a stream
function RealFS:open(path, mode, userId)
    local fs, relativePath = self:findFS(path)
    return fs:_open(relativePath, mode, userId)
end

-- Internal open function (used by the found filesystem)
function RealFS:_open(path, mode, userId)
    if path:sub(1,1) ~= "/" then
        path = "/"..path
    end
    local absolutePath = self.combine(self.storePath, path)
    
    local meta = self.permissions[path]

    -- Check if file exists and handle according to mode
    if mode == "r" then
        -- Check if user has read permissions
        if not self:checkPermissions(path, userId, "r") then
            local p,e =self:Permissions(path,userId)
            return nil, "Permission denied for reading "..p.." "..e
        end
    elseif mode == "w" or mode == "w+" then
        if meta then
            -- Check if user has write permissions
            if not self:checkPermissions(path, userId, "w") then
                return nil, "Permission denied for writing"
            end
        else
            -- If file does not exist, check for write permissions in the parent directory
            local parentPath = self:getParentPath(path)
            local parentMeta = self.permissions[parentPath]
            
            if not parentMeta or not self:checkPermissions(parentPath, userId, "w") then
                return nil, "Permission denied for creating file in parent directory"
            end
            -- Create the file
            
            -- Set initial permissions for the new file (you may need to adjust this logic)
            self.permissions[path] = {
                perms = 6,  -- Assuming user has read+write permissions for the newly created file
                ownerId = userId,
                groupPerms =0,
                allPerms = 0,
                groupId = 0,
                created = os.time(),
                modified = os.time(),
                isDir = false
            }
            self:savePermissions()
        end
    elseif mode == "a" then
        -- Append mode (allow writing even if file doesn't exist)
        if meta and not self:checkPermissions(path, userId, "w") then
            return nil, "Permission denied for appending"
        end
    elseif mode == "r+" then
        -- Read-write mode, check for both read and write permissions
        if not meta then
            error "File not found"
        end
        if not self:checkPermissions(path, userId, "r") or not self:checkPermissions(path, userId, "w") then
            return nil, "Permission denied for read-write"
        end
    elseif mode == "w+" then
        -- Same as "w", handle both write and read
        if meta and not self:checkPermissions(path, userId, "w") then
            return nil, "Permission denied for writing"
        end
        if not meta then
            local parentPath = self:getParentPath(path)
            local parentMeta = self.permissions[parentPath]
            
            if not parentMeta or not self:checkPermissions(parentPath, userId, "w") then
                return nil, "Permission denied for creating file in parent directory"
            end
            -- Set initial permissions for the new file
            self.permissions[path] = {
                perms = 6,
                ownerId = userId,
                groupPerms =0,
                allPerms = 0,
                groupId = 0,
                created = os.time(),
                modified = os.time(),
                isDir = false
            }
            self:savePermissions()
        end
    end

    -- Open the file with the chosen mode
    local file, err = ofs.open(absolutePath, mode)
    if not file then
        return nil, err
    end

    return file
end


-- List files in a directory
function RealFS:list(path, userId)
    local fs, relativePath = self:findFS(path)
    return fs:_list(relativePath, userId)
end

-- Internal list function (used by the found filesystem)
function RealFS:_list(path, userId)
    local absolutePath = self.combine(self.storePath, path)
    if not self:checkPermissions(path, userId, "r") then
        local p,e = self:Permissions(path,userId)
        error(path.." Permission denied or directory not found "..p.." "..e)
    end

    return ofs.list(absolutePath)
end

-- Check if user has required permissions for a given file
function RealFS:checkPermissions(path, userId, accessType)
    path = path:gsub("%/$", "")
    
    if #path == 0 then
        path = "/"
    end
    if path:sub(1,1) ~= "/" then
        path = "/"..path
    end

    local perms = self:Permissions(path, userId)
    if accessType == "r" then
        return bit.band(perms, 4) ~= 0
    elseif accessType == "w" then
        return bit.band(perms, 2) ~= 0
    elseif accessType == "x" then
        return bit.band(perms, 1) ~= 0
    end
    return false
end

-- Get a user's permissions for a path
function RealFS:Permissions(path, userId)
    local meta = self.permissions[path]
    if not meta then return 0,"NOTFOUND"..path end
    if userId == 0 then
        return 7
    end
    if userId == meta.ownerId then
        return meta.perms
    end
    return meta.allPerms,"GENERIC"
end

-- Make a directory
function RealFS:makeDir(path, userId)
    local fs, relativePath = self:findFS(path)
    return fs:_makeDir(relativePath, userId)
end

-- Internal make directory function
function RealFS:_makeDir(path, userId)
    local absolutePath = self.combine(self.storePath, path)
    local parentPath = self:getParentPath(path)
    local parentMeta = self.permissions[parentPath]
    if not parentMeta or not self:checkPermissions(parentPath, userId, "w") then
        return false, "Permission denied"
    end

    ofs.makeDir(absolutePath)
    self.permissions[path] = {
        perms = 7,  -- Full permissions for owner
        ownerId = userId,
        groupPerms =0,
        allPerms = 0,
        groupId = 0,
        created = os.time(),
        modified = os.time(),
        isDir = true
    }
    self:savePermissions()
    return true
end

-- Get the parent path of a given path
function RealFS:getParentPath(path)
    local parentPath = path:match("(.*/)"):gsub("%/$", "")
    if #parentPath == 0 then
        parentPath = "/"
    end
    return parentPath or "/"
end

-- Delete a file or directory
function RealFS:delete(path, userId)
    local fs, relativePath = self:findFS(path)
    return fs:_delete(relativePath, userId)
end

-- Internal delete function
function RealFS:_delete(path, userId)
    local absolutePath = self.combine(self.storePath, path)
    local parentPath = self:getParentPath(path)
    local parentMeta = self.permissions[parentPath]
    if not parentMeta or not self:checkPermissions(parentPath, userId, "w") then
        return false, "Permission denied"
    end

    ofs.delete(absolutePath)
    self.permissions[path] = nil
    self:savePermissions()
    return true
end

-- Function to change the permissions of a file or directory
function RealFS:chmod(path, userId, newPermissions,scope)
    -- Find the filesystem and the relative path
    local fs, relativePath = self:findFS(path)
    return fs:_chmod(relativePath, userId, newPermissions,scope)
end

-- Internal chmod function (used by the found filesystem)
function RealFS:_chmod(path, userId, newPermissions,scope)
    local meta = self.permissions[path]
    
    if not meta then
        return nil, "File or directory not found"
    end
    
    -- Check if user has write permissions to modify the permissions of this item
    if not self:checkPermissions(path, userId, "w") then
        return nil, "Permission denied for changing permissions"
    end
    
    -- Update permissions for the file/directory
    if bit.band(scope, 1) ~=0 then
        meta.perms = newPermissions
    end
    if bit.band(scope, 2) ~=0 then
        meta.groupPerms = newPermissions
    end
    if bit.band(scope, 4) ~=0 then
        meta.allPerms = newPermissions
    end
    
    meta.modified = os.time()  -- Update the modification time
    self:savePermissions()
    
    return true  -- Return true on success
end
-- Function to execute a file using fs.open
function RealFS:exec(path, userId)
    -- Find the filesystem and relative path
    local fs, relativePath = self:findFS(path)
    return fs:_exec(relativePath, userId)
end

-- Internal exec function (used by the found filesystem)
function RealFS:_exec(path, userId)
    -- Check if the file exists and if it's executable
    local meta = self.permissions[path]
    
    -- Check if the user has execute permissions
    if not self:checkPermissions(path, userId, "x") then
        return nil, "Permission denied for execution"
    end

    -- Open the file in read mode
    local file, err = self:open(path, "r", userId)
    if not file then
        return nil, "Failed to open file: " .. err
    end
    
    -- Read the content of the file
    local fileContent = file.readAll()
    file.close()

    -- Ensure file content is a valid Lua function or script
    local func, loadError = load(fileContent, path)
    if not func then
        return nil, "Failed to load file as Lua code: " .. loadError
    end

    -- Return the function that can be executed
    return func
end

-- Function to check if the path is a directory
function RealFS:isDir(path, userId)
    -- Find the filesystem and relative path
    local fs, relativePath = self:findFS(path)
    return fs:_isDir(relativePath, userId)
end

-- Internal isDir function (used by the found filesystem)
function RealFS:_isDir(path, userId)
    -- Check if the item exists in permissions
    local meta = self.permissions[path]
    local absolutePath = self.combine(self.storePath, path)
    return ofs.isDir(absolutePath)
    --[[
    -- Check if it's marked as a directory (assuming 'isDir' is part of metadata)
    if meta.isDir then
        return true
    else
        return false
    end]]
end
function RealFS:exists(path, userId)
    -- Find the filesystem and relative path
    local fs, relativePath = self:findFS(path)
    return fs:_exists(relativePath, userId)
end

-- Internal isDir function (used by the found filesystem)
function RealFS:_exists(path, userId)
    -- Check if the item exists in permissions

    local absolutePath = self.combine(self.storePath, path)
    return ofs.exists(absolutePath)
    --[[
    -- Check if it's marked as a directory (assuming 'isDir' is part of metadata)
    if meta.isDir then
        return true
    else
        return false
    end]]
end
function RealFS:getDir(path)
    if path == "/" then
        return nil -- Root has no parent
    end

    -- Split the path into segments
    local segments = {}
    for segment in path:gmatch("[^/]+") do
        table.insert(segments, segment)
    end

    -- Remove the last segment to get the parent path
    table.remove(segments) -- Remove the last segment

    -- Reconstruct the parent path
    local parentPath = "/" .. table.concat(segments, "/")
    return parentPath
end



return RealFS
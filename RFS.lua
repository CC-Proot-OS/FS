local ofs = fs
RealFS = {}
RealFS.__index = RealFS

-- Constructor
function RealFS:new(storePath)
    storePath = storePath or "/proot/fs"
    if storePath:sub(-1) == "/" then
        storePath = storePath:sub(1, -2)
    end

    local metaFilePath = storePath .. "/etc/fsmeta.lstn" -- Store metadata in <storePath>/etc/fsmeta.lstn

    local FS = {
        storePath = storePath,                  -- Root of the filesystem
        metaFilePath = metaFilePath,            -- Metadata file
        permissions = {},                       -- Cache for permissions
        root = { isDir = true, contents = {} }, -- Root directory
        mounts = {}                             -- Table to store mounted filesystems
    }
    FS.combine = ofs.combine
    FS.getName = ofs.getName
    --setmetatable(fs, self)

    -- Mount another filesystem to a path
    function FS:mount(path, fs, user)
        if not self.permissions[path] then
            error "Mount point does not exist or is not a directory"
        end
        self.mounts[path] = fs
        return true
    end

    -- Helper function to split a path into components
    function FS:splitPath(path)
        local parts = {}
        for part in string.gmatch(path, "[^/]+") do
            table.insert(parts, part)
        end
        return parts
    end

    -- Function to create a symlink at a path pointing to targetPath
    function FS:symlink(path, targetPath, userId)
        -- Find the parent directory to ensure it's writable
        local parentPath = self:getParentPath(path)
        local parentMeta = self.permissions[parentPath]

        if not parentMeta then
            return nil, "Parent directory not found"
        end

        -- Check if the user has write permissions to create a symlink
        if not self:checkPermissions(parentMeta, userId, "w") then
            return nil, "Permission denied to create symlink"
        end

        -- Add ".sym" extension to store as a symlink file
        local symPath = path .. ".sym"

        -- Write the target path into the .sym file
        local file, err = self:open(symPath, "w", userId)
        if not file then
            return nil, "Failed to create symlink: " .. err
        end
        file:write(targetPath)
        file:close()

        -- Mark this path as a symlink in the permissions metadata
        self.permissions[symPath] = {
            isSymlink = true,
            permissions = {}, -- Symlink may inherit permissions from target
        }

        return true -- Symlink created successfully
    end

    -- Resolve a symlink, if it's a .sym file, and handle loops
    function FS:resolveSymlink(path, visited)
        visited = visited or {}

        -- Detect loops in symlinks
        if visited[path] then
            return nil, "Symlink loop detected"
        end
        visited[path] = true

        -- Check if the path is a symlink (".sym" file)
        local symPath = path .. ".sym"
        local meta = self.permissions[symPath]

        if meta and meta.isSymlink then
            -- Open the .sym file to read the target path
            local file, err = self:open(symPath, "r", 0) -- Root user (0) for reading
            if not file then
                return nil, "Failed to open symlink file: " .. err
            end

            local targetPath = file:readAll()
            file:close()

            -- Return the target path (symlink resolves to this path)
            return targetPath, nil
        end

        -- If it's not a symlink, return the original path
        return path, nil
    end

    function FS:resolveFullPath(path, userId)
        if string.sub(path, 1, 1) == "~" then
            path = "/home/user" .. tostring(userId) .. string.sub(path, 2)
        end
        local parts = self:splitPath(path)
        local resolvedParts = {}
        local visited = {}

        for _, part in ipairs(parts) do
            if part == "" or part == "." then
                -- Ignore empty components or current directory references
            elseif part == ".." then
                -- Go back one directory
                if #resolvedParts > 0 then
                    table.remove(resolvedParts)
                end
            else
                -- Check for symlinks at this level
                local currentPath = "/" .. table.concat(resolvedParts, "/") .. "/" .. part
                local resolvedPath, err = self:resolveSymlink(currentPath, visited)
                if not resolvedPath then
                    return nil, err -- Return error if unable to resolve
                end

                -- If the resolved path is absolute, reset the resolution
                if string.sub(resolvedPath, 1, 1) == "/" then
                    resolvedParts = self:splitPath(resolvedPath)
                else
                    -- Otherwise, continue appending parts to the current resolution
                    table.insert(resolvedParts, resolvedPath)
                end
            end
        end

        return "/" .. table.concat(resolvedParts, "/")
    end

    -- Find the correct filesystem and the relative path for that filesystem
    ---@param path string
    ---@param uid number
    ---@return nil
    ---@return string
    function FS:findFS(path, uid)
        -- First, resolve the full path (handle symlinks)
        local resolvedPath, err = self:resolveFullPath(path, uid)
        if not resolvedPath then
            return nil, "Error resolving path: " .. err
        end

        -- Check if the resolved path is within a mounted filesystem
        for mountPoint, mountedFs in pairs(self.mounts) do
            if string.sub(resolvedPath, 1, #mountPoint) == mountPoint then
                local relativePath = string.sub(resolvedPath, #mountPoint + 1)
                if relativePath == "" then relativePath = "/" end
                return mountedFs, relativePath
            end
        end

        -- If no mounted filesystem is found, return the base filesystem
        return self, resolvedPath
    end

    local function mysplit(inputstr, sep)
        if sep == nil then
            sep = "%s"
        end
        local t = {}
        for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
            table.insert(t, str)
        end
        return t
    end
    -- Load permissions from the metadata file
    function FS:loadPermissions()
        local file = ofs.open(self.metaFilePath, "r")

        if file then
            local lines = mysplit(file.readAll(), "\n")
            for _, line in ipairs(lines) do
                local path, ownr_perms, ownerId, group, groupId, all, created, modified = line:match(
                "([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
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
    function FS:savePermissions()
        local file, e = ofs.open(self.metaFilePath, "w")
        for path, meta in pairs(self.permissions) do
            file.write(string.format("%s|%d|%d|%d|%d|%d|%d|%d\n", path, meta.perms, meta.ownerId, meta.groupPerms,
                meta.groupId, meta.allPerms, meta.created, meta.modified))
        end
        file.close()
    end

    function FS:loadFromDisk(p)
        self:loadPermissions()
    end

    function FS:saveToDisk(p)
        self:savePermissions()
    end

    -- Open a file and return a stream
    function FS:open(path, mode, userId)
        local fs, relativePath = self:findFS(path, userId)
        return fs:_open(relativePath, mode, userId)
    end

    -- Internal open function (used by the found filesystem)
    function FS:_open(path, mode, userId)
        if path:sub(1, 1) ~= "/" then
            path = "/" .. path
        end
        local absolutePath = self.combine(self.storePath, path)

        local meta = self.permissions[path]

        -- Check if file exists and handle according to mode
        if mode == "r" then
            -- Check if user has read permissions
            if not self:checkPermissions(path, userId, "r") then
                local p, e = self:Permissions(path, userId)
                return nil, "Permission denied for reading " .. p .. " - " .. e
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
                    perms = 6, -- Assuming user has read+write permissions for the newly created file
                    ownerId = userId,
                    groupPerms = 0,
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
                    groupPerms = 0,
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
    function FS:list(path, userId)
        local fs, relativePath = self:findFS(path, userId)
        return fs:_list(relativePath, userId)
    end

    -- Internal list function (used by the found filesystem)
    function FS:_list(path, userId)
        local absolutePath = self.combine(self.storePath, path)
        if not self:checkPermissions(path, userId, "r") then
            local p, e = self:Permissions(path, userId)
            error(path .. " Permission denied or directory not found " .. p .. " " .. e)
        end

        return ofs.list(absolutePath)
    end
    function FS:isReadOnly(path, userId)
        local fs, relativePath = self:findFS(path, userId)
        return fs:_isReadOnly(relativePath, userId)
    end
    function FS:_isReadOnly(path,uid)

        if FS:exists(path,uid) then
            return not FS:checkPermissions(path,uid,"r")
        else
            local parentPath = self:getParentPath(path)
            return not FS:checkPermissions(parentPath,uid,"r")
        end
        
    end

    -- Check if user has required permissions for a given file
    function FS:checkPermissions(path, userId, accessType)
        path = path:gsub(" $", "")
        path = path:gsub("%/$", "")

        if #path == 0 then
            path = "/"
        end
        if path:sub(1, 1) ~= "/" then
            path = "/" .. path
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
    function FS:Permissions(path, userId)
        path = path:gsub(" $", "")
        if path:sub(1, 1) ~= "/" then
            path = "/" .. path
        end
        local meta = self.permissions[path]
        if not meta then return 0, "NOTFOUND" .. path end
        if userId == 0 then
            return 7
        end
        if userId == meta.ownerId then
            return meta.perms
        end
        return meta.allPerms, "GENERIC"
    end

    function FS:getPermissions(path, usr)
        local fs, relativePath = self:findFS(path, usr)
        return fs:_getPermissions(relativePath, usr)
    end

    function FS:_getPermissions(path, userId)
        path = path:gsub(" $", "")
        if path:sub(1, 1) ~= "/" then
            path = "/" .. path
        end
        local meta = self.permissions[path]
        if not meta then return 0, "NOTFOUND" .. path end
        if userId == 0 then
            return 7
        elseif userId == meta.ownerId then
            return meta.perms
        elseif userId == "G" then
            return meta.groupPerms
        end
        return meta.allPerms, "GENERIC"
    end

    local function printHex(str)
        for i = 1, #str, 1 do
            write(string.format("%02x ", string.sub(str, i, i):byte()))
        end
        print()
    end
    local function printComp(str)
        for i = 1, #str, 1 do
            write(string.sub(str, i, i) .. "  ")
        end
        print()
        printHex(str)
    end

    function FS:getOwner(path)
        local fs, relativePath = self:findFS(path, 0)
        return fs:_getOwner(relativePath)
    end

    function FS:_getOwner(path)
        path = path:gsub(" $", "")
        if path:sub(1, 1) ~= "/" then
            path = "/" .. path
        end
        local meta = self.permissions[path]
        --print(path,meta)
        --printComp(path)
        --printComp("/var/log/kern.log")
        return meta and meta.ownerId or 0
    end

    -- Make a directory
    function FS:makeDir(path, userId)
        local fs, relativePath = self:findFS(path, userId)
        return fs:_makeDir(relativePath, userId)
    end

    -- Make a directory
    -- Internal make directory function
    function FS:_makeDir(path, userId)
        local absolutePath = self.combine(self.storePath, path)
        local parentPath = self:getParentPath(path)
        local parentMeta = self.permissions[parentPath]
        if not parentMeta or not self:checkPermissions(parentPath, userId, "w") then
            return false, "Permission denied"
        end

        ofs.makeDir(absolutePath)
        self.permissions[path] = {
            perms = 7, -- Full permissions for owner
            ownerId = userId,
            groupPerms = 0,
            allPerms = 0,
            groupId = 0,
            created = os.time(),
            modified = os.time(),
            isDir = true
        }
        self:savePermissions()
        return true
    end

    function FS:getFreeSpace(path, userId)
        local fs, relativePath = self:findFS(path, userId)
        return fs:_getFreeSpace(relativePath, userId)
    end
    -- Make a directory
    function FS:_getFreeSpace(path, userId)
        local absolutePath = self.combine(self.storePath, path)
        return ofs.getFreeSpace(absolutePath)
    end

    -- Get the parent path of a given path
    function FS:getParentPath(path)
        local parentPath = path:match("(.*/)"):gsub("%/$", "")
        if #parentPath == 0 then
            parentPath = "/"
        end
        return parentPath or "/"
    end

    -- Delete a file or directory
    function FS:delete(path, userId)
        local fs, relativePath = self:findFS(path, userId)
        return fs:_delete(relativePath, userId)
    end

    -- Internal delete function
    function FS:_delete(path, userId)
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
    function FS:chmod(path, userId, newPermissions, scope)
        -- Find the filesystem and the relative path
        local fs, relativePath = self:findFS(path, userId)
        return fs:_chmod(relativePath, userId, newPermissions, scope)
    end

    -- Internal chmod function (used by the found filesystem)
    function FS:_chmod(path, userId, newPermissions, scope)
        local meta = self.permissions[path]

        if not meta then
            return nil, "File or directory not found"
        end

        -- Check if user has write permissions to modify the permissions of this item
        if not self:checkPermissions(path, userId, "w") then
            return nil, "Permission denied for changing permissions"
        end

        -- Update permissions for the file/directory
        if bit.band(scope, 1) ~= 0 then
            meta.perms = newPermissions
        end
        if bit.band(scope, 2) ~= 0 then
            meta.groupPerms = newPermissions
        end
        if bit.band(scope, 4) ~= 0 then
            meta.allPerms = newPermissions
        end

        meta.modified = os.time() -- Update the modification time
        self:savePermissions()

        return true -- Return true on success
    end

    -- Function to change the permissions of a file or directory
    function FS:takeOwn(path, userId)
        -- Find the filesystem and the relative path
        local fs, relativePath = self:findFS(path, userId)
        return fs:_takeOwn(relativePath, userId)
    end

    -- Internal chmod function (used by the found filesystem)
    function FS:_takeOwn(path, userId)
        local meta = self.permissions[path]

        if not meta then
            error "File or directory not found"
        end

        meta.ownerId = userId

        meta.modified = os.time() -- Update the modification time
        self:savePermissions()

        return true -- Return true on success
    end

    -- Function to execute a file using fs.open
    function FS:exec(path, userId)
        -- Find the filesystem and relative path
        local fs, relativePath = self:findFS(path, userId)
        return fs:_exec(relativePath, userId)
    end

    -- Internal exec function (used by the found filesystem)
    function FS:_exec(path, userId)
        -- Check if the file exists and if it's executable
        local meta = self.permissions[path]

        -- Check if the user has execute permissions
        if not self:checkPermissions(path, userId, "x") then
            error("Permission denied for execution " .. path .. " "..userId.." "..tostring(self:checkPermissions(path, userId, "x")), 2)
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
    function FS:isDir(path, userId)
        -- Find the filesystem and relative path

        local fs, relativePath = self:findFS(path, userId)
        return fs:_isDir(relativePath, userId)
    end

    -- Internal isDir function (used by the found filesystem)
    function FS:_isDir(path, userId)
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

    function FS:exists(path, userId)
        -- Find the filesystem and relative path
        local fs, relativePath = self:findFS(path, userId)
        return fs:_exists(relativePath, userId)
    end

    -- Internal isDir function (used by the found filesystem)
    function FS:_exists(path, userId)
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

    function FS:getDir(path)
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


    FS:loadPermissions()
    FS.permissions["/"] = {
        perms = 7,   -- Full permissions (rwx) for root
        ownerId = 0, -- Root is the owner
        groupId = 0,
        groupPerms = 0,
        allPerms = 4,
        created = os.time(),
        modified = os.time(),
        isDir = true
    }

    return FS
end

return RealFS

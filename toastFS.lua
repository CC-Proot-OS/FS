-- Buggy old code
-- DO Not use
-- TODO: Remove
local textutils = fs:exec("/lib/txtUtil.lua",0)()
local ofs = fs
-- Define the FileSystem class
local ToasterFileSystem = {}
ToasterFileSystem.__index = ToasterFileSystem

--- Constructor for the filesystem
--- @return ToasterFileSystem
--- @class ToasterFileSystem
function ToasterFileSystem:new()
    --- @class ToasterFileSystem
    local fs = {
        root = {
            bin = { permissions = { [0] = 7 }, isDir = true },
            home = { permissions = { [0] = 7 }, isDir = true }, -- Initialize home directory
            opt = { permissions = {}, isDir = true },
            tmp = { permissions = {}, isDir = true },
            usr = { permissions = {}, isDir = true },
            var = { permissions = {}, isDir = true,log={permissions = { [0] = 7 }, isDir = true} },
            boot = { permissions = {}, isDir = true },
            dev = { permissions = { [0] = 7 }, isDir = true },
            etc = { permissions = { [0] = 7 }, isDir = true },
            lib = { permissions = { [0] = 7 }, isDir = true, modul = { permissions = { [0] = 7 }, isDir = true }},
            permissions = {
                [0] = 7,   -- Root user has full permissions (read, write, execute)
            },
            isDir = true,  -- Mark root as a directory
        },
        users = { [0] = 7 }, -- Store user permissions by user ID
        files = {},         -- Store file data
        change = false
    }
    fs.combine = ofs.combine
    fs.getName = ofs.getName
    --- add a user with no permissions
    ---@param userId number user's id
    function fs:addUser(userId)
        self.users[userId] = 0 -- Assign no permissions to the new user

        -- Set read and execute permissions (5) for the root directory for this user
        self.root.permissions[userId] = 5
        local homeDir = "user" .. userId
        -- Create a home directory for the user
        --[[
    self.root.home[homeDir] = {
        permissions = {},
        isDir = true
    }
    -- Set default permissions for the home directory (full access for the user)]]
        self:makeDir("/home/" .. homeDir, 0)
        self.root.home[homeDir].permissions[userId] = 7 -- Full access for the user
        self.change = true
    end

    --- check permissions
    -- @private
    -- for internal use
    function fs:checkPermissions(item, userId, accessType)
        local userPerms = item.permissions[userId] or 0 -- Default to 0 if no permissions assigned
        local requiredPerms = 0
        if userId == 0 then
            return true
        end

        if accessType == "r" then
            requiredPerms = 4 -- Read permission
        elseif accessType == "w" then
            requiredPerms = 2 -- Write permission
        elseif accessType == "x" then
            requiredPerms = 1 -- Execute permission
        end

        return bit.band(userPerms, requiredPerms) > 0
    end

    --- Gets perms for a user for a file
    -- @param path string
    -- @param userId number
    -- @return number
    function fs:Permissions(path, userId)
        local tgt = self:navigate(path)
        if tgt == nil then
            error("Not Found")
        end
        local userPerms = tgt.permissions[userId] or 0 -- Default to 0 if no permissions assigned
        local requiredPerms = 0
        if userId == 0 then
            return 7
        end


        return userPerms
    end
    

    --- Function to mount another filesystem to a specified path
    ---@param path string
    ---@param otherFS FileSystem
    ---@param user number
    function fs:mount(path, otherFS, user)
        local targetDir = self:navigate(path)

        if not targetDir or not targetDir.isDir then
            error "Target directory not found or permission denied."
        end

        if not self:checkPermissions(targetDir, user, "w") then
            error "Permission denied."
        end

        -- Set the mounted filesystem in the target directory
        targetDir.mountedFs = otherFS
    end

    --- Function to mount another filesystem to a specified path
    ---@param path string
    ---@param user number
    function fs:unmount(path, user)
        local targetDir = self:navigate(path)

        if not targetDir or not targetDir.isDir then
            error "Target directory not found or permission denied."
        end

        if not self:checkPermissions(targetDir, user, "w") then
            error "Permission denied."
        end
        if targetDir.mountedFs == nil then
            error "No FS mounted"
        end

        -- Set the mounted filesystem in the target directory
        targetDir.mountedFs = nil
    end

    -- Function to open a file and return a stream
    ---@param path string
    ---@param mode string
    ---@param userId number
    ---@return Stream
    function fs:open(path, mode, userId)
        local target = self:navigate(path)
        local parentDirPath = path:match("(.*/)")                           -- Extract parent directory path
        local parentDir = parentDirPath and self:navigate(parentDirPath) or nil -- Navigate to parent directory

        if parentDir and parentDir.mountedFs then
            -- If the target is a mounted filesystem, delegate to it
            return parentDir.mountedFs:open(path, mode, userId)
        end

        local function mkFlush(target)
            return function(cont)
                --print("FLUSH")
                target.contents = cont
                target.modified = os.time("utc")
                self.change = true
            end
        end

        -- Handle read and read+ modes
        if mode == "r" or mode == "r+" then
            if not target or not target.isDir and not target.contents then
                error "File not found or permission denied."
            end
            if not self:checkPermissions(target, userId, "r") then
                error "Permission denied."
            end

            -- Return a stream object for reading
            return self:createStream(target.contents or "", mode, mkFlush(target)), nil

            -- Handle write and write+ modes
        elseif mode == "w" or mode == "w+" then
            if not parentDir or not parentDir.isDir then
                error "Parent directory not found."
            end

            if not self:checkPermissions(parentDir, userId, "w") then
                error "Permission denied on parent directory."
            end
            local t = os.time("utc")
            local fl
            fl = self:navigate(path)
            if fl ~= nil then
                t = fl.created
            end

            -- Create or overwrite the file
            local filename = path:match("([^/]+)$") -- Extract file name
            target = { contents = "", permissions = {}, isDir = false, created = t, modified = t }
            target.permissions[userId] = 6
            parentDir[filename] = target -- Add the new file to the parent directory
            self.change = true
            return self:createStream(target.contents, mode, mkFlush(target))

            -- Handle append mode
        elseif mode == "a" then
            if not target or (target.isDir) then
                error "File not found."
            end
            if not self:checkPermissions(target, userId, "w") then
                error "Permission denied."
            end

            -- Append to the file
            return self:createStream(target.contents or "", mode, mkFlush(target)), nil
        end

        error "Invalid mode."
    end

    --- Function to create a stream object
    ---@class Stream
    ---@param contents string
    ---@param mode string
    ---@param flush function
    ---@return Stream
    function fs:createStream(contents, mode, flush)
        ---@class Stream
        local stream = {
            contents = contents,
            position = 1,
            mode = mode,
            isOpen = true,
        }

        -- Method to read from the stream
        function stream:read(size)
            self = self or stream
            size = size or 1
            if not self.isOpen then
                return nil, ("Stream is closed.")
            end
            if self.mode:find("r") or self.mode:find("+") then
                local data = self.contents:sub(self.position, self.position + size - 1)
                self.position = self.position + size
                return data
            else
                return nil, "Stream not open for reading."
            end
        end

        function stream:readAll()
            self = self or stream
            if not self.isOpen then
                return nil, ("Stream is closed.")
            end
            if self.mode:find("r") or self.mode:find("+") then
                return self.contents
            else
                return nil, "Stream not open for reading."
            end
        end
        function stream:readLine()
            self = self or stream
            if not self.isOpen then
                return nil, ("Stream is closed.")
            end
            if self.mode:find("r") or self.mode:find("+") then
                local c = ""
                local l = ""
                while l~="\n" do
                    l = self:read()
                    if l~="\n" then
                        c = c..l
                    end
                end
                return c
            else
                return nil, "Stream not open for reading."
            end
        end

        -- Method to write to the stream
        function stream:write(data)
            self = self or stream
            if not self.isOpen then
                return nil, ("Stream is closed.")
            end
            if self.mode:find("w") or self.mode:find("a") or self.mode:find("+") then
                self.contents = self.contents .. data -- Append
                return #data
            else
                return nil, "Stream not open for writing."
            end
        end

        -- Method to seek to a specific position in the stream
        function stream:seek(offset, whence)
            self = self or stream
            if not self.isOpen then
                return nil, ("Stream is closed.")
            end
            if whence == "set" then
                self.position = offset
            elseif whence == "cur" then
                self.position = self.position + offset
            elseif whence == "end" then
                self.position = #self.contents + offset
            end
            return self.position
        end

        -- Method to flush the buffer to the file
        function stream:flush()
            self = self or stream
            if not self.isOpen then
                return nil, ("Stream is closed.")
            end
            if self.mode:find("w") or self.mode:find("a") or self.mode:find("+") then
                flush(self.contents)
            else
                return nil, "Stream not open for writing."
            end
        end

        -- Method to close the stream
        function stream:close()
            self = self or stream
            if not self.isOpen then
                return  -- Stream is already closed
            end
            self:flush() -- Ensure any buffered data is written
            self.isOpen = false -- Mark the stream as closed
        end

        return stream
    end

    --- find the filesystem and relative path for a given absolute path
    ---@param path string
    ---@return FileSystem
    ---@return string
    function fs:findFs(path,igerr)
        local parts = self:splitPath(path)
        local currentFs = self -- Start with the root filesystem
        local currentDir = currentFs.root
        local relativePath = "/" -- Path relative to the found filesystem

        for i, part in ipairs(parts) do
            if currentDir and currentDir[part] then
                local item = currentDir[part]

                -- If the item is a directory, move into it
                if item.isDir then
                    if item.mountedFs then
                        -- If it's a mount point, switch to the mounted filesystem
                        currentFs = item.mountedFs
                        currentDir = currentFs.root
                        relativePath = "/" .. table.concat(parts, "/", i + 1)
                        return currentFs, relativePath
                    else
                        -- Normal directory, continue into it
                        currentDir = item
                    end
                else
                    -- If it's a file, return up to this point
                    relativePath = "/" .. table.concat(parts, "/")
                    return currentFs, relativePath
                end
            else
                if igerr then
                    return self,path
                end
                return self,path
                --error "Path not found."
            end
        end

        -- Return the filesystem and relative path if we finish traversing the path
        return currentFs, "/" .. table.concat(parts, "/")
    end

    --- Function to list files and directories with permission checks and return a table
    ---@param path string
    ---@param userId number
    ---@return table
    function fs:list(path, userId)
        -- Navigate to the directory for the given path
        local parts = self:splitPath(path)
        local currentDir = self:navigate(path)

        -- Traverse the path to reach the correct directory

        if not self:checkPermissions(currentDir, userId, "r") then
            error("permission denied: " .. (path or "/"))
        end
        -- List contents of the current directory
        if currentDir.isDir then
            local contents = {}

            for name, item in pairs(currentDir) do
                if type(item) == "table" and item.isDir ~= nil then
                    table.insert(contents, name)
                end
            end

            return contents
        else
            error "Not a directory."
        end
    end

    --- Utility function to split a path into its components
    ---@param path string
    ---@return table
    function fs:splitPath(path)
        local parts = {}
        for part in string.gmatch(path, "[^/]+") do
            table.insert(parts, part)
        end
        return parts
    end

    --- Helper function to navigate to a directory or file
    --- Recursively navigate directories, including mounted filesystems
    ---@param path string
    ---@return table|nil
    ---@return nil|string
    function fs:navigate(path)
        local parts = self:splitPath(path)
        local currentDir = self.root

        for _, part in ipairs(parts) do
            if currentDir and currentDir[part] then
                local item = currentDir[part]

                if item.isDir then
                    currentDir = item
                else
                    return item -- Return the item if it's a file
                end
            else
                return nil, "Directory or file not found."
            end
        end
        --if currentDir.isDir then
        --    local host = currentDir
        --    if currentDir.mountedFs then
        --        -- If this directory is a mounted filesystem, switch to that filesystem
        --        return currentDir.mountedFs.root
        --    end
        --end
        return currentDir
    end

    --- Function to execute a script from a given file path
    ---@param path string
    ---@param userId number
    ---@return function
    function fs:exec(path, userId)
        local target = self:navigate(path)
        -- Check if the target is a file and if it exists
        if not target or target.isDir or not target.contents then
            error("File not found or is a directory: " .. path)
        end

        -- Check if the user has execute permissions for the file
        if not self:checkPermissions(target, userId, "x") then
            error "Permission denied."
        end

        -- Create a function to execute the file's contents
        local execFunction, err = load(target.contents,path) -- Load the Lua code in the file
        if not execFunction then
            error("Failed to load file: " .. err)
        end

        return execFunction -- Return the function to execute
    end

    --- Function to change the permissions of a file or directory for a specific user
    ---@param path string
    ---@param userId number
    ---@param targetUserId number
    ---@param newPermissions number
    ---@return boolean
    function fs:chmod(path, userId, targetUserId, newPermissions)
        local target = self:navigate(path)

        -- Check if the target exists and is a valid file or directory
        if not target or (not target.isDir and not target.contents) then
            error("File or directory not found: " .. path)
        end

        -- Check if the user has permission to change permissions (needs write access to parent directory)
        local parentDir = self:navigate(self:getDir(path))
        if not self:checkPermissions(parentDir, userId, "w") then
            error "Permission denied."
        end

        -- Update the permissions for the target item for the specified user
        target.permissions[targetUserId] = newPermissions
        return true -- Return success
    end

    --- Function to get the parent path of a given path
    ---@param path string
    ---@return string|nil
    function fs:getDir(path)
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

    --- Function to serialize and save the filesystem to disk
    ---@param filename string
    ---@return boolean
    function fs:saveToDisk(filename)
        local file, err = ofs.open(filename, "w")
        if not file then
            error(err)
        end

        -- Prepare the data to be saved, excluding mounted filesystems
        local dataToSave = {
            home = self:serializeDirectory(self.root.home),
            bin = self:serializeDirectory(self.root.bin),
            lib = self:serializeDirectory(self.root.lib),
            boot = self:serializeDirectory(self.root.boot),
            etc = self:serializeDirectory(self.root.etc),
            var = self:serializeDirectory(self.root.var),
        }


        -- Serialize the data using textutils
        local serializedData = textutils.serialize(dataToSave, { allow_repetitions = true })

        -- Write the serialized data to the file
        file.write(serializedData)
        file.close()

        return true -- Indicate success
    end

    --- Helper function to serialize a directory
    ---@param directory string
    ---@return table
    function fs:serializeDirectory(directory)
        local serializedContents = {
            isDir = directory.isDir,
            permissions = directory.permissions,
        }
        for n, item in pairs(directory) do
            --print(n,item)
            if n ~= "mountedFs" and (serializedContents[n] == nil) and type(item) == "table" then
                if item.isDir == true then -- Exclude mounted filesystems
                    local serializedItem = {
                        isDir = item.isDir,
                        permissions = item.permissions,

                    }
                    for key, value in pairs(item) do
                        if key ~= "mountedFs" and serializedItem[key] == nil then
                            serializedItem[key] = self:serializeDirectory(value)
                        end
                    end
                    serializedContents[n] = self:serializeDirectory(item)
                else
                    local serializedItem = {
                        isDir = item.isDir,
                        permissions = item.permissions,

                    }
                    serializedItem.contents = item.contents -- Serialize contents
                    serializedContents[n] = serializedItem
                end
            end
        end
        return serializedContents
    end

    

    --- Function to load the filesystem from disk
    ---@param filename string
    ---@return boolean
    function fs:loadFromDisk(filename)
        local file, err = ofs.open(filename, "r")
        if not file then
            error(err)
        end

        -- Read the entire file contents
        local serializedData = file.readAll()
        file:close()

        -- Unserialize the data using textutils
        local dataLoaded = textutils.unserialize(serializedData)

        -- Rebuild the filesystem from the loaded data
        if dataLoaded and dataLoaded.home then
            self.root.home = dataLoaded.home
        end
        if dataLoaded and dataLoaded.lib then
            self.root.lib = dataLoaded.lib
        end
        if dataLoaded and dataLoaded.bin then
            self.root.bin = dataLoaded.bin
        end
        if dataLoaded and dataLoaded.boot then
            self.root.boot = dataLoaded.boot
        end
        if dataLoaded and dataLoaded.etc then
            self.root.etc = dataLoaded.etc
        end
        if dataLoaded and dataLoaded.var then
            self.root.var = dataLoaded.var
        end

        return true -- Indicate success
    end

    --[[ Helper function to unserialize a directory
    function FileSystem:unserializeDirectory(data)
        local directory = {
            name = data.name,
            isDir = data.isDir,
            permissions = data.permissions,
            contents = {}
        }

        for _, item in pairs(data.contents) do
            -- Create a new entry for each item
            local newItem = {
                name = item.name,
                isDir = item.isDir,
                permissions = item.permissions,
                contents = item.isDir and {} or nil -- Initialize contents if it's a directory
            }
            table.insert(directory.contents, newItem)

            -- If it's a directory, recursively unserialize its contents
            if item.isDir and item.contents then
                newItem.contents = self:unserializeDirectoryContents(item.contents)
            end
        end

        return directory
    end

    -- Helper function to unserialize contents of a directory
    function FileSystem:unserializeDirectoryContents(contents)
        local dirContents = {}
        for _, item in pairs(contents) do
            table.insert(dirContents, {
                name = item.name,
                isDir = item.isDir,
                permissions = item.permissions,
                contents = item.isDir and {} or nil -- Initialize contents if it's a directory
            })
        end
        return dirContents
    end]]

    ---makes a dir
    ---@param path string
    ---@param usr number
    function fs:makeDir(path, usr)
        local parent = self:navigate(self:getDir(path))
        if self:checkPermissions(parent, usr, "w") then
            local name = path:match("([^/]+)$") -- Extract file name
            parent[name] = {
                isDir = true,
                permissions = {}
            }
            parent[name].permissions[usr] = 7
            self.change = true
        end
    end

    --- Function to check if a file or directory exists
    ---@param path string
    ---@return boolean
    function fs:exists(path)
        local targetItem = self:navigate(path)
        return targetItem ~= nil
    end

    --- Function to get the size of a file (or return 0 for directories)
    ---@param path string
    ---@return integer
    function fs:getSize(path)
        local targetItem = self:navigate(path)

        if not targetItem then
            error "File or directory not found."
        end

        if targetItem.isDir then
            return 0               -- Directories return 0 for simplicity
        elseif targetItem.content then
            return #targetItem.content -- Return the length of the file content
        else
            return 0               -- If no content exists, size is 0
        end
    end

    ---is path a dir
    ---@param path string
    ---@return boolean
    function fs:isDir(path)
        local targetItem = self:navigate(path)
        return targetItem and targetItem.isDir or false
    end

    --- Function to return attributes of a file or directory
    ---@param path string
    ---@param user number
    ---@return table
    function fs:attributes(path, user)
        local targetItem = self:navigate(path)

        if not targetItem then
            error "File or directory not found."
        end

        local attributes = {
            size = targetItem.isDir and 0 or (targetItem.content and #targetItem.content or 0),
            isDir = targetItem.isDir,
            isReadOnly = self:checkPermissions(targetItem, user, "w") == false, -- Check if user 0 (root) has write permission
            created = targetItem.created or os.time(),                      -- If no timestamp, set current time as fallback
            modified = targetItem.modified or os.time()
        }

        return attributes
    end

    ---moves a file
    ---@param path string
    ---@param dest string
    ---@param usr number
    function fs:move(path, dest, usr)
        local targetItem = self:navigate(path)
        local tgtP = self:navigate(self:getDir(path))
        --local destItem = self:navigate(dest)
        local destP = self:navigate(self:getDir(dest))
        if self:checkPermissions(targetItem, usr, "w") and self:checkPermissions(destP, usr, "w") then
            local filename = path:match("([^/]+)$") -- Extract file name
            destP[filename] = targetItem
            tgtP[filename] = nil
            self.change = true
        end
    end

    function fs:delete(path, usr)
        local targetItem = self:navigate(path)
        local tgtP = self:navigate(self:getDir(path))
        if self:checkPermissions(targetItem, usr, "w") then
            local filename = path:match("([^/]+)$") -- Extract file name
            tgtP[filename] = nil
            self.change = true
        end
    end

    ---copys a file
    ---@param path string
    ---@param dest string
    ---@param usr number
    function fs:copy(path, dest, usr)
        local targetItem = self:navigate(path)
        local tgtP = self:navigate(self:getDir(path))
        --local destItem = self:navigate(dest)
        local destP = self:navigate(self:getDir(dest))
        if self:checkPermissions(targetItem, usr, "r") and self:checkPermissions(destP, usr, "w") then
            local filename = path:match("([^/]+)$") -- Extract file name
            destP[filename] = targetItem
            self.change = true
        end
    end

    --setmetatable(fs, FileSystem)

    return fs
end

return ToasterFileSystem

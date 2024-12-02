WrapperFS = {}

-- Constructor for WrapperFS
function WrapperFS:new(baseFs)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.baseFs = baseFs  ,usr-- The root or initial filesystem that we wrap
    o.combine = baseFs.combine
    o.getName = baseFs.getName
    return o
end
function WrapperFS:addUser(usr)
    return self.baseFs:addUser(usr)
end
function WrapperFS:saveToDisk(path)
    return self.baseFs:saveToDisk(path)
end


-- Helper function to find the filesystem and relative path
function WrapperFS:findFs(path,ig)
    return self.baseFs:findFs(path,ig)
end

-- Wrapper function for `ls`
function WrapperFS:list(path,usr)
    local fs, relativePath = self:findFs(path)
    if fs then
        --print("Listing contents of:", relativePath, "in filesystem:", fs)
        return fs:list(relativePath,usr)
    else
        return nil, "Path not found."
    end
end

function WrapperFS:isReadOnly(path,usr)
    local fs, relativePath = self:findFs(path)
    if fs then
        --print("Listing contents of:", relativePath, "in filesystem:", fs)
        return fs:isReadOnly(relativePath,usr)
    else
        return nil, "Path not found."
    end
end

-- Wrapper function for `open`
function WrapperFS:open(path, mode, userId)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:open(relativePath, mode, userId)
    else
        return nil, "Path not found."
    end
end

-- Wrapper function for `mkdir`
function WrapperFS:makeDir(path, userId)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:makeDir(relativePath, userId)
    else
        return nil, "Path not found."
    end
end

-- Wrapper function for `chmod`
function WrapperFS:chmod(path, userId, targetUserId, permissions)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:chmod(relativePath, userId, targetUserId, permissions)
    else
        return nil, "Path not found."
    end
end

-- Wrapper function for `attributes`
function WrapperFS:attributes(path,usr)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:attributes(relativePath,usr)
    else
        return nil, "Path not found."
    end
end
function WrapperFS:exec(path,usr)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:exec(relativePath,usr)
    else
        return nil, "Path not found."
    end
end
function WrapperFS:mount(path,FS,usr)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:mount(relativePath,FS,usr)
    else
        return nil, "Path not found."
    end
end
function WrapperFS:unmount(path,usr)
    local rfs, relativePath = self:findFs("/")
    if rfs then
        return rfs:unmount(path,usr)
    else
        return nil, "Path not found."
    end
end

-- Wrapper function for `getSize`
function WrapperFS:getSize(path)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:getSize(relativePath)
    else
        return nil, "Path not found."
    end
end

-- Wrapper function for `exists`
function WrapperFS:exists(path)
    --print(path)
    local fs, relativePath = self:findFs(path,true)
    if fs then
        return fs:exists(relativePath)
    else
        return false
    end
end
function WrapperFS:move(path,dest,usr)
    local fs, relativePath = self:findFs(path)
    local fs2, relativePath2 = self:findFs(dest)
    assert(fs==fs2,"Moving between diffrent fs is not curently suported") -- TODO FIX
    if fs then
        return fs:move(relativePath,relativePath2,usr)
    else
        return nil, "Path not found."
    end
end
function WrapperFS:copy(path,dest,usr)
    local fs, relativePath = self:findFs(path)
    local fs2, relativePath2 = self:findFs(dest)
    assert(fs==fs2,"Copying between diffrent fs is not curently suported") -- TODO FIX
    if fs then
        return fs:copy(relativePath,relativePath2,usr)
    else
        return nil, "Path not found."
    end
end
-- Wrapper function for `isDir`
function WrapperFS:isDir(path)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:isDir(relativePath)
    else
        return nil, "Path not found."
    end
end

function WrapperFS:delete(path)
    local fs, relativePath = self:findFs(path)
    if fs then
        return fs:delete(relativePath)
    else
        return nil, "Path not found."
    end
end

function WrapperFS:Permissions(path, userId)
    local rfs, relativePath = self:findFs(path)
    --print(rfs,relativePath)
    if rfs then
        return rfs:Permissions(relativePath,userId)
    else
        return nil, "Path not found."
    end
end
function WrapperFS:save(path)
    local rfs, relativePath = self:findFs("/")
    rfs:saveToDisk(path)
    self.baseFs.change = false
end
function WrapperFS:isChanged()
    return self.baseFs.change
end
function WrapperFS:getDir(path)
    return self.baseFs:getDir(path)
end
return WrapperFS
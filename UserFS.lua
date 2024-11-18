UserFS = {}
local expect = dofile("rom/modules/main/cc/expect.lua")

-- Constructor for UserFS
---@param baseFs FileSystem
---@param usr number
---@return UserFS
function UserFS:new(baseFs,usr)
    ---@class UserFS
    local o = {}
    o.baseFs = baseFs  -- The root or initial filesystem that we wrap
    o.combine = baseFs.combine
    o.getName = baseFs.getName

    -- Wrapper function for `ls`
    function o.list(path)
        return baseFs:list(path, usr)
    end

    -- Wrapper function for `open`
    function o.open(path, mode)
        return baseFs:open(path, mode, usr)
    end

    -- Wrapper function for `mkdir`
    function o.makeDir(path)
        return baseFs:makeDir(path, usr)
    end

    -- Wrapper function for `chmod`
    function o.chmod(path, targetUserId, permissions)
        baseFs:chmod(path, usr, targetUserId, permissions)
        
    end

    -- Wrapper function for `attributes`
    function o.attributes(path)
        return baseFs:attributes(path, usr)
    end

    function o.exec(path)
        return baseFs:exec(path, usr)
    end

    function o.mount(path, FS)
        return baseFs:mount(path, FS, usr)
    end

    function o.unmount(path)
        return baseFs:unmount(path, usr)
    end

    -- Wrapper function for `getSize`
    function o.getSize(path)
        return baseFs:getSize(path)
    end

    -- Wrapper function for `exists`
    function o.exists(path)
        --coroutine.yield("SYSCALL","log",{{level="debug"},"run",path,debug.traceback()})
        --assert(path ~= nil)
        return baseFs:exists(path,usr)
    end

    function o.move(path, dest)
    
        return baseFs:move(path, dest, usr)
    end

    function o.copy(path, dest)
        return baseFs:copy(path, dest, usr)
    end

    -- Wrapper function for `isDir`
    function o.isDir(path)
        return baseFs:isDir(path,usr)
    end

    function o.delete(path)
        return baseFs:delete(path,usr)

    end

    function o.Permissions(path)
        return baseFs:Permissions(path, usr)
    end
    function o.getPermissions(path, user)
        return baseFs:getPermissions(path, user)
    end
    function o.getOwner(path)
        return baseFs:getOwner(path)
    end

    function o.complete(sPath, sLocation, bIncludeFiles, bIncludeDirs)
        expect.expect(1, sPath, "string")
        expect.expect(2, sLocation, "string")
        local bIncludeHidden = nil
        if type(bIncludeFiles) == "table" then
            bIncludeDirs = expect.field(bIncludeFiles, "include_dirs", "boolean", "nil")
            bIncludeHidden = expect.field(bIncludeFiles, "include_hidden", "boolean", "nil")
            bIncludeFiles = expect.field(bIncludeFiles, "include_files", "boolean", "nil")
        else
            expect(3, bIncludeFiles, "boolean", "nil")
            expect(4, bIncludeDirs, "boolean", "nil")
        end
    
        bIncludeHidden = bIncludeHidden ~= false
        bIncludeFiles = bIncludeFiles ~= false
        bIncludeDirs = bIncludeDirs ~= false
        local sDir = sLocation
        local nStart = 1
        local nSlash = string.find(sPath, "[/\\]", nStart)
        if nSlash == 1 then
            sDir = ""
            nStart = 2
        end
        local sName
        while not sName do
            local nSlash = string.find(sPath, "[/\\]", nStart)
            if nSlash then
                local sPart = string.sub(sPath, nStart, nSlash - 1)
                sDir = o.combine(sDir, sPart)
                nStart = nSlash + 1
            else
                sName = string.sub(sPath, nStart)
            end
        end
    
        if o.isDir(sDir) then
            local tResults = {}
            if bIncludeDirs and sPath == "" then
                table.insert(tResults, ".")
            end
            if sDir ~= "" then
                if sPath == "" then
                    table.insert(tResults, bIncludeDirs and ".." or "../")
                elseif sPath == "." then
                    table.insert(tResults, bIncludeDirs and "." or "./")
                end
            end
            local tFiles = o.list(sDir)
            for n = 1, #tFiles do
                local sFile = tFiles[n]
                if #sFile >= #sName and string.sub(sFile, 1, #sName) == sName and (
                    bIncludeHidden or sFile:sub(1, 1) ~= "." or sName:sub(1, 1) == "."
                ) then
                    local bIsDir = o.isDir(o.combine(sDir, sFile))
                    local sResult = string.sub(sFile, #sName + 1)
                    if bIsDir then
                        table.insert(tResults, sResult .. "/")
                        if bIncludeDirs and #sResult > 0 then
                            table.insert(tResults, sResult)
                        end
                    else
                        if bIncludeFiles and #sResult > 0 then
                            table.insert(tResults, sResult)
                        end
                    end
                end
            end
            return tResults
        end
    
        return {}
    end
    function o.getDir(path)
        return o.baseFs:getDir(path)
    end
    return o
end

return UserFS

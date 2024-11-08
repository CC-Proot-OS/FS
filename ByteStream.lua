local ByteStream = {}
ByteStream.__index = ByteStream

-- Constructor
---@class Sream
function ByteStream.new()
    local self = setmetatable({}, ByteStream)
    self.data = {}
    self.position = 1  -- Start position
    -- Write function (writes bytes at the current position)
    function self.write(bytes)
        for i = 1, #bytes do
            self.data[self.position] = string.sub(bytes, i, i)
            self.position = self.position + 1
        end
    end

    -- WriteLine function (writes a string followed by a newline)
    function self.writeLine(line)
        self.write(line)
        self.write("\n")  -- Add newline at the end
    end

    -- Read function (reads n bytes from the current position)
    function self.read(n)
        local result = {}

        -- Adjust n if it exceeds the remaining bytes
        local end_pos = math.min(self.position + n - 1, #self.data)

        for i = self.position, end_pos do
            table.insert(result, self.data[i])
            self.position = self.position + 1
        end

        return table.concat(result)
    end

    -- Read all function (reads all bytes from the current position to the end)
    function self.read_all()
        if self.position > #self.data then
            return ""  -- If the position is beyond the data, return an empty string
        end
        local result = {}

        for i = self.position, #self.data do
            table.insert(result, self.data[i])
        end

        self.position = #self.data + 1  -- Move position to the end of the stream

        return table.concat(result)
    end

    -- ReadLine function (reads bytes until it encounters a newline or reaches the end)
    function self.readLine()
        if self.position > #self.data then
            return nil  -- If the position is beyond the data, return nil (no more lines)
        end

        local result = {}
        
        while self.position <= #self.data do
            local byte = self.data[self.position]
            self.position = self.position + 1

            if byte == "\n" then
                break
            end

            table.insert(result, byte)
        end

        return table.concat(result)
    end

    -- Seek function (moves the position within the stream)
    -- mode can be 'set', 'cur', or 'end'
    function self.seek(offset, mode)
        mode = mode or "set"

        if mode == "set" then
            self.position = offset + 1
        elseif mode == "cur" then
            self.position = self.position + offset
        elseif mode == "end" then
            self.position = #self.data + offset + 1
        end

        -- Clamp the position to ensure it stays within valid bounds
        if self.position < 1 then
            self.position = 1
        elseif self.position > #self.data + 1 then
            self.position = #self.data + 1
        end
    end

    -- Clear the stream
    function self.clear()
        self.data = {}
        self.position = 1
    end
    return self
end


return ByteStream
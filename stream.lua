local class = require '30log'
local Stream = class()
Stream.__name = "Stream"

function Stream:bytesToNum(bytes)
	local n = 0
	for _, v in ipairs(bytes) do
		n = (n << 8) + v
	end
	n = (n > 2147483647) and (n - 4294967296) or n
	return n
end

function Stream:__init(param)
	self.data = {}
	self.position = 1

	local str = ""
	if (param.inputF ~= nil) then
		local f = assert(io.open(param.inputF, "rb"), param.inputF)
		str = f:read("*all")
	end
	if (param.input ~= nil) then
		str = param.input
	end

	for i=1,#str do
		self.data[i] = str:byte(i, i)
	end
end

function Stream:seek(amount)
	self.position = self.position + amount
end

function Stream:readByte()
	if self.position <= 0 then self:seek(1) return nil end
	local byte = self.data[self.position]
	self:seek(1)
	return byte
end

function Stream:readyReadBit()
	self.accumulator = 0
	self.bitCount = 0
end

function Stream:readBit(num)
	if self.position <= 0 then self:seek(1) return nil end
	if self.bitCount <= 0 then
		self.accumulator = self:readByte()
		self.bitCount = 8
	end

	self.bitCount = self.bitCount - num
	return self.accumulator >> self.bitCount & (2^num - 1)
end

function Stream:readChars(num)
	if self.position <= 0 then self:seek(1) return nil end
	local t = {}
	for i = 1, num do
		t[i] = self:readChar()
	end
	return table.concat(t)
end

function Stream:readChar()
	if self.position <= 0 then self:seek(1) return nil end
	return string.char(self:readByte())
end

function Stream:readBytes(num)
	if self.position <= 0 then self:seek(1) return nil end
	local tabl = {}
	local i = 1
	while i <= num do
		local curByte = self:readByte()
		if curByte == nil then break end
		tabl[i] = curByte
		i = i + 1
	end
	return tabl, i-1
end

function Stream:readInt(num)
	if self.position <= 0 then self:seek(1) return nil end
	num = num or 4
	local bytes, count = self:readBytes(num)
	return self:bytesToNum(bytes), count
end

function Stream:writeByte(byte)
	if self.position <= 0 then self:seek(1) return end
	self.data[self.position] = byte
	self:seek(1)
end

function Stream:writeChar(char)
	if self.position <= 0 then self:seek(1) return end
	self:writeByte(char:byte())
end

function Stream:writeBytes(buffer)
	if self.position <= 0 then self:seek(1) return end
	for _, v in ipairs(buffer) do
		self:writeByte(v)
	end
end

return Stream

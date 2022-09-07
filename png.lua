local class = require '30log'
local deflate = require 'deflate'
local Stream = require 'stream'

local Chunk = class()
Chunk.__name = "Chunk"

function Chunk:__init(stream)
	if stream.__name == "Chunk" then
		self.length = stream.length
		self.name = stream.name
		self.data = stream.data
		self.crc = stream.crc
	else
		self.length = stream:readInt()
		self.name = stream:readChars(4)
		self.data = stream:readChars(self.length)
		self.crc = stream:readChars(4)
	end
end

function Chunk:getDataStream()
	return Stream({input = self.data})
end

local IHDR = Chunk:extends()
IHDR.__name = "IHDR"

function IHDR:__init(chunk)
	self.super.__init(self, chunk)
	local stream = chunk:getDataStream()
	self.width = stream:readInt()
	self.height = stream:readInt()
	self.bitDepth = stream:readByte()
	self.colorType = stream:readByte()
	self.compression = stream:readByte()
	self.filter = stream:readByte()
	self.interlace = stream:readByte()
end

local IDAT = Chunk:extends()
IDAT.__name = "IDAT"

function IDAT:__init(chunk)
	self.super.__init(self, chunk)
end

local PLTE = Chunk:extends()
PLTE.__name = "PLTE"

function PLTE:__init(chunk)
	self.super.__init(self, chunk)
	self.numColors = chunk.length // 3
	self.colors = {}
	local stream = chunk:getDataStream()
	for i = 1, self.numColors do
		self.colors[i] = {
			R = stream:readByte(),
			G = stream:readByte(),
			B = stream:readByte(),
		}
	end
end

function PLTE:getColor(index)
	return self.colors[index]
end

local tRNS = Chunk:extends()
tRNS.__name = "tRNS"

function tRNS:__init(chunk, colorType, palette)
	self.super.__init(self, chunk)

	local stream = chunk:getDataStream()
	if colorType == 0 then
		local grey = stream:readInt(2)
		self.R = grey
		self.G = grey
		self.B = grey
	elseif colorType == 2 then
		self.R = stream:readInt(2)
		self.G = stream:readInt(2)
		self.B = stream:readInt(2)
	elseif colorType == 3 then
		self.Alphas = {}
		for i = 1, chunk.length do
			self.Alphas[i] = stream:readByte()
		end
	else
		error ('Invalid colortype:' .. colorType)
	end
end

function tRNS:getAlpha(index)
	return self.Alphas[index] or 255
end

local tEXt = Chunk:extends()
IDAT.__name = "tEXt"

function tEXt:__init(chunk)
	self.super.__init(self, chunk)
	self.key, self.value = self.data:match("(.+)\0(.*)")
end

local Pixel = class()
Pixel.__name = "Pixel"

function Pixel:__init(stream, depth, colorType, palette, trns)
	--0, /*grayscale: 1,2,4,8,16 bit*/
	--2, /*RGB: 8,16 bit*/
	--3, /*palette: 1,2,4,8 bit*/
	--4, /*grayscale with alpha: 8,16 bit*/
	--6, /*RGB with alpha: 8,16 bit*/
	local bps = depth // 8
	if colorType == 0 then
		local grey = bps > 0 and stream:readInt(bps) or stream:readBit(depth)
		self.R = grey
		self.G = grey
		self.B = grey
		self.A = 255
	elseif colorType == 2 then
		self.R = stream:readInt(bps)
		self.G = stream:readInt(bps)
		self.B = stream:readInt(bps)
		self.A = 255
	elseif colorType == 3 then
		local index = bps > 0 and stream:readInt(bps) + 1 or stream:readBit(depth) + 1
		local color = palette:getColor(index)
		self.R = color.R
		self.G = color.G
		self.B = color.B
		self.A = trns:getAlpha(index)
	elseif colorType == 4 then
		local grey = stream:readInt(bps)
		self.R = grey
		self.G = grey
		self.B = grey
		self.A = stream:readInt(bps)
	elseif colorType == 6 then
		self.R = stream:readInt(bps)
		self.G = stream:readInt(bps)
		self.B = stream:readInt(bps)
		self.A = stream:readInt(bps)
	else
		error ('Invalid colortype:' .. colorType)
	end
end

function Pixel:format()
	return string.format("R: %d, G: %d, B: %d, A: %d", self.R, self.G, self.B, self.A)
end

local ScanLine = class()
ScanLine.__name = "ScanLine"

function ScanLine:__init(stream, depth, colorType, palette, trns, length)
	local bpp = depth // 8 * self:bitFromColorType(colorType)
	local bpl = bpp*length
	self.pixels = {}
	self.filterType = stream:readByte()
	stream:seek(-1)
	stream:writeByte(0)
	local startLoc = stream.position
	if self.filterType == 0 then
		stream:readyReadBit()
		for i = 1, length do
			self.pixels[i] = Pixel(stream, depth, colorType, palette, trns)
		end
	elseif self.filterType == 1 then
		for i = 1, length do
			for _ = 1, bpp do
				local curByte = stream:readByte()
				stream:seek(-(bpp+1))
				local lastByte = 0
				if stream.position >= startLoc then lastByte = stream:readByte() or 0 else stream:readByte() end
				stream:seek(bpp-1)
				stream:writeByte((curByte + lastByte) & 0xFF)
			end
			stream:seek(-bpp)
			self.pixels[i] = Pixel(stream, depth, colorType, palette, trns)
		end
	elseif self.filterType == 2 then
		for i = 1, length do
			for _ = 1, bpp do
				local curByte = stream:readByte()
				stream:seek(-(bpl+2))
				local lastByte = stream:readByte() or 0
				stream:seek(bpl)
				stream:writeByte((curByte + lastByte) & 0xFF)
			end
			stream:seek(-bpp)
			self.pixels[i] = Pixel(stream, depth, colorType, palette, trns)
		end
	elseif self.filterType == 3 then
		for i = 1, length do
			for _ = 1, bpp do
				local curByte = stream:readByte()
				stream:seek(-(bpp+1))
				local lastByte = 0
				if stream.position >= startLoc then lastByte = stream:readByte() or 0 else stream:readByte() end
				stream:seek(-(bpl)+bpp-2)
				local priByte = stream:readByte() or 0
				stream:seek(bpl)
				stream:writeByte((curByte + ((lastByte + priByte) >> 1)) & 0xFF)
			end
			stream:seek(-bpp)
			self.pixels[i] = Pixel(stream, depth, colorType, palette, trns)
		end
	elseif self.filterType == 4 then
		for i = 1, length do
			for _ = 1, bpp do
				local curByte = stream:readByte()
				stream:seek(-(bpp+1))
				local lastByte = 0
				if stream.position >= startLoc then lastByte = stream:readByte() or 0 else stream:readByte() end
				stream:seek(-(bpl + 2 - bpp))
				local priByte = stream:readByte() or 0
				stream:seek(-(bpp+1))
				local lastPriByte = 0
				if stream.position >= startLoc - (length * bpp + 1) then lastPriByte = stream:readByte() or 0 else stream:readByte() end
				stream:seek(bpl + bpp)
				stream:writeByte((curByte + self:_PaethPredict(lastByte, priByte, lastPriByte)) & 0xFF)
			end
			stream:seek(-bpp)
			self.pixels[i] = Pixel(stream, depth, colorType, palette, trns)
		end
	else
		error ('Invalid colortype:' .. colorType)
	end
end

function ScanLine:bitFromColorType(colorType)
	if colorType == 0 then return 1
	elseif colorType == 2 then return 3
	elseif colorType == 3 then return 1
	elseif colorType == 4 then return 2
	elseif colorType == 6 then return 4 end
	error ('Invalid colortype:' .. colorType)
end

function ScanLine:getPixel(pixel)
	return self.pixels[pixel]
end

--Stolen right from w3.
function ScanLine:_PaethPredict(a, b, c)
	local p = a + b - c
	local varA = math.abs(p - a)
	local varB = math.abs(p - b)
	local varC = math.abs(p - c)
	if varA <= varB and varA <= varC then return a end
	if varB <= varC then return b end
	return c
end

local pngImage = class()
pngImage.__name = "PNG"

function pngImage:__init(path, progCallback)
	local str = Stream({inputF = path})
	if str:readChars(8) ~= "\137\080\078\071\013\010\026\010" then error 'Not a PNG' end
	local ihdr
	local plte
	local trns
	local idat = {}
	local text = {}
	while true do
		local ch = Chunk(str)
		if ch.name == "IHDR" then ihdr = IHDR(ch)
		elseif ch.name == "PLTE" then plte = PLTE(ch)
		elseif ch.name == "tRNS" then trns = tRNS(ch, ihdr.colorType, plte)
		elseif ch.name == "IDAT" then table.insert(idat, IDAT(ch))
		elseif ch.name == "tEXt" then table.insert(text, tEXt(ch))
		elseif ch.name == "IEND" then break end
	end
	self.width = ihdr.width
	self.height = ihdr.height
	self.depth = ihdr.bitDepth
	self.colorType = ihdr.colorType
	self.scanLines = {}
	self.text_tbl = {}

	local datas = {}
	for i, v in ipairs(idat) do datas[i] = v.data end
	local output = {}
	deflate.inflate_zlib {input = table.concat(datas), output = function(byte) output[#output+1] = string.char(byte) end, disable_crc = true}
	local imStr = Stream({input = table.concat(output)})

	for i = 1, self.height do
		self.scanLines[i] = ScanLine(imStr, self.depth, self.colorType, plte, trns, self.width)
		if progCallback ~= nil then progCallback(i, self.height) end
	end

	for _, v in ipairs(text) do
		self.text_tbl[v.key] = v.value
	end
end

function pngImage:getPixel(x, y)
	local pixel = self.scanLines[y].pixels[x]
	return pixel
end

return pngImage

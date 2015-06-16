local usb_transfer_type_f = Field.new("usb.transfer_type")
local usb_direction_f = Field.new("usb.endpoint_number.direction")
local usb_capdata_f = Field.new("usb.capdata")


--for k,v in pairs(Field.list()) do print(k,v) end

local usbtap = Listener.new("usb")

local outdata = ByteArray.new()
local indata = ByteArray.new()

function usbtap.packet(pinfo, tvb, usbp)
   if usb_transfer_type_f().value ~= 3 then
      return
   end

   local content = usb_capdata_f()

   if not content then
      return
   end

   content = content.value

   if usb_direction_f().value == 1 and tostring(pinfo.dst) == "host" and content:len() > 2 then
      content = content:subset(2,content:len()-2)
      indata:append(content)
   end

   if usb_direction_f().value == 0 and tostring(pinfo.src) == "host" then
      outdata:append(content)
   end
end

BBuf = {}
BBuf.__index = BBuf
function BBuf.new(ba)
   local self = setmetatable({}, BBuf)
   self.value = ba
   self.pos = 0
   return self
end

function BBuf:skip(len)
   self.pos = self.pos + len
end

function BBuf:eof()
   return self.pos >= self.value:len()
end

function BBuf:peek_uint8()
   local v = self.value:get_index(self.pos)
   return v
end

function BBuf:read_uint8()
   local v = self:peek_uint8()
   self:skip(1)
   return v
end

function BBuf:read_uint16()
   local bl = self:read_uint8()
   local bh = self:read_uint8()
   return bl + bh * 256
end

function usbtap.draw()
   outdata = BBuf.new(outdata)
   indata = BBuf.new(indata)

   while not outdata:eof() do
      local opb = outdata:read_uint8()

      local ops = {
         [0x19] = function()
            local len = outdata:read_uint16() + 1
            print("data out bytes", len)
            outdata:skip(len)
         end,
         [0x1b] = function()
            local len = outdata:read_uint8()
            local outval = outdata:read_uint8()
            print("data out bits", len, "outval", outval)
         end,
         [0x28] = function()
            local len = outdata:read_uint16() + 1
            print("data in bytes", len)
            indata:skip(len)
         end,
         [0x2a] = function()
            local len = outdata:read_uint8() + 1
            local inval = indata:read_uint8()
            print("data in bits", len, "inval", inval)
         end,
         [0x39] = function()
            local len = outdata:read_uint16() + 1
            print("data in out bytes", len)
            outdata:skip(len)
            indata:skip(len)
         end,
         [0x3b] = function()
            local len = outdata:read_uint8() + 1
            local outval = outdata:read_uint8()
            local inval = indata:read_uint8()
            print("data in out bits", len, "outval", outval, "inval", inval)
         end,
         [0x4b] = function()
            local len = outdata:read_uint8() + 1
            local val = outdata:read_uint8()
            print("tms data out len", len, "val", val)
         end,
         [0x6b] = function()
            local len = outdata:read_uint8() + 1
            local outval = outdata:read_uint8()
            local inval = indata:read_uint8()
            print("tms data inout len", len, "outval", outval, "inval", inval)
         end,
         [0x80] = function()
            local val = outdata:read_uint8()
            local dir = outdata:read_uint8()
            print("set lo", val, dir)
         end,
         [0x82] = function()
            local val = outdata:read_uint8()
            local dir = outdata:read_uint8()
            print("set hi", val, dir)
         end,
         [0x85] = function()
            print("disconnect loopback")
         end,
         [0x86] = function()
            local div = outdata:read_uint16()
            print("set tck divisor", div)
         end,
         [0x87] = function()
            print("flush")
         end,
         [0x8a] = function()
            print("disable clk divide")
         end,
         [0x8d] = function()
            print("disable 3 phase data clocking")
         end,
         [0x97] = function()
            print("disable adaptive clocking")
         end,
      }

      if ops[opb] then
         if not pcall(ops[opb], outdata) then
            print(("error processing op %02x"):format(opb))
            print("outpos", outdata.pos, outdata.value:len())
            print("inpos", indata.pos, indata.value:len())
         end
      else
         if indata:peek_uint8() == 0xfa then
            indata:read_uint8()
            print(string.format("invalid op %02x", opb))
            if indata:read_uint8() ~= opb then
               print("no error from ftdi")
            end
         else
            print(string.format("unknown op %02x", opb))
         end
      end
   end
end

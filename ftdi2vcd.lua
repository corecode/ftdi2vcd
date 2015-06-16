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

function usbtap.draw()
   local ftdi = FTDI.new(outdata, indata)

   ftdi:process()
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


FTDI = {}
FTDI.__index = FTDI

function FTDI.new(outdata, indata)
   local self = setmetatable({}, FTDI)
   self.o = BBuf.new(outdata)
   self.i = BBuf.new(indata)
   return self
end

function FTDI:cmd_19()
   local len = self.o:read_uint16() + 1
   print("data out bytes", len)
   self.o:skip(len)
end

function FTDI:cmd_1b()
   local len = self.o:read_uint8()
   local outval = self.o:read_uint8()
   print("data out bits", len, "outval", outval)
end

function FTDI:cmd_28()
   local len = self.o:read_uint16() + 1
   print("data in bytes", len)
   self.i:skip(len)
end

function FTDI:cmd_2a()
   local len = self.o:read_uint8() + 1
   local inval = self.i:read_uint8()
   print("data in bits", len, "inval", inval)
end

function FTDI:cmd_39()
   local len = self.o:read_uint16() + 1
   print("data in out bytes", len)
   self.o:skip(len)
   self.i:skip(len)
end

function FTDI:cmd_3b()
   local len = self.o:read_uint8() + 1
   local outval = self.o:read_uint8()
   local inval = self.i:read_uint8()
   print("data in out bits", len, "outval", outval, "inval", inval)
end

function FTDI:cmd_4b()
   local len = self.o:read_uint8() + 1
   local val = self.o:read_uint8()
   print("tms data out len", len, "val", val)
end

function FTDI:cmd_6b()
   local len = self.o:read_uint8() + 1
   local outval = self.o:read_uint8()
   local inval = self.i:read_uint8()
   print("tms data inout len", len, "outval", outval, "inval", inval)
end

function FTDI:cmd_80()
   local val = self.o:read_uint8()
   local dir = self.o:read_uint8()
   print("set lo", val, dir)
end

function FTDI:cmd_82()
   local val = self.o:read_uint8()
   local dir = self.o:read_uint8()
   print("set hi", val, dir)
end

function FTDI:cmd_85()
   print("disconnect loopback")
end

function FTDI:cmd_86()
   local div = self.o:read_uint16()
   print("set tck divisor", div)
end

function FTDI:cmd_87()
   print("flush")
end

function FTDI:cmd_8a()
   print("disable clk divide")
end

function FTDI:cmd_8d()
   print("disable 3 phase data clocking")
end

function FTDI:cmd_97()
   print("disable adaptive clocking")
end

function FTDI:cmd_unknown(opb)
   if self.i:peek_uint8() == 0xfa then
      self.i:read_uint8()
      print(string.format("invalid op %02x", opb))
      if self.i:read_uint8() ~= opb then
         print("no error from ftdi")
      end
   else
      print(string.format("unknown op %02x", opb))
   end
end

function FTDI:process()
   while not self.o:eof() do
      local opb = self.o:read_uint8()

      local fun = self[("cmd_%02x"):format(opb)]
      if not fun then
         fun = self["cmd_unknown"]
      end

      if not pcall(fun, self, opb) then
         print(("error processing op %02x"):format(opb))
         print("outpos", self.o.pos, self.o.value:len())
         print("inpos", self.i.pos, self.i.value:len())
      end
   end
end

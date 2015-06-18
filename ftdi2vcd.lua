-- ftdi2vcd - wireshark plugin to convert FTDI MPSSE captures to VCD signal dumps
--
-- Copyright (c) 2015 Simon Schubert <2@0x2c.org>.
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU Affero General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU Affero General Public License for more details.
--
--    You should have received a copy of the GNU Affero General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.



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

FTDI.pinmap = { CLK = 0, TDI = 1, TDO = 2, TMS = 3 }

function FTDI.new(outdata, indata)
   local self = setmetatable({}, FTDI)
   self.o = BBuf.new(outdata)
   self.i = BBuf.new(indata)
   self.time = 0
   self.pinstate = { "X", "X", "X", "X", "X", "X", "X", "X",
                     "X", "X", "X", "X", "X", "X", "X", "X" }
   return self
end

function FTDI:cmd_19()
   local len = self.o:read_uint16() + 1
   self:comment("data out bytes", len)
   for i = 1, len do
      local val = self.o:read_uint8()
      self:clock(8, {TDI = val})
   end
end

function FTDI:cmd_1b()
   local len = self.o:read_uint8()
   local outval = self.o:read_uint8()
   self:comment("data out bits", len, "outval", outval)
   self:clock(len, {TDI = outval})
end

function FTDI:cmd_28()
   local len = self.o:read_uint16() + 1
   self:comment("data in bytes", len)
   for i = 1, len do
      local val = self.i:read_uint8()
      self:clock(8, {TDO = val})
   end
end

function FTDI:cmd_2a()
   local len = self.o:read_uint8() + 1
   local inval = self.i:read_uint8()
   self:comment("data in bits", len, "inval", inval)
   self:clock(len, {TDO = inval})
end

function FTDI:cmd_39()
   local len = self.o:read_uint16() + 1
   self:comment("data in out bytes", len)
   for i = 1, len do
      local outval = self.o:read_uint8()
      local inval = self.i:read_uint8()
      self:clock(8, {TDI = outval, TDO = inval})
   end
end

function FTDI:cmd_3b()
   local len = self.o:read_uint8() + 1
   local outval = self.o:read_uint8()
   local inval = self.i:read_uint8()
   self:comment("data in out bits", len, "outval", outval, "inval", inval)
   self:clock(len, {TDI = outval, TDO = inval})
end

function FTDI:cmd_4b()
   local len = self.o:read_uint8() + 1
   local val = self.o:read_uint8()
   self:comment("tms data out len", len, "val", val)
   self:set("TDI", bit32.extract(val, 7))
   self:clock(len, {TMS = val})
end

function FTDI:cmd_6b()
   local len = self.o:read_uint8() + 1
   local outval = self.o:read_uint8()
   local inval = self.i:read_uint8()
   self:comment("tms data inout len", len, "outval", outval, "inval", inval)
   self:set("TDI", bit32.extract(outval, 7))
   self:clock(len, {TMS = outval, TDO = inval})
end

function FTDI:cmd_80()
   local val = self.o:read_uint8()
   local dir = self.o:read_uint8()
   self:setpins(0, val, dir)
end

function FTDI:cmd_82()
   local val = self.o:read_uint8()
   local dir = self.o:read_uint8()
   self:setpins(1, val, dir)
end

function FTDI:cmd_85()
   -- print("disconnect loopback")
end

function FTDI:cmd_86()
   local div = self.o:read_uint16()
   self:comment("set tck divisor", div)
end

function FTDI:cmd_87()
   -- self:comment("flush")
end

function FTDI:cmd_8a()
   self:comment("disable clk divide")
end

function FTDI:cmd_8d()
   -- self:comment("disable 3 phase data clocking")
end

function FTDI:cmd_97()
   -- self:comment("disable adaptive clocking")
end

function FTDI:cmd_unknown(opb)
   if self.i:peek_uint8() == 0xfa then
      self.i:read_uint8()
      self:comment(string.format("invalid op %02x", opb))
      if self.i:read_uint8() ~= opb then
         print("no error from ftdi")
      end
   else
      self:comment(string.format("unknown op %02x", opb))
   end
end

function FTDI:process()
   for i = 0, 15 do
      local name = i
      for k, v in pairs(self.pinmap) do
         if v == i then
            name = k
         end
      end
      print(("$var wire 1 %d %s $end"):format(i, name))
   end
   print("$enddefinitions $end")

   while not self.o:eof() do
      local opb = self.o:read_uint8()

      local fun = self[("cmd_%02x"):format(opb)]
      if not fun then
         fun = self["cmd_unknown"]
      end

      -- if not pcall(fun, self, opb) then
      --    print(("error processing op %02x"):format(opb))
      --    print("outpos", self.o.pos, self.o.value:len())
      --    print("inpos", self.i.pos, self.i.value:len())
      -- end
      fun(self, opb)
   end
end

function FTDI:set(sig, val)
   if self.pinmap[sig] then
      sig = self.pinmap[sig]
   end

   if self.pinstate[sig + 1] == val then
      return
   end

   self.pinstate[sig + 1] = val

   print(("%d%s"):format(val, sig))
end

function FTDI:time_passes()
   self.time = self.time + 5
   print(("#%d"):format(self.time))
end

function FTDI:clock(len, sigs)
   for i = 0, len - 1 do
      for k, v in pairs(sigs) do
         self:set(k, bit32.extract(v, i))
      end
      self:set("CLK", 0)
      self:time_passes()
      self:set("CLK", 1)
      self:time_passes()
   end
end

function FTDI:setpins(hi, val, mask)
   for i = 0, 7 do
      if bit32.extract(mask, i) == 1 then
         self:set(i + hi * 8, bit32.extract(val, i))
      end
   end
end

function FTDI:comment(...)
   local str = table.concat({...},"\t")
   print(("$comment %s $end"):format(str))
end

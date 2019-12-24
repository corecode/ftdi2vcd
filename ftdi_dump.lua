-- ftdi_dump - wireshark plugin to dump FTDI MPSSE captures.  in case ftdi2vcd is too slow.
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
local usb_direction_f = Field.new("usb.endpoint_address.direction")
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
   print("out:", outdata)
   print("in:", indata)
end

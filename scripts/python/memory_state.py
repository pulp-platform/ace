from common import MemoryRange
from typing import List
import pdb

class MemoryState:
  def __init__(
      self,
      mem_ranges: List[MemoryRange] = []
    ):
    self.mem_ranges: List[MemoryRange] = mem_ranges

  def gen_rand_mem(self):
    for mem_range in self.mem_ranges:
      mem_range.init_random_mem()

  def store(self, addr, data):
    range_found = False
    for mem_range in self.mem_ranges:
      if mem_range.start_addr <= addr <= mem_range.end_addr:
        range_found = True
        mem_range.mem_data[addr - mem_range.start_addr] = data
    if not range_found:
      raise Exception("Provided an address outside the memory range(s)")

  def reconstruct_mem(
      self,
      file,
      start_time,
      end_time
  ) -> int:
    """
    Updates memory given the transactions in a file.
    Returns the time stamp that was the first one that was not updated.
    """
    with open(file, "r") as mem_file:
      for line in mem_file:
        words = line.split()
        time = -1
        addr = None
        data = None
        for word in words:
          t_idx = word.find("TIME:")
          a_idx = word.find("ADDR:")
          d_idx = word.find("DATA:")
          payload = word.split(":")[1]
          if t_idx != -1:
            time = int(payload)
          if a_idx != -1:
            addr = int(payload, 16)
          if d_idx != -1:
            data = int(payload, 16)
        if time > end_time:
          return time
        if (time < start_time) and time != -1:
          continue
        if (addr is not None) and (data is not None):
          self.store(addr, data)
        elif (addr is not None) or (data is not None):
          raise Exception(
            "Either data or addr provided without the other"
          )

  def save_mem(
    self,
    file="main_mem.mem",
    ):
    with open(file, "w") as mem_file:
      mem_file.write("@0\n")
      for mem_range in self.mem_ranges:
        for addr in range(mem_range.start_addr, mem_range.end_addr, 4):
          fmt = "{:2x} {:2x} {:2x} {:2x}\n".format(
            mem_range.mem_data[addr - mem_range.start_addr],
            mem_range.mem_data[addr - mem_range.start_addr + 1],
            mem_range.mem_data[addr - mem_range.start_addr + 2],
            mem_range.mem_data[addr - mem_range.start_addr + 3]
          )
          mem_file.write(fmt)

from common import MemoryRange
from typing import List

class MemoryState:
  def __init__(
      self,
      mem_ranges: List[MemoryRange]
    ):
    self.mem_ranges: List[MemoryRange] = mem_ranges

  def gen_rand_mem(self):
    for mem_range in self.mem_ranges:
      mem_range.init_mem()

  def save_rand_mem(
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
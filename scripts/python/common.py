import numpy as np
from typing import List

class MemoryRange:
  def __init__(
      self,
      cached: bool,
      start_addr: int,
      end_addr: int
  ):
    # Whether memory range is cached
    self.cached = cached
    # Start address of the range (inclusive)
    self.start_addr = start_addr
    # End address of the range (non-inclusive)
    self.end_addr = end_addr
    self.mem_data = []

  def init_mem(self):
    self.mem_data = np.random.randint(
      0, 256, size=(self.end_addr-self.start_addr),
      dtype=np.uint8)


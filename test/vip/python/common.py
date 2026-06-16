import numpy as np
from random import randrange
from typing import List

class MemoryRange:
  def __init__(
      self,
      start_addr: int,
      end_addr: int,
      cached: bool = False,
      shared: bool = False,
  ):
    """
    Parameters
    ==========
      start_addr Start address.\n
      end_addr End address.\n
      cached Set whole range as cached.\n
      shared Set whole range as shared.\n
    """

    # Start address of the range (inclusive)
    self.start_addr = start_addr
    # End address of the range (non-inclusive)
    self.end_addr = end_addr
    # Data
    self.mem_data = []
    # Subrange that is cached
    self.cached_region: MemoryRange = None
    # Subrange that is shared
    self.shared_region: MemoryRange = None

    if cached:
      self.set_cached_region(start_addr, end_addr)
    if shared:
      self.set_shared_region(start_addr, end_addr)

  def init_random_mem(self):
    self.mem_data = np.random.randint(
      0, 256, size=(self.end_addr-self.start_addr),
      dtype=np.uint8)

  def init_zero_mem(self):
    self.mem_data = np.zeros(
      size=(self.end_addr-self.start_addr),
      dtype=np.uint8)

  def set_cached_region(self, start_addr, end_addr):
    self.cached_region = MemoryRange(
      start_addr=start_addr,
      end_addr=end_addr
    )

  def set_shared_region(self, start_addr, end_addr):
    self.shared_region = MemoryRange(
      start_addr=start_addr,
      end_addr=end_addr
    )

  def get_addr_properties(self, addr):
    """Get whether address is cached and/or shared
    Returns (cached, shared)
    """
    cached = False
    shared = False
    if self.cached_region:
      if self.cached_region.start_addr <= addr <= self.cached_region.end_addr:
        cached = True
    if self.shared_region:
      if self.shared_region.start_addr <= addr \
        <= self.shared_region.end_addr:
        shared = True
    return cached, shared

  def get_rand_addr(self, step):
    return randrange(self.start_addr, self.end_addr, step)

  def get_rand_cached_addr(self, step):
    return randrange(
      self.cached_region.start_addr,
      self.cached_region.end_addr,
      step) 

  def get_rand_shared_addr(self, step):
    return randrange(
      self.shared_region.start_addr,
      self.shared_region.end_addr,
      step) 

  def get_rand_cached_shared_addr(self, step):
    if (not self.cached_region) or (not self.shared_region):
      raise Exception("Either cached or shared region is missing")
    if (self.cached_region.start_addr <=
      self.shared_region.start_addr):
      start_addr = self.shared_region.start_addr
    else:
      start_addr = self.cached_region.start_addr
    if (self.cached_region.end_addr >= 
        self.shared_region.end_addr):
      end_addr = self.shared_region.end_addr
    else:
      end_addr = self.cached_region.end_addr
    if end_addr < start_addr:
      raise Exception("No overlapping shared and cached regions")
    return randrange(start_addr, end_addr, step)

  def get_data(self, addr, len):
    """Return an array of length len, consisting of bytes"""
    data = []
    start_idx = addr - self.start_addr
    end_idx = start_idx + len
    for i in range(start_idx, end_idx):
      data.append(self.mem_data[i])
    return data
      


from common import MemoryRange
from typing import List
from math import log2
from random import random, randint, choices
import numpy as np
from enum import Enum

class StateBits(Enum):
  VALID_IDX = 0
  SHARED_IDX = 1
  DIRTY_IDX = 2

class CachelineStateGen:
  def __init__(
      self,
      modified_prob = 0.1,
      owned_prob = 0.1,
      exclusive_prob = 0.1,
      shared_prob = 0.1,
      invalid_prob = 0.6
      ):
    self.modified_prob = modified_prob
    self.owned_prob = owned_prob
    self.exclusive_prob = exclusive_prob
    self.shared_prob = shared_prob
    self.invalid_prob = invalid_prob

    assert(self.modified_prob + self.owned_prob + \
          self.exclusive_prob + self.shared_prob + \
          self.invalid_prob == 1.0)

    self.state_probs = {
        CachelineState.MODIFIED: self.modified_prob,
        CachelineState.OWNED: self.owned_prob,
        CachelineState.EXCLUSIVE: self.exclusive_prob,
        CachelineState.SHARED: self.shared_prob,
        CachelineState.INVALID: self.invalid_prob,
    }

  def random(self):
    return choices(
      population=list(self.state_probs.keys()),
      weights=list(self.state_probs.values()),
      k=1
    )[0]

class CachelineState(Enum):
  MODIFIED = 0
  OWNED = 1
  EXCLUSIVE = 2
  SHARED = 3
  INVALID = 4

class CacheSetFullException(Exception):
  pass

class CacheState:
  def __init__(
      self,
      addr_width,
      data_width,
      word_width,
      cacheline_words,
      ways,
      sets 
    ):
    self.aw = addr_width
    self.dw = data_width
    self.word_width = word_width
    self.cacheline_words = cacheline_words
    self.ways = ways
    self.sets = sets

    self.bytes_per_word = self.dw // 8
    self.cacheline_bytes = \
      self.cacheline_words * self.word_width // 8
    self.block_offset_bits = int(log2(self.cacheline_bytes))
    self.index_bits = int(log2(self.sets))
    self.tag_bits = \
      self.aw - self.block_offset_bits - self.index_bits

    self.index_mask = ((1 << self.index_bits) - 1) << self.block_offset_bits

    self.cache_status = self.sets * [self.ways * [3 * [None]]]
    self.cache_data = self.sets * [self.ways * [self.cacheline_bytes * [None]]]
    self.cache_tag  = self.sets * [self.ways * [None]]

  def init_cache(self):
    for set in range(self.sets):
      for way in range(self.ways):
        self.cache_status[set][way][StateBits.VALID_IDX.value] = False
        self.cache_status[set][way][StateBits.SHARED_IDX.value] = False
        self.cache_status[set][way][StateBits.DIRTY_IDX.value] = False
        self.cache_tag[set][way] = 0
        for byte in range(self.cacheline_bytes):
          self.cache_data[set][way][byte] = 0

  def get_index(self, addr):
    return (addr & self.index_mask) >> self.block_offset_bits

  def get_free_way(self, set):
    """Get first free (non-valid) way in a set."""
    was_free = False
    way_idx = 0
    for i, way in enumerate(self.cache_status[set]):
      if not way[StateBits.VALID_IDX.value]:
        way_idx = i
        was_free = True
        break
    return way_idx, was_free

  def set_entry(
      self,
      addr: int,
      data: np.ndarray,
      status: List[bool]
    ):
    """Write cacheline corresponding to addr with data and status.
    Assumes we write the whole cache line byte-by-byte
    """
    set_idx = self.get_index(addr)
    way_idx, was_free = self.get_free_way(set_idx)
    if not was_free:
      raise CacheSetFullException
    for byte_idx in range(self.cacheline_bytes):
      self.cache_data[set_idx][way_idx][byte_idx] = \
        data[byte_idx]
    self.cache_status[set_idx][way_idx] = status

  def save_data(
    self,
    file
  ):
    with open(file, "wb") as data_file:
      for set in range(self.sets):
        for way in range(self.ways):
          b_data = bytearray(self.cache_data[set][way])
          data_file.write(b_data)

  # TODO: ensure width
  def save_tag(
    self,
    file
  ):
    with open(file, "wb") as tag_file:
      for set in range(self.sets):
        b_data = bytearray(self.cache_tag[set])
        tag_file.write(b_data)

  def save_status(
    self,
    file
  ):
    with open(file, "wb") as state_file:
      for set in range(self.sets):
        for way in range(self.ways):
          b_data = bytearray(self.cache_status[set][way])
          state_file.write(b_data)

  def save_state(
      self,
      data_file="data_mem.mem",
      tag_file="tag_mem.mem",
      state_file="state.mem"
  ):
    self.save_data(data_file)
    self.save_tag(tag_file)
    self.save_status(state_file)

